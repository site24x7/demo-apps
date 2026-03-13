// Site24x7 Labs Chaos SDK for .NET — Exception Class Mapping
//
// Maps canonical Java exception class names to .NET exception factories.
// The config always stores Java class names for cross-SDK consistency.

namespace Site24x7.Chaos;

/// <summary>
/// Maps canonical Java exception class names to .NET exception factories.
/// Used by HTTP, HTTP client, database, and Redis fault injectors.
/// </summary>
public static class ExceptionMap
{
    /// <summary>
    /// Factory delegate that creates an exception from a message string.
    /// </summary>
    public delegate Exception ExceptionFactory(string message);

    private static readonly Dictionary<string, ExceptionFactory> Map = new(StringComparer.Ordinal)
    {
        // --- General / Inbound HTTP ---
        ["java.lang.RuntimeException"] = msg => new InvalidOperationException(msg),
        ["java.lang.NullPointerException"] = msg => new NullReferenceException(msg ?? "Object reference not set"),
        ["java.lang.IllegalArgumentException"] = msg => new ArgumentException(msg),
        ["java.lang.IllegalStateException"] = msg => new InvalidOperationException(msg),
        ["java.lang.UnsupportedOperationException"] = msg => new NotSupportedException(msg),
        ["java.io.IOException"] = msg => new IOException(msg),
        ["java.util.concurrent.TimeoutException"] = msg => new TimeoutException(msg ?? "Operation timed out"),

        // --- Network / Socket ---
        ["java.net.SocketException"] = msg => new IOException($"Socket error: {msg}"),
        ["java.net.SocketTimeoutException"] = msg => new TimeoutException($"Socket timeout: {msg}"),
        ["java.net.ConnectException"] = msg => new IOException($"Connection refused: {msg}"),
        ["java.net.UnknownHostException"] = msg => new IOException($"Unknown host: {msg}"),

        // --- Spring / HTTP client ---
        ["org.springframework.web.client.ResourceAccessException"] = msg => new HttpRequestException($"Resource access error: {msg}"),
        ["org.springframework.web.client.HttpServerErrorException"] = msg => new HttpRequestException($"HTTP server error: {msg}"),
        ["org.springframework.web.client.HttpClientErrorException"] = msg => new HttpRequestException($"HTTP client error: {msg}"),
        ["ResourceAccessException"] = msg => new HttpRequestException($"Resource access error: {msg}"),
        ["HttpServerErrorException"] = msg => new HttpRequestException($"HTTP server error: {msg}"),
        ["HttpClientErrorException"] = msg => new HttpRequestException($"HTTP client error: {msg}"),

        // --- Database / JDBC ---
        ["java.sql.SQLException"] = msg => new InvalidOperationException($"SQL error: {msg}"),
        ["java.sql.SQLTimeoutException"] = msg => new TimeoutException($"SQL timeout: {msg}"),
        ["java.sql.SQLTransientConnectionException"] = msg => new InvalidOperationException($"SQL transient connection error: {msg}"),
        ["java.sql.SQLNonTransientConnectionException"] = msg => new InvalidOperationException($"SQL connection error: {msg}"),
        ["SQLTransientConnectionException"] = msg => new InvalidOperationException($"SQL transient connection error: {msg}"),
        ["org.postgresql.util.PSQLException"] = msg => new InvalidOperationException($"PostgreSQL error: {msg}"),

        // --- Redis ---
        ["redis.clients.jedis.exceptions.JedisConnectionException"] = msg => new IOException($"Redis connection error: {msg}"),
        ["RedisConnectionFailureException"] = msg => new IOException($"Redis connection failure: {msg}"),
        ["io.lettuce.core.RedisCommandTimeoutException"] = msg => new TimeoutException($"Redis command timeout: {msg}"),
        ["org.springframework.data.redis.RedisConnectionFailureException"] = msg => new IOException($"Redis connection failure: {msg}"),
        ["RedisSystemException"] = msg => new IOException($"Redis system error: {msg}"),
        ["RedisCommandTimeoutException"] = msg => new TimeoutException($"Redis command timeout: {msg}"),
        ["JedisConnectionException"] = msg => new IOException($"Redis connection error: {msg}"),
    };

    /// <summary>
    /// Resolve a canonical Java exception class name to a .NET exception.
    /// Returns a generic <see cref="InvalidOperationException"/> if unmapped.
    /// </summary>
    /// <param name="javaClassName">Canonical Java class name (e.g., "java.lang.RuntimeException").</param>
    /// <param name="message">Error message for the exception.</param>
    public static Exception Resolve(string javaClassName, string message)
    {
        if (Map.TryGetValue(javaClassName, out var factory))
        {
            return factory(message);
        }

        // Fallback: use the Java class name as context
        return new InvalidOperationException($"[{javaClassName}] {message}");
    }
}
