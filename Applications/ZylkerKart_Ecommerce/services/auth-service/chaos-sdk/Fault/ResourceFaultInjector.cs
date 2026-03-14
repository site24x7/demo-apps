// Site24x7 Labs Chaos SDK for .NET — Resource Fault Injector
//
// Unlike HTTP/DB/Redis faults (triggered per-request), resource faults are
// triggered when the config changes. The injector registers as a
// config-update listener on the ChaosEngine.
//
// 6 fault types:
//  1. thread_pool_exhaustion — Task.Run flooding the ThreadPool.
//  2. memory_pressure        — Allocate byte[] arrays and hold them.
//  3. cpu_burn               — Thread + SpinWait tight loops.
//  4. gc_pressure            — Rapid short-lived byte[] allocations.
//  5. thread_deadlock        — ManualResetEventSlim.Wait() blocking.
//  6. disk_fill              — File.WriteAllBytes temp files.

namespace Site24x7.Chaos.Fault;

/// <summary>
/// Listens for config changes on the <see cref="ChaosEngine"/> and injects
/// resource exhaustion faults. Only one resource fault is active at a time.
/// </summary>
public sealed class ResourceFaultInjector
{
    private readonly ChaosEngine _engine;
    private volatile bool _active;

    public ResourceFaultInjector(ChaosEngine engine)
    {
        _engine = engine;
    }

    /// <summary>
    /// Register this injector as a config-update listener on the engine.
    /// Call once after the engine is started.
    /// </summary>
    public void Install()
    {
        _engine.AddConfigUpdateListener(EvaluateAndApply);
        Console.WriteLine("[chaos-sdk] ResourceFaultInjector installed");
    }

    /// <summary>
    /// Find the first matching resource fault rule and apply it.
    /// </summary>
    public void EvaluateAndApply()
    {
        if (!_engine.Enabled) return;
        if (_active)
        {
            Console.WriteLine("[chaos-sdk] Resource fault already active, skipping");
            return;
        }

        var rules = _engine.FindMatchingRules("");
        foreach (var rule in rules)
        {
            if (!FaultTypes.ResourceFaultTypes.Contains(rule.FaultType))
                continue;
            if (!_engine.ShouldFire(rule))
                continue;

            switch (rule.FaultType)
            {
                case FaultTypes.ThreadPoolExhaustion:
                    ApplyThreadPoolExhaustion(rule);
                    break;
                case FaultTypes.MemoryPressure:
                    ApplyMemoryPressure(rule);
                    break;
                case FaultTypes.CpuBurn:
                    ApplyCpuBurn(rule);
                    break;
                case FaultTypes.GcPressure:
                    ApplyGcPressure(rule);
                    break;
                case FaultTypes.ThreadDeadlock:
                    ApplyThreadDeadlock(rule);
                    break;
                case FaultTypes.DiskFill:
                    ApplyDiskFill(rule);
                    break;
                default:
                    Console.Error.WriteLine($"[chaos-sdk] Unknown resource fault type: {rule.FaultType}");
                    break;
            }
            return; // Only inject one at a time
        }
    }

    // -----------------------------------------------------------------------
    // 1. Thread pool exhaustion — flood the ThreadPool with blocked tasks
    // -----------------------------------------------------------------------

