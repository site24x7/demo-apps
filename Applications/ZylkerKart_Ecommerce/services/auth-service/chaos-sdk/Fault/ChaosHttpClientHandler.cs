// Site24x7 Labs Chaos SDK for .NET — Outbound HTTP Client Fault Handler
//
// DelegatingHandler that intercepts outbound HttpClient calls and injects
// 4 fault types:
//   1. http_client_latency            — Delay before the outbound call proceeds.
//   2. http_client_exception          — Throw an exception instead of making the call.
//   3. http_client_error_response     — Return a fake error response.
//   4. http_client_partial_response   — Return a truncated response body.
//
// Usage:
//   builder.Services.AddHttpClient("api").AddChaosHandler();

using System.Net;
using System.Text;

namespace Site24x7.Chaos.Fault;

/// <summary>
/// <see cref="DelegatingHandler"/> that injects outbound HTTP client faults.
/// Registered via <c>AddChaosHandler()</c> on an <see cref="IHttpClientBuilder"/>.
/// </summary>
public sealed class ChaosHttpClientHandler : DelegatingHandler
{
    private const string FaultPrefix = "http_client_";
    private readonly ChaosEngine _engine;

    public ChaosHttpClientHandler(ChaosEngine engine)
    {
        _engine = engine;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        if (!_engine.Enabled)
            return await base.SendAsync(request, cancellationToken);

        var url = request.RequestUri?.PathAndQuery ?? "/";
        var rules = _engine.FindMatchingRules(FaultPrefix, url);

        foreach (var rule in rules)
        {
            if (!_engine.ShouldFire(rule)) continue;

            switch (rule.FaultType)
            {
                case FaultTypes.HttpClientLatency:
                {
                    var delayMs = ConfigHelpers.GetInt(rule, "delay_ms", 3000);
                    Console.WriteLine($"[chaos-sdk] Injecting HTTP client latency: {delayMs}ms on {url}");
                    await Task.Delay(delayMs, cancellationToken);
                    // Fall through to the real request after delay
                    return await base.SendAsync(request, cancellationToken);
                }

                case FaultTypes.HttpClientException:
                {
                    var javaClass = ConfigHelpers.GetString(rule, "exception_class", "ResourceAccessException");
                    var message = ConfigHelpers.GetString(rule, "message", "Injected outbound fault");
                    Console.WriteLine($"[chaos-sdk] Injecting HTTP client exception: {javaClass} - {message} on {url}");
                    throw ExceptionMap.Resolve(javaClass, message);
                }

                case FaultTypes.HttpClientErrorResponse:
                {
                    var statusCode = ConfigHelpers.GetInt(rule, "status_code", 503);
                    var body = ConfigHelpers.GetString(rule, "body", "Service Unavailable");
                    Console.WriteLine($"[chaos-sdk] Injecting HTTP client error response: {statusCode} on {url}");
                    return new HttpResponseMessage((HttpStatusCode)statusCode)
                    {
                        Content = new StringContent(body, Encoding.UTF8, "text/plain"),
                        RequestMessage = request,
                    };
                }

                case FaultTypes.HttpClientPartialResponse:
                {
                    var statusCode = ConfigHelpers.GetInt(rule, "status_code", 200);
                    var body = ConfigHelpers.GetString(rule, "body", "{\"data\":[{\"id\":1,\"name\":\"item\"");
                    var truncatePct = ConfigHelpers.Clamp(
                        ConfigHelpers.GetInt(rule, "truncate_percentage", 50), 10, 90);

                    var truncLen = Math.Max(1, body.Length * truncatePct / 100);
                    var truncatedBody = body[..truncLen];

                    Console.WriteLine($"[chaos-sdk] Injecting HTTP client partial response: {truncatePct}% of body on {url}");
                    return new HttpResponseMessage((HttpStatusCode)statusCode)
                    {
                        Content = new StringContent(truncatedBody, Encoding.UTF8, "application/json"),
                        RequestMessage = request,
                    };
                }

                default:
                    Console.Error.WriteLine($"[chaos-sdk] Unknown HTTP client fault type: {rule.FaultType}");
                    break;
            }
        }

        return await base.SendAsync(request, cancellationToken);
    }
}
