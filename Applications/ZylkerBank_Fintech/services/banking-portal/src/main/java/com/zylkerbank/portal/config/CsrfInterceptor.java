package com.zylkerbank.portal.config;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.MediaType;
import org.springframework.web.servlet.HandlerInterceptor;

import java.util.Set;
import java.util.UUID;

public class CsrfInterceptor implements HandlerInterceptor {

    public static final String CSRF_SESSION_ATTR = "_CSRF_TOKEN";
    public static final String CSRF_REQ_ATTR = "csrfToken";

    private static final Set<String> PROTECTED_METHODS = Set.of("POST", "PUT", "DELETE", "PATCH");

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        HttpSession session = request.getSession(true);
        String sessionToken = (String) session.getAttribute(CSRF_SESSION_ATTR);

        if (sessionToken == null) {
            sessionToken = UUID.randomUUID().toString();
            session.setAttribute(CSRF_SESSION_ATTR, sessionToken);
        }

        // Always make CSRF token available to templates
        request.setAttribute(CSRF_REQ_ATTR, sessionToken);

        String method = request.getMethod();
        if (PROTECTED_METHODS.contains(method)) {
            String paramToken = request.getParameter("_csrf");
            String headerToken = request.getHeader("X-CSRF-TOKEN");
            if (headerToken == null) {
                headerToken = request.getHeader("X-CSRF-Token");
            }
            if (headerToken == null) {
                headerToken = request.getHeader("X-XSRF-TOKEN");
            }

            String clientToken = (paramToken != null) ? paramToken : headerToken;

            // Allow bypass only for health check endpoints or if specifically whitelisted
            String uri = request.getRequestURI();
            if (uri.startsWith("/health") || uri.startsWith("/actuator/")) {
                return true;
            }

            if (clientToken == null || !clientToken.equals(sessionToken)) {
                boolean isApi = uri.startsWith("/api/") ||
                        (request.getHeader("Accept") != null && request.getHeader("Accept").contains(MediaType.APPLICATION_JSON_VALUE));

                response.setStatus(HttpServletResponse.SC_FORBIDDEN);
                if (isApi) {
                    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                    response.getWriter().write("{\"error\":\"INVALID_CSRF_TOKEN\",\"message\":\"CSRF token missing or invalid\"}");
                } else {
                    response.sendError(HttpServletResponse.SC_FORBIDDEN, "Invalid or missing CSRF token");
                }
                return false;
            }
        }

        return true;
    }
}
