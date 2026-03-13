package com.site24x7.labs.chaos.fault.jdbc;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.sql.DataSource;
import java.io.PrintWriter;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.SQLFeatureNotSupportedException;
import java.sql.Statement;
import java.sql.PreparedStatement;
import java.sql.CallableStatement;

/**
 * DataSource proxy that wraps connections to inject JDBC faults.
 * All SQL execution methods (execute, executeQuery, executeUpdate, executeBatch)
 * are intercepted to potentially inject faults before the real operation.
 */
public class ChaosDataSourceProxy implements DataSource {

    private static final Logger log = LoggerFactory.getLogger(ChaosDataSourceProxy.class);

    private final DataSource delegate;
    private final JdbcFaultInjector faultInjector;

    public ChaosDataSourceProxy(DataSource delegate, JdbcFaultInjector faultInjector) {
        this.delegate = delegate;
        this.faultInjector = faultInjector;
        // Allow the injector to acquire raw connections for pool drain
        faultInjector.setRealDataSource(delegate);
        log.info("ChaosDataSourceProxy wrapping: {}", delegate.getClass().getName());
    }

    @Override
    public Connection getConnection() throws SQLException {
        return wrapConnection(delegate.getConnection());
    }

    @Override
    public Connection getConnection(String username, String password) throws SQLException {
        return wrapConnection(delegate.getConnection(username, password));
    }

    private Connection wrapConnection(Connection realConnection) {
        return (Connection) Proxy.newProxyInstance(
                realConnection.getClass().getClassLoader(),
                new Class<?>[]{Connection.class},
                new ConnectionHandler(realConnection)
        );
    }

    /**
     * Connection proxy that wraps Statement/PreparedStatement/CallableStatement.
     */
    private class ConnectionHandler implements InvocationHandler {
        private final Connection realConnection;

        ConnectionHandler(Connection realConnection) {
            this.realConnection = realConnection;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            Object result = method.invoke(realConnection, args);

            // Wrap statement-producing methods
            String methodName = method.getName();
            if (result instanceof CallableStatement cs) {
                return wrapStatement(cs, CallableStatement.class);
            } else if (result instanceof PreparedStatement ps) {
                return wrapStatement(ps, PreparedStatement.class);
            } else if (result instanceof Statement s && "createStatement".equals(methodName)) {
                return wrapStatement(s, Statement.class);
            }

            return result;
        }
    }

    /**
     * Wraps a Statement (or subclass) to intercept execute methods.
     */
    private <T extends Statement> T wrapStatement(T realStatement, Class<T> iface) {
        @SuppressWarnings("unchecked")
        T proxy = (T) Proxy.newProxyInstance(
                realStatement.getClass().getClassLoader(),
                new Class<?>[]{iface},
                new StatementHandler(realStatement)
        );
        return proxy;
    }

    /**
     * Statement proxy that intercepts execute methods to inject faults.
     */
    private class StatementHandler implements InvocationHandler {
        private final Statement realStatement;

        StatementHandler(Statement realStatement) {
            this.realStatement = realStatement;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            String methodName = method.getName();

            // Intercept SQL execution methods
            if (isExecuteMethod(methodName)) {
                faultInjector.applyFault();
            }

            return method.invoke(realStatement, args);
        }

        private boolean isExecuteMethod(String name) {
            return "execute".equals(name)
                    || "executeQuery".equals(name)
                    || "executeUpdate".equals(name)
                    || "executeBatch".equals(name)
                    || "executeLargeUpdate".equals(name)
                    || "executeLargeBatch".equals(name);
        }
    }

    // --- Delegate remaining DataSource methods ---

    @Override
    public PrintWriter getLogWriter() throws SQLException {
        return delegate.getLogWriter();
    }

    @Override
    public void setLogWriter(PrintWriter out) throws SQLException {
        delegate.setLogWriter(out);
    }

    @Override
    public void setLoginTimeout(int seconds) throws SQLException {
        delegate.setLoginTimeout(seconds);
    }

    @Override
    public int getLoginTimeout() throws SQLException {
        return delegate.getLoginTimeout();
    }

    @Override
    public java.util.logging.Logger getParentLogger() throws SQLFeatureNotSupportedException {
        return delegate.getParentLogger();
    }

    @Override
    public <T> T unwrap(Class<T> iface) throws SQLException {
        if (iface.isInstance(this)) {
            return iface.cast(this);
        }
        return delegate.unwrap(iface);
    }

    @Override
    public boolean isWrapperFor(Class<?> iface) throws SQLException {
        return iface.isInstance(this) || delegate.isWrapperFor(iface);
    }
}
