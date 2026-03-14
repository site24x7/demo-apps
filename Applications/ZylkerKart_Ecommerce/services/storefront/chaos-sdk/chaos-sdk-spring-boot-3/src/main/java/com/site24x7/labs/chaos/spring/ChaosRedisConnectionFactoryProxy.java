package com.site24x7.labs.chaos.spring;

import com.site24x7.labs.chaos.fault.redis.RedisFaultInjector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.connection.RedisConnection;
import org.springframework.data.redis.connection.RedisConnectionFactory;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/**
 * JDK proxy wrapper around RedisConnectionFactory that injects Redis faults.
 * <p>
 * Intercepts getConnection() and getClusterConnection() to apply faults
 * before the actual Redis operation. The returned RedisConnection is also
 * proxied to inject faults on command execution.
 */
public class ChaosRedisConnectionFactoryProxy {

    private static final Logger log = LoggerFactory.getLogger(ChaosRedisConnectionFactoryProxy.class);

    /**
     * Wrap a RedisConnectionFactory with fault injection.
     * Returns a JDK proxy that implements RedisConnectionFactory.
     */
    public static RedisConnectionFactory wrap(RedisConnectionFactory delegate, RedisFaultInjector faultInjector) {
        log.info("Wrapping RedisConnectionFactory with chaos proxy: {}", delegate.getClass().getName());

        return (RedisConnectionFactory) Proxy.newProxyInstance(
                delegate.getClass().getClassLoader(),
                getAllInterfaces(delegate.getClass()),
                new ConnectionFactoryHandler(delegate, faultInjector)
        );
    }

    /**
     * Get all interfaces implemented by a class and its superclasses.
     */
    private static Class<?>[] getAllInterfaces(Class<?> clazz) {
        java.util.Set<Class<?>> interfaces = new java.util.LinkedHashSet<>();
        while (clazz != null) {
            for (Class<?> iface : clazz.getInterfaces()) {
                interfaces.add(iface);
            }
            clazz = clazz.getSuperclass();
        }
        return interfaces.toArray(new Class<?>[0]);
    }

    private static class ConnectionFactoryHandler implements InvocationHandler {
        private final RedisConnectionFactory delegate;
        private final RedisFaultInjector faultInjector;

        ConnectionFactoryHandler(RedisConnectionFactory delegate, RedisFaultInjector faultInjector) {
            this.delegate = delegate;
            this.faultInjector = faultInjector;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            String methodName = method.getName();

            // Inject faults before connection acquisition
            if ("getConnection".equals(methodName) || "getClusterConnection".equals(methodName)) {
                faultInjector.applyFault();
            }

            Object result = method.invoke(delegate, args);

            // Wrap the returned connection to also inject faults on commands
            if (result instanceof RedisConnection redisConn
                    && ("getConnection".equals(methodName) || "getClusterConnection".equals(methodName))) {
                return wrapConnection(redisConn);
            }

            return result;
        }

        private RedisConnection wrapConnection(RedisConnection realConnection) {
            return (RedisConnection) Proxy.newProxyInstance(
                    realConnection.getClass().getClassLoader(),
                    getAllInterfaces(realConnection.getClass()),
                    new RedisConnectionHandler(realConnection, faultInjector)
            );
        }
    }

    /**
     * Proxy for RedisConnection that injects faults on command execution methods.
     */
    private static class RedisConnectionHandler implements InvocationHandler {
        private final RedisConnection realConnection;
        private final RedisFaultInjector faultInjector;

        RedisConnectionHandler(RedisConnection realConnection, RedisFaultInjector faultInjector) {
            this.realConnection = realConnection;
            this.faultInjector = faultInjector;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            String methodName = method.getName();

            // Inject faults on Redis command methods (not lifecycle methods)
            if (!isLifecycleMethod(methodName)) {
                faultInjector.applyFault();
            }

            return method.invoke(realConnection, args);
        }

        private boolean isLifecycleMethod(String name) {
            return "close".equals(name)
                    || "isClosed".equals(name)
                    || "getNativeConnection".equals(name)
                    || "isQueueing".equals(name)
                    || "isPipelined".equals(name)
                    || "hashCode".equals(name)
                    || "equals".equals(name)
                    || "toString".equals(name);
        }
    }
}
