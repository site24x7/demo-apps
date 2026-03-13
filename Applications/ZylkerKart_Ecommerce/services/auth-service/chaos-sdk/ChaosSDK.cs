// Site24x7 Labs Chaos SDK for .NET — SDK Entry Point
//
// ChaosSDK is the central coordinator. In typical ASP.NET Core usage it is
// created automatically by the DI extension (AddSite24x7Chaos / UseSite24x7Chaos),
// but can also be used standalone.

namespace Site24x7.Chaos;

/// <summary>
/// Central coordinator for the Chaos SDK. Owns the engine, config watcher,
/// and heartbeat writer. Created via DI or directly.
/// </summary>
public sealed class ChaosSDK : IDisposable
{
    /// <summary>The chaos engine for fault rule evaluation.</summary>
    public ChaosEngine Engine { get; }

    /// <summary>Resolved options snapshot.</summary>
    public ChaosOptions Options { get; }

    private ConfigFileWatcher? _watcher;
    private HeartbeatWriter? _heartbeat;
    private bool _disposed;

    /// <summary>
    /// Creates and starts the Chaos SDK.
    /// </summary>
    public ChaosSDK(ChaosOptions options)
    {
        Options = options ?? throw new ArgumentNullException(nameof(options));

        if (string.IsNullOrWhiteSpace(options.AppName))
            throw new ArgumentException("ChaosOptions.AppName is required.", nameof(options));

        Engine = new ChaosEngine { Enabled = options.Enabled };

        // Config file watcher
        _watcher = new ConfigFileWatcher(
            options.ConfigDir,
            options.AppName,
            TimeSpan.FromSeconds(2),
            config => Engine.UpdateRules(config.Rules));
        _watcher.Start();

        // Heartbeat writer
        _heartbeat = new HeartbeatWriter(
            options.ConfigDir,
            options.AppName,
            options.Framework,
            options.FrameworkVersion);
        _heartbeat.Start();

        Console.WriteLine($"[chaos-sdk] Chaos SDK initialized for {options.Framework} app \"{options.AppName}\"");
    }

    /// <summary>
    /// Stops the config watcher and heartbeat writer, releasing all resources.
    /// Safe to call multiple times.
    /// </summary>
    public void Shutdown()
    {
        if (_disposed) return;
        _disposed = true;

        _watcher?.Stop();
        _watcher?.Dispose();
        _watcher = null;

        _heartbeat?.Stop();
        _heartbeat?.Dispose();
        _heartbeat = null;

        Console.WriteLine("[chaos-sdk] Chaos SDK shut down");
    }

    /// <inheritdoc />
    public void Dispose()
    {
        Shutdown();
    }
}
