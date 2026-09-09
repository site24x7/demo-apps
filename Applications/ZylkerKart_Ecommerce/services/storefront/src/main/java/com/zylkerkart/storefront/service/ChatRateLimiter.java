package com.zylkerkart.storefront.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Simple in-memory per-session rate limiter for /api/chat.
 */
@Component
public class ChatRateLimiter {

    private final int maxRequests;
    private final long windowMs;
    private final Map<String, Deque<Long>> hits = new ConcurrentHashMap<>();

    public ChatRateLimiter(
            @Value("${services.ai.rate-limit-per-minute:10}") int maxRequests) {
        this.maxRequests = Math.max(1, maxRequests);
        this.windowMs = 60_000L;
    }

    public boolean tryAcquire(String sessionId) {
        String key = (sessionId == null || sessionId.isBlank()) ? "_anon" : sessionId;
        long now = System.currentTimeMillis();
        Deque<Long> q = hits.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (q) {
            while (!q.isEmpty() && now - q.peekFirst() > windowMs) {
                q.pollFirst();
            }
            if (q.size() >= maxRequests) {
                return false;
            }
            q.addLast(now);
            return true;
        }
    }
}