    private void ApplyThreadPoolExhaustion(FaultRuleConfig rule)
    {
        var threadCount = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "thread_count", 10), 1, 50);
        var durationMs = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "duration_ms", 30000), 1000, 60000);

        Console.WriteLine($"[chaos-sdk] Injecting thread pool exhaustion: {threadCount} tasks for {durationMs}ms");
        _active = true;

        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(durationMs));
        var token = cts.Token;

        for (var i = 0; i < threadCount; i++)
        {
            Task.Run(() =>
            {
                try
                {
                    // Block the ThreadPool thread until cancelled
                    token.WaitHandle.WaitOne();
                }
                catch (ObjectDisposedException)
                {
                    // Expected when CTS is disposed
                }
            });
        }

        // Cleanup task
        Task.Run(async () =>
        {
            await Task.Delay(durationMs).ConfigureAwait(false);
            _active = false;
            Console.WriteLine("[chaos-sdk] Thread pool exhaustion fault completed");
        });
    }

    // -----------------------------------------------------------------------
    // 2. Memory pressure — allocate and hold byte[] arrays
    // -----------------------------------------------------------------------

    private void ApplyMemoryPressure(FaultRuleConfig rule)
    {
        var allocationMb = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "allocation_mb", 64), 1, 512);
        var durationMs = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "duration_ms", 30000), 1000, 60000);

        Console.WriteLine($"[chaos-sdk] Injecting memory pressure: {allocationMb}MB for {durationMs}ms");
        _active = true;

        var blocks = new List<byte[]>(allocationMb);
        try
        {
            for (var i = 0; i < allocationMb; i++)
            {
                var block = new byte[1024 * 1024]; // 1 MB
                // Touch pages to ensure real allocation
                for (var j = 0; j < block.Length; j += 4096)
                    block[j] = (byte)(i & 0xFF);
                blocks.Add(block);
            }
            Console.WriteLine($"[chaos-sdk] Memory pressure: allocated {allocationMb}MB");
        }
        catch (OutOfMemoryException)
        {
            Console.Error.WriteLine($"[chaos-sdk] Memory pressure: allocation error, holding partial ({blocks.Count}MB)");
        }

        // Hold for duration, then release
        Task.Run(async () =>
        {
            await Task.Delay(durationMs).ConfigureAwait(false);
            blocks.Clear();
            GC.Collect(); // Hint GC
            _active = false;
            Console.WriteLine("[chaos-sdk] Memory pressure fault completed, memory released");
        });
    }

    // -----------------------------------------------------------------------
    // 3. CPU burn — Thread + SpinWait tight loops
    // -----------------------------------------------------------------------

    private void ApplyCpuBurn(FaultRuleConfig rule)
    {
        var threadCount = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "thread_count", 2), 1, 8);
        var durationMs = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "duration_ms", 30000), 1000, 60000);

        Console.WriteLine($"[chaos-sdk] Injecting CPU burn: {threadCount} threads for {durationMs}ms");
        _active = true;

        var deadline = DateTime.UtcNow.AddMilliseconds(durationMs);
        var completed = 0;

        for (var i = 0; i < threadCount; i++)
        {
            var thread = new Thread(() =>
            {
                var x = 1.1;
                while (DateTime.UtcNow < deadline)
                {
                    // Tight math loop — burns CPU
                    for (var j = 0; j < 10000; j++)
                    {
                        x = Math.Sin(x) * Math.Cos(x) + Math.Sqrt(Math.Abs(x));
                    }
                }
                _ = x; // prevent optimisation

                if (Interlocked.Increment(ref completed) == threadCount)
                {
                    _active = false;
                    Console.WriteLine($"[chaos-sdk] CPU burn fault completed ({threadCount} threads)");
                }
            })
            {
                IsBackground = true,
                Name = $"chaos-cpu-burn-{i}",
            };
            thread.Start();
        }
    }

    // -----------------------------------------------------------------------
    // 4. GC pressure — rapid short-lived allocations
    // -----------------------------------------------------------------------

    private void ApplyGcPressure(FaultRuleConfig rule)
    {
        var allocRateMbPerSec = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "allocation_rate_mb_per_sec", 10), 1, 100);
        var durationMs = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "duration_ms", 30000), 1000, 60000);

        Console.WriteLine($"[chaos-sdk] Injecting GC pressure: {allocRateMbPerSec}MB/sec for {durationMs}ms");
        _active = true;

        Task.Run(async () =>
        {
            var deadline = DateTime.UtcNow.AddMilliseconds(durationMs);
            var intervalMs = Math.Max(1, 1000 / allocRateMbPerSec);

            while (DateTime.UtcNow < deadline)
            {
                // Allocate 1 MB — immediately discard so GC must collect
                var garbage = new byte[1024 * 1024];
                garbage[0] = 1;
                garbage[^1] = 1;
                _ = garbage; // goes out of scope, eligible for GC

                await Task.Delay(intervalMs).ConfigureAwait(false);
            }

            _active = false;
            Console.WriteLine("[chaos-sdk] GC pressure fault completed");
        });
    }

    // -----------------------------------------------------------------------
    // 5. Thread deadlock — ManualResetEventSlim blocking
    // -----------------------------------------------------------------------

    private void ApplyThreadDeadlock(FaultRuleConfig rule)
    {
        var durationMs = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "duration_ms", 30000), 1000, 60000);

        Console.WriteLine($"[chaos-sdk] Injecting simulated deadlock for {durationMs}ms");
        _active = true;

        const int deadlockedCount = 4;
        var events = new ManualResetEventSlim[deadlockedCount];

        for (var i = 0; i < deadlockedCount; i++)
        {
            var evt = new ManualResetEventSlim(false);
            events[i] = evt;

            var thread = new Thread(() =>
            {
                // Block until the event is set — simulates deadlock
                evt.Wait();
            })
            {
                IsBackground = true,
                Name = $"chaos-deadlock-{i}",
            };
            thread.Start();
        }

        // Release after duration
        Task.Run(async () =>
        {
            await Task.Delay(durationMs).ConfigureAwait(false);
            foreach (var evt in events)
            {
                evt.Set();
                evt.Dispose();
            }
            _active = false;
            Console.WriteLine("[chaos-sdk] Simulated deadlock fault completed");
        });
    }

    // -----------------------------------------------------------------------
    // 6. Disk fill — write temp files
    // -----------------------------------------------------------------------

    private void ApplyDiskFill(FaultRuleConfig rule)
    {
        var allocationMb = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "allocation_mb", 64), 1, 512);
        var durationMs = ConfigHelpers.Clamp(ConfigHelpers.GetInt(rule, "duration_ms", 30000), 1000, 60000);

        Console.WriteLine($"[chaos-sdk] Injecting disk fill: {allocationMb}MB for {durationMs}ms");
        _active = true;

        var tempDir = Path.GetTempPath();
        var tempFiles = new List<string>(allocationMb);
        var block = new byte[1024 * 1024]; // 1 MB
        Array.Fill(block, (byte)0xAA);

        try
        {
            for (var i = 0; i < allocationMb; i++)
            {
                var filePath = Path.Combine(tempDir, $"chaos-disk-fill-{i}.tmp");
                File.WriteAllBytes(filePath, block);
                tempFiles.Add(filePath);
            }
            Console.WriteLine($"[chaos-sdk] Disk fill: wrote {allocationMb}MB of temp files");
        }
        catch (IOException ex)
        {
            Console.Error.WriteLine($"[chaos-sdk] Disk fill: error during writing: {ex.Message}");
        }

        // Hold for duration, then clean up
        Task.Run(async () =>
        {
            await Task.Delay(durationMs).ConfigureAwait(false);
            foreach (var fp in tempFiles)
            {
                try { File.Delete(fp); }
                catch { /* ignore */ }
            }
            _active = false;
            Console.WriteLine($"[chaos-sdk] Disk fill fault completed, {tempFiles.Count} temp files cleaned up");
        });
    }
}
