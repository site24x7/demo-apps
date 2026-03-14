// Site24x7 Labs Chaos SDK for .NET — Models
//
// Defines fault types, config file schema, and rule configuration.

using System.Text.Json.Serialization;

namespace Site24x7.Chaos;

// ---------------------------------------------------------------------------
// Fault types (all 20)
// ---------------------------------------------------------------------------

/// <summary>
/// All supported chaos fault type identifiers.
/// </summary>
public static class FaultTypes
{
    // Inbound HTTP (5)
    public const string HttpException = "http_exception";
    public const string HttpLatency = "http_latency";
    public const string HttpErrorResponse = "http_error_response";
    public const string HttpConnectionReset = "http_connection_reset";
    public const string HttpSlowBody = "http_slow_body";

    // Outbound HTTP client (4)
    public const string HttpClientLatency = "http_client_latency";
    public const string HttpClientException = "http_client_exception";
    public const string HttpClientErrorResponse = "http_client_error_response";
    public const string HttpClientPartialResponse = "http_client_partial_response";

    // Database / JDBC (3)
    public const string JdbcException = "jdbc_exception";
    public const string JdbcLatency = "jdbc_latency";
    public const string JdbcConnectionPoolDrain = "jdbc_connection_pool_drain";

    // Redis (2)
    public const string RedisException = "redis_exception";
    public const string RedisLatency = "redis_latency";

    // Resource exhaustion (6)
    public const string ThreadPoolExhaustion = "thread_pool_exhaustion";
    public const string MemoryPressure = "memory_pressure";
    public const string CpuBurn = "cpu_burn";
    public const string GcPressure = "gc_pressure";
    public const string ThreadDeadlock = "thread_deadlock";
    public const string DiskFill = "disk_fill";

    /// <summary>
    /// Resource fault types are triggered on config change, not per-request.
    /// </summary>
    public static readonly HashSet<string> ResourceFaultTypes = new()
    {
        ThreadPoolExhaustion, MemoryPressure, CpuBurn,
        GcPressure, ThreadDeadlock, DiskFill,
    };
}

// ---------------------------------------------------------------------------
// Config file schema (written by agent, read by SDK)
// ---------------------------------------------------------------------------

/// <summary>
/// A single fault rule from the config file.
/// </summary>
public sealed class FaultRuleConfig
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("fault_type")]
    public string FaultType { get; set; } = string.Empty;

    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; }

    [JsonPropertyName("probability")]
    public double Probability { get; set; }

    [JsonPropertyName("config")]
    public Dictionary<string, object?> Config { get; set; } = new();

    [JsonPropertyName("url_pattern")]
    public string UrlPattern { get; set; } = string.Empty;
}

/// <summary>
/// Top-level config file written by the agent.
/// </summary>
public sealed class AppFaultConfig
{
    [JsonPropertyName("version")]
    public int Version { get; set; }

    [JsonPropertyName("app_name")]
    public string AppName { get; set; } = string.Empty;

    [JsonPropertyName("environment_id")]
    public string EnvironmentId { get; set; } = string.Empty;

    [JsonPropertyName("updated_at")]
    public string UpdatedAt { get; set; } = string.Empty;

    [JsonPropertyName("rules")]
    public List<FaultRuleConfig> Rules { get; set; } = new();
}

// ---------------------------------------------------------------------------
// SDK options
// ---------------------------------------------------------------------------

/// <summary>
/// Configuration options for the Chaos SDK.
/// </summary>
public sealed class ChaosOptions
{
    /// <summary>
    /// Application name — must match the service name in Site24x7 Labs.
    /// </summary>
    public string AppName { get; set; } = string.Empty;

    /// <summary>
    /// Directory where the agent writes fault config files.
    /// Default: /var/site24x7-labs/faults
    /// </summary>
    public string ConfigDir { get; set; } = ChaosConstants.DefaultConfigDir;

    /// <summary>
    /// Framework name reported in the heartbeat (e.g., "aspnetcore").
    /// </summary>
    public string Framework { get; set; } = "aspnetcore";

    /// <summary>
    /// Framework version reported in the heartbeat.
    /// </summary>
    public string FrameworkVersion { get; set; } = string.Empty;

    /// <summary>
    /// Whether fault injection is enabled. Default: true.
    /// </summary>
    public bool Enabled { get; set; } = true;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

public static class ChaosConstants
{
    public const string DefaultConfigDir = "/var/site24x7-labs/faults";
    public const string SdkVersion = "1.0.0";
    public const string SdkLanguage = "dotnet";
}
