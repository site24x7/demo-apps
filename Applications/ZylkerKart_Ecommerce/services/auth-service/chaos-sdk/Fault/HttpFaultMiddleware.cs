// Site24x7 Labs Chaos SDK for .NET — Inbound HTTP Fault Middleware
//
// ASP.NET Core middleware that intercepts incoming requests and injects
// 5 fault types:
//   1. http_exception       — Return the mapped .NET exception as a 500 response.
//   2. http_latency         — Delay before the request is handled.
//   3. http_error_response  — Return a static error status + body.
//   4. http_connection_reset— Abort the connection.
//   5. http_slow_body       — Stream a response body with inter-chunk delays.

using Microsoft.AspNetCore.Http;

namespace Site24x7.Chaos.Fault;

/// <summary>
/// ASP.NET Core middleware that evaluates inbound HTTP fault rules
/// and injects the first matching fault.
/// </summary>
public sealed class HttpFaultMiddleware : IMiddleware
{
    private const string FaultPrefix = "http_";
    private readonly ChaosEngine _engine;

    public HttpFaultMiddleware(ChaosEngine engine)
    {
        _engine = engine;
    }

    public async Task InvokeAsync(HttpContext context, RequestDelegate next)
    {
        if (!_engine.Enabled)
        {
            await next(context);
            return;
        }

        var path = context.Request.Path.Value ?? "/";
        var rules = _engine.FindMatchingRules(FaultPrefix, path);

        foreach (var rule in rules)
        {
            if (!_engine.ShouldFire(rule)) continue;

            switch (rule.FaultType)
            {
                case FaultTypes.HttpException:
                    await ApplyException(context, rule);
                    return;

                case FaultTypes.HttpLatency:
                    await ApplyLatency(rule);
                    // Fall through to next middleware after delay
                    await next(context);
                    return;

                case FaultTypes.HttpErrorResponse:
                    await ApplyErrorResponse(context, rule);
                    return;

                case FaultTypes.HttpConnectionReset:
                    ApplyConnectionReset(context);
                    return;

                case FaultTypes.HttpSlowBody:
                    await ApplySlowBody(context, rule);
                    return;

                default:
                    Console.Error.WriteLine($"[chaos-sdk] Unknown HTTP fault type: {rule.FaultType}");
                    break;
            }
        }

        // No fault fired — pass through
        await next(context);
    }

    // ------------------------------------------------------------------
    // Fault implementations
    // ------------------------------------------------------------------

    private static async Task ApplyException(HttpContext context, FaultRuleConfig rule)
    {
        var javaClass = ConfigHelpers.GetString(rule, "exception_class", "java.lang.RuntimeException");
        var message = ConfigHelpers.GetString(rule, "message", "Injected fault");

        Console.WriteLine($"[chaos-sdk] Injecting HTTP exception: {javaClass} - {message}");

        var ex = ExceptionMap.Resolve(javaClass, message);
        context.Response.StatusCode = 500;
        context.Response.ContentType = "text/plain";
        await context.Response.WriteAsync(ex.Message);
    }

    private static async Task ApplyLatency(FaultRuleConfig rule)
    {
        var delayMs = ConfigHelpers.GetInt(rule, "delay_ms", 1000);
        Console.WriteLine($"[chaos-sdk] Injecting HTTP latency: {delayMs}ms");
        await Task.Delay(delayMs);
    }

    private static async Task ApplyErrorResponse(HttpContext context, FaultRuleConfig rule)
    {
        var statusCode = ConfigHelpers.GetInt(rule, "status_code", 500);
        var body = ConfigHelpers.GetString(rule, "body", "Internal Server Error");

        Console.WriteLine($"[chaos-sdk] Injecting HTTP error response: {statusCode} - {body}");

        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "text/plain";
        await context.Response.WriteAsync(body);
    }

    private static void ApplyConnectionReset(HttpContext context)
    {
        Console.WriteLine("[chaos-sdk] Injecting HTTP connection reset");
        context.Abort();
    }

    private static async Task ApplySlowBody(HttpContext context, FaultRuleConfig rule)
    {
        var delayMs = ConfigHelpers.GetInt(rule, "delay_ms", 200);
        var chunkSize = ConfigHelpers.GetInt(rule, "chunk_size_bytes", 64);
        const int totalChunks = 32;

        Console.WriteLine($"[chaos-sdk] Injecting HTTP slow body: {delayMs}ms delay, {chunkSize} byte chunks");

        context.Response.StatusCode = 200;
        context.Response.ContentType = "text/plain";

        var chunk = new string('X', chunkSize);

        for (var i = 0; i < totalChunks; i++)
        {
            try
            {
                await context.Response.WriteAsync(chunk);
                await context.Response.Body.FlushAsync();
                await Task.Delay(delayMs);
            }
            catch (OperationCanceledException)
            {
                return; // Client disconnected
            }
        }
    }
}
