package com.site24x7.labs.chaos.spring;

import com.site24x7.labs.chaos.fault.http.HttpFaultInjector;
import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.FilterConfig;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;

/**
 * Servlet filter that intercepts HTTP requests to inject faults.
 * Registered automatically by ChaosAutoConfiguration.
 */
public class ChaosServletFilter implements Filter {

    private final HttpFaultInjector faultInjector;

    public ChaosServletFilter(HttpFaultInjector faultInjector) {
        this.faultInjector = faultInjector;
    }

    @Override
    public void init(FilterConfig filterConfig) {
        // No-op
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        if (request instanceof HttpServletRequest && response instanceof HttpServletResponse) {
            boolean faultApplied = faultInjector.applyFault(request, response);
            if (faultApplied) {
                return; // Fault handled the response, don't continue the chain
            }
        }
        chain.doFilter(request, response);
    }

    @Override
    public void destroy() {
        // No-op
    }
}
