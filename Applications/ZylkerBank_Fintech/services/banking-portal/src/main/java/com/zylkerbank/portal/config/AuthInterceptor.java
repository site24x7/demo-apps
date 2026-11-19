package com.zylkerbank.portal.config;

import com.zylkerbank.portal.model.UserSession;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.MediaType;
import org.springframework.web.servlet.HandlerInterceptor;

public class AuthInterceptor implements HandlerInterceptor {

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        HttpSession session = request.getSession(false);
        UserSession user = (session != null) ? (UserSession) session.getAttribute("user") : null;

        if (user != null && user.getToken() != null && !user.getToken().isBlank()) {
            // Expose user in request scope for Thymeleaf templates
            request.setAttribute("user", user);
            request.setAttribute("currentUser", user);
            return true;
        }

        String uri = request.getRequestURI();
        String accept = request.getHeader("Accept");
        boolean isApi = (uri != null && uri.startsWith("/api/")) || (accept != null && accept.contains(MediaType.APPLICATION_JSON_VALUE));

        if (isApi) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.getWriter().write("{\"error\":\"UNAUTHORIZED\",\"message\":\"Authentication required. Please log in.\"}");
            return false;
        }

        response.sendRedirect(request.getContextPath() + "/login");
        return false;
    }
}
