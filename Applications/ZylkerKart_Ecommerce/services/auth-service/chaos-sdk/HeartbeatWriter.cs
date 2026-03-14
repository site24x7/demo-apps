// Site24x7 Labs Chaos SDK for .NET — Heartbeat Writer
//
// Writes {app_name}.heartbeat.json every 30 seconds so the agent can
// discover that this SDK is installed and running.
// Uses atomic write (tmp + File.Move overwrite) to prevent partial reads.

using System.Text.Json;

namespace Site24x7.Chaos;

/// <summary>
/// Periodically writes a heartbeat JSON file so the agent can detect
/// that this SDK is installed and active. Runs as a background task
/// using <see cref="PeriodicTimer"/>.
/// </summary>
public sealed class HeartbeatWriter : IDisposable
{
    private static readonly TimeSpan HeartbeatInterval = TimeSpan.FromSeconds(30);

    private readonly string _heartbeatPath;
    private readonly string _tmpPath;
    private readonly string _appName;
    private readonly string _framework;
    private readonly string _frameworkVersion;

    private CancellationTokenSource? _cts;
    private Task? _writeTask;

    /// <summary>
    /// Creates a heartbeat writer.
    /// </summary>
    /// <param name="configDir">Directory where heartbeat files are written.</param>
    /// <param name="appName">Application name.</param>
    /// <param name="framework">Framework name (e.g., "aspnetcore").</param>
    /// <param name="frameworkVersion">Framework version string.</param>
    public HeartbeatWriter(
        string configDir,
        string appName,
        string framework,
        string frameworkVersion)
    {
        _heartbeatPath = Path.Combine(configDir, $"{appName}.heartbeat.json");
        _tmpPath = Path.Combine(configDir, $"{appName}.heartbeat.tmp");
        _appName = appName;
        _framework = framework;
        _frameworkVersion = frameworkVersion;
    }

    /// <summary>Path to the heartbeat file.</summary>
    public string HeartbeatPath => _heartbeatPath;

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    /// <summary>
    /// Start writing heartbeats in a background task.
    /// </summary>
    public void Start()
    {
        if (_cts is not null) return;

        // Ensure directory exists
        try
        {
            var dir = Path.GetDirectoryName(_heartbeatPath);
            if (dir is not null)
                Directory.CreateDirectory(dir);
        }
        catch
        {
            // Directory may not be writable — we'll log on first write failure
        }

        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        // Write immediately
        WriteHeartbeat();

        _writeTask = Task.Run(async () =>
        {
            using var timer = new PeriodicTimer(HeartbeatInterval);
            try
            {
                while (await timer.WaitForNextTickAsync(token))
                {
                    WriteHeartbeat();
                }
            }
            catch (OperationCanceledException)
            {
                // Expected on shutdown
            }
        }, token);

        Console.WriteLine($"[chaos-sdk] HeartbeatWriter started, path: {_heartbeatPath}");
    }

    /// <summary>
    /// Stop the heartbeat writer, wait for the background task, and remove the heartbeat file.
    /// </summary>
    public void Stop()
    {
        if (_cts is null) return;

        _cts.Cancel();

        try { _writeTask?.Wait(); }
        catch (AggregateException) { /* cancelled */ }

        _cts.Dispose();
        _cts = null;
        _writeTask = null;

        // Clean up heartbeat file on shutdown
        try { File.Delete(_heartbeatPath); }
        catch { /* may not exist */ }

        Console.WriteLine("[chaos-sdk] HeartbeatWriter stopped");
    }

    // ------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------

    private void WriteHeartbeat()
    {
        var data = new Dictionary<string, object>
        {
            ["app_name"] = _appName,
            ["sdk_version"] = ChaosConstants.SdkVersion,
            ["sdk_language"] = ChaosConstants.SdkLanguage,
            ["framework"] = _framework,
            ["framework_version"] = _frameworkVersion,
            ["pid"] = Environment.ProcessId,
            ["hostname"] = Environment.MachineName,
            ["timestamp"] = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
        };

        try
        {
            var json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });

            // Atomic write: write to tmp file, then rename
            File.WriteAllText(_tmpPath, json);
            File.Move(_tmpPath, _heartbeatPath, overwrite: true);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[chaos-sdk] Failed to write heartbeat file: {ex.Message}");
        }
    }

    // ------------------------------------------------------------------
    // IDisposable
    // ------------------------------------------------------------------

    public void Dispose()
    {
        Stop();
    }
}
