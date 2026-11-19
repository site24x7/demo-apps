package middleware

import (
	"log"
	"time"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/trace"
)

func StructuredLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		raw := c.Request.URL.RawQuery

		c.Next()

		latency := time.Since(start)
		statusCode := c.Writer.Status()
		clientIP := c.ClientIP()
		method := c.Request.Method

		if raw != "" {
			path = path + "?" + raw
		}

		traceID := ""
		spanCtx := trace.SpanFromContext(c.Request.Context()).SpanContext()
		if spanCtx.HasTraceID() {
			traceID = spanCtx.TraceID().String()
		}

		if traceID != "" {
			log.Printf("[HTTP] %d | %13v | %15s | %-7s %s | trace_id=%s",
				statusCode, latency, clientIP, method, path, traceID)
		} else {
			log.Printf("[HTTP] %d | %13v | %15s | %-7s %s",
				statusCode, latency, clientIP, method, path)
		}
	}
}
