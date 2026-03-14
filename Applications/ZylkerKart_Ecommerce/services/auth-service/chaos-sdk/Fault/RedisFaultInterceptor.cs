// Site24x7 Labs Chaos SDK for .NET — Redis Fault Interceptor
//
// Intercepts StackExchange.Redis commands to inject 2 fault types:
//   1. redis_exception  — Throw a mapped error before the command runs.
//   2. redis_latency    — Delay before the command runs.
//
// Usage:
//   var mux = ConnectionMultiplexer.Connect("localhost:6379");
//   var db = mux.GetDatabase();
//   var chaosDb = new ChaosRedisDatabase(db, engine);

namespace Site24x7.Chaos.Fault;

/// <summary>
/// Wraps a StackExchange.Redis <c>IDatabase</c> to inject Redis faults.
/// This is a lightweight proxy that checks fault rules before delegating
/// to the real Redis connection.
/// </summary>
/// <remarks>
/// StackExchange.Redis doesn't have a Hook/interceptor pattern like go-redis.
/// The recommended approach is to wrap the IDatabase at the application level.
/// For DI scenarios, register this wrapper instead of the raw database.
/// </remarks>
public sealed class RedisFaultInterceptor
{
    private const string FaultPrefix = "redis_";
    private readonly ChaosEngine _engine;

    public RedisFaultInterceptor(ChaosEngine engine)
    {
        _engine = engine;
    }

    /// <summary>
    /// Evaluate Redis fault rules before a command. Call this before
    /// every Redis operation. Throws if an exception fault fires;
    /// delays synchronously if a latency fault fires.
    /// </summary>
    public void EvaluateBeforeCommand()
    {
        if (!_engine.Enabled) return;

        var rules = _engine.FindMatchingRules(FaultPrefix);
        foreach (var rule in rules)
        {
            if (!_engine.ShouldFire(rule)) continue;

            switch (rule.FaultType)
            {
                case FaultTypes.RedisException:
                {
                    var javaClass = ConfigHelpers.GetString(rule, "exception_class", "RedisConnectionFailureException");
                    var message = ConfigHelpers.GetString(rule, "message", "Injected Redis fault");
                    Console.WriteLine($"[chaos-sdk] Injecting Redis exception: {javaClass} - {message}");
                    throw ExceptionMap.Resolve(javaClass, message);
                }

                case FaultTypes.RedisLatency:
                {
                    var delayMs = ConfigHelpers.GetInt(rule, "delay_ms", 3000);
                    Console.WriteLine($"[chaos-sdk] Injecting Redis latency: {delayMs}ms");
                    Thread.Sleep(delayMs);
                    return; // Continue after delay
                }
            }
        }
    }

    /// <summary>
    /// Async version of <see cref="EvaluateBeforeCommand"/>.
    /// </summary>
    public async Task EvaluateBeforeCommandAsync(CancellationToken ct = default)
    {
        if (!_engine.Enabled) return;

        var rules = _engine.FindMatchingRules(FaultPrefix);
        foreach (var rule in rules)
        {
            if (!_engine.ShouldFire(rule)) continue;

            switch (rule.FaultType)
            {
                case FaultTypes.RedisException:
                {
                    var javaClass = ConfigHelpers.GetString(rule, "exception_class", "RedisConnectionFailureException");
                    var message = ConfigHelpers.GetString(rule, "message", "Injected Redis fault");
                    Console.WriteLine($"[chaos-sdk] Injecting Redis exception: {javaClass} - {message}");
                    throw ExceptionMap.Resolve(javaClass, message);
                }

                case FaultTypes.RedisLatency:
                {
                    var delayMs = ConfigHelpers.GetInt(rule, "delay_ms", 3000);
                    Console.WriteLine($"[chaos-sdk] Injecting Redis latency: {delayMs}ms");
                    await Task.Delay(delayMs, ct);
                    return;
                }
            }
        }
    }
}
