package com.site24x7.labs.chaos.spring;

import com.site24x7.labs.chaos.engine.ChaosEngine;
import com.site24x7.labs.chaos.fault.http.HttpFaultInjector;
import com.site24x7.labs.chaos.fault.httpclient.HttpClientFaultInjector;
import com.site24x7.labs.chaos.fault.jdbc.ChaosDataSourceProxy;
import com.site24x7.labs.chaos.fault.jdbc.JdbcFaultInjector;
import com.site24x7.labs.chaos.fault.redis.RedisFaultInjector;
import com.site24x7.labs.chaos.fault.resource.ResourceFaultInjector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import javax.sql.DataSource;
import java.util.ArrayList;
import java.util.List;

/**
 * Auto-configuration for the Chaos SDK.
 * Automatically registers:
 * - ChaosEngine (config watcher + fault evaluator)
 * - ChaosServletFilter (inbound HTTP fault injection)
 * - HttpClientFaultInjector + RestTemplate interceptor (outbound HTTP fault injection)
 * - JdbcFaultInjector + DataSource BeanPostProcessor (JDBC fault injection + pool drain)
 * - RedisFaultInjector + RedisConnectionFactory BeanPostProcessor (Redis fault injection, conditional)
 * - ResourceFaultInjector (thread/memory/CPU exhaustion, triggered on config update)
 */
@Configuration
@ConditionalOnProperty(name = "chaos.enabled", havingValue = "true", matchIfMissing = true)
@EnableConfigurationProperties(ChaosProperties.class)
public class ChaosAutoConfiguration {

    private static final Logger log = LoggerFactory.getLogger(ChaosAutoConfiguration.class);

    @Bean
    public ChaosEngine chaosEngine(ChaosProperties properties) {
        com.site24x7.labs.chaos.config.ChaosProperties coreProps = new com.site24x7.labs.chaos.config.ChaosProperties();
        coreProps.setEnabled(properties.isEnabled());
        coreProps.setAppName(properties.getAppName());
        coreProps.setConfigFile(properties.getConfigFile());
        coreProps.setPollIntervalMs(properties.getPollIntervalMs());

        // Set framework info for heartbeat reporting
        coreProps.setFramework("spring-boot");
        coreProps.setFrameworkVersion(getSpringBootVersion());

        ChaosEngine engine = new ChaosEngine(coreProps);
        engine.start();
        return engine;
    }

    private static String getSpringBootVersion() {
        try {
            return org.springframework.boot.SpringBootVersion.getVersion();
        } catch (Exception e) {
            return "";
        }
    }

    // ---- Inbound HTTP ----

    @Bean
    public HttpFaultInjector httpFaultInjector(ChaosEngine engine) {
        return new HttpFaultInjector(engine);
    }

    @Bean
    public FilterRegistrationBean<ChaosServletFilter> chaosFilterRegistration(HttpFaultInjector injector) {
        FilterRegistrationBean<ChaosServletFilter> registration = new FilterRegistrationBean<>();
        registration.setFilter(new ChaosServletFilter(injector));
        registration.addUrlPatterns("/*");
        registration.setName("chaosServletFilter");
        registration.setOrder(Integer.MIN_VALUE + 100); // Run early but after security filters
        return registration;
    }

    // ---- Outbound HTTP (RestTemplate) ----

    @Bean
    public HttpClientFaultInjector httpClientFaultInjector(ChaosEngine engine) {
        return new HttpClientFaultInjector(engine);
    }

    @Bean
    public ChaosClientHttpRequestInterceptor chaosClientHttpRequestInterceptor(HttpClientFaultInjector injector) {
        return new ChaosClientHttpRequestInterceptor(injector);
    }

    /**
     * BeanPostProcessor that adds the chaos interceptor to all RestTemplate beans.
     */
    @Bean
    public BeanPostProcessor chaosRestTemplatePostProcessor(ChaosClientHttpRequestInterceptor interceptor) {
        return new BeanPostProcessor() {
            @Override
            public Object postProcessAfterInitialization(Object bean, String beanName) throws BeansException {
                if (bean instanceof RestTemplate restTemplate) {
                    log.info("Adding chaos interceptor to RestTemplate '{}'", beanName);
                    List<org.springframework.http.client.ClientHttpRequestInterceptor> interceptors =
                            new ArrayList<>(restTemplate.getInterceptors());
                    interceptors.add(interceptor);
                    restTemplate.setInterceptors(interceptors);
                }
                return bean;
            }
        };
    }

    // ---- JDBC ----

    @Bean
    public JdbcFaultInjector jdbcFaultInjector(ChaosEngine engine) {
        return new JdbcFaultInjector(engine);
    }

    @Bean
    public BeanPostProcessor chaosDataSourcePostProcessor(JdbcFaultInjector jdbcFaultInjector) {
        return new BeanPostProcessor() {
            @Override
            public Object postProcessAfterInitialization(Object bean, String beanName) throws BeansException {
                if (bean instanceof DataSource ds && !(bean instanceof ChaosDataSourceProxy)) {
                    log.info("Wrapping DataSource '{}' with ChaosDataSourceProxy", beanName);
                    return new ChaosDataSourceProxy(ds, jdbcFaultInjector);
                }
                return bean;
            }
        };
    }

    // ---- Redis (conditional on spring-data-redis) ----

    @Configuration
    @ConditionalOnClass(name = "org.springframework.data.redis.connection.RedisConnectionFactory")
    static class ChaosRedisAutoConfiguration {

        private static final Logger log = LoggerFactory.getLogger(ChaosRedisAutoConfiguration.class);

        @Bean
        public RedisFaultInjector redisFaultInjector(ChaosEngine engine) {
            return new RedisFaultInjector(engine);
        }

        @Bean
        public BeanPostProcessor chaosRedisConnectionFactoryPostProcessor(RedisFaultInjector redisFaultInjector) {
            return new BeanPostProcessor() {
                @Override
                public Object postProcessAfterInitialization(Object bean, String beanName) throws BeansException {
                    if (bean instanceof org.springframework.data.redis.connection.RedisConnectionFactory rcf
                            && !java.lang.reflect.Proxy.isProxyClass(bean.getClass())) {
                        log.info("Wrapping RedisConnectionFactory '{}' with chaos proxy", beanName);
                        return ChaosRedisConnectionFactoryProxy.wrap(rcf, redisFaultInjector);
                    }
                    return bean;
                }
            };
        }
    }

    // ---- Resource Exhaustion ----

    @Bean
    public ResourceFaultInjector resourceFaultInjector(ChaosEngine engine) {
        ResourceFaultInjector injector = new ResourceFaultInjector(engine);
        // Register as a config update listener so resource faults trigger on config changes
        engine.addConfigUpdateListener(injector::evaluateAndApply);
        return injector;
    }
}
