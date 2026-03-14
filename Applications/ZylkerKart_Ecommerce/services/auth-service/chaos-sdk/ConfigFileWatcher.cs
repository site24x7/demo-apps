// Site24x7 Labs Chaos SDK for .NET — Config File Watcher
//
// Polls the fault config JSON file every 2 seconds, re-parses on mtime change,
// and notifies the engine via a callback.

using System.Text.Json;

namespace Site24x7.Chaos;

/// <summary>
/// Polls a JSON fault-config file on disk. When the file's mtime changes,
/// it is re-parsed and the registered callback is invoked with the new config.
/// Runs as a background task using <see cref="PeriodicTimer"/>.
/// </summary>
public sealed class ConfigFileWatcher : IDisposable
{
    private readonly string _configPath;
    private readonly TimeSpan _pollInterval;
    private readonly Action<AppFaultConfig> _listener;

    private DateTime _lastMtime = DateTime.MinValue;
    private CancellationTokenSource? _cts;
    private Task? _pollTask;

    /// <summary>
    /// Creates a watcher for the given config file.
    /// </summary>
    /// <param name="configDir">Directory where the agent writes config files.</param>
    /// <param name="appName">Application name (used to derive the file name).</param>
    /// <param name="pollInterval">How often to check for changes.</param>
    /// <param name="listener">Callback invoked when the config changes.</param>
    public ConfigFileWatcher(
        string configDir,
        string appName,
        TimeSpan pollInterval,
        Action<AppFaultConfig> listener)
    {
        _configPath = Path.Combine(configDir, $"{appName}.json");
        _pollInterval = pollInterval;
        _listener = listener;
    }

    /// <summary>Path to the config file being watched.</summary>
    public string ConfigPath => _configPath;

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    /// <summary>
    /// Start polling in a background task.
    /// </summary>
    public void Start()
    {
        if (_cts is not null) return;

        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        // Check immediately
        CheckForChanges();

        _pollTask = Task.Run(async () =>
        {
            using var timer = new PeriodicTimer(_pollInterval);
            try
            {
                while (await timer.WaitForNextTickAsync(token))
                {
                    CheckForChanges();
                }
            }
            catch (OperationCanceledException)
            {
                // Expected on shutdown
            }
        }, token);

        Console.WriteLine($"[chaos-sdk] ConfigFileWatcher started, watching: {_configPath}");
    }

    /// <summary>
    /// Stop the watcher and wait for the background task to finish.
    /// </summary>
    public void Stop()
    {
        if (_cts is null) return;

        _cts.Cancel();

        try { _pollTask?.Wait(); }
        catch (AggregateException) { /* cancelled */ }

        _cts.Dispose();
        _cts = null;
        _pollTask = null;

        Console.WriteLine("[chaos-sdk] ConfigFileWatcher stopped");
    }

    // ------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------

    private void CheckForChanges()
    {
        // Check if file exists and has a newer mtime
        FileInfo fileInfo;
        try
        {
            fileInfo = new FileInfo(_configPath);
            if (!fileInfo.Exists)
            {
                // File doesn't exist — either agent hasn't written it yet,
                // or agent deleted it (all rules removed). If we had rules
                // before, clear them by sending an empty config.
                if (_lastMtime > DateTime.MinValue)
                {
                    _lastMtime = DateTime.MinValue;
                    Console.WriteLine("[chaos-sdk] Config file removed, clearing all rules");
                    try
                    {
                        _listener(new AppFaultConfig());
                    }
                    catch (Exception ex)
                    {
                        Console.Error.WriteLine($"[chaos-sdk] Config update listener error on clear: {ex.Message}");
                    }
                }
                return;
            }
        }
        catch
        {
            return;
        }

        var mtime = fileInfo.LastWriteTimeUtc;
        if (mtime <= _lastMtime) return;
        _lastMtime = mtime;

        // Read and parse the config file
        AppFaultConfig? config;
        try
        {
            var content = File.ReadAllText(_configPath);
            config = JsonSerializer.Deserialize<AppFaultConfig>(content);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[chaos-sdk] Failed to parse config file {_configPath}: {ex.Message}");
            return;
        }

        // Validate minimal structure
        if (config?.Rules is null)
        {
            Console.Error.WriteLine($"[chaos-sdk] Invalid config file structure in {_configPath}");
            return;
        }

        Console.WriteLine($"[chaos-sdk] Config file changed, loaded {config.Rules.Count} rules");

        // Notify listener
        try
        {
            _listener(config);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[chaos-sdk] Config update listener error: {ex.Message}");
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
