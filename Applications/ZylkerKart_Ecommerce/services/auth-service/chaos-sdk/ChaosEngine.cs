// Site24x7 Labs Chaos SDK for .NET — Chaos Engine
//
// Central orchestrator: manages fault rules, URL matching, probability evaluation.
// Thread-safe via ReaderWriterLockSlim.

namespace Site24x7.Chaos;

/// <summary>
/// Central chaos engine that manages fault rules, URL pattern matching,
/// and probability-based firing decisions. Thread-safe for concurrent access.
/// </summary>
public sealed class ChaosEngine
{
    private readonly ReaderWriterLockSlim _lock = new();
    private readonly UrlMatcher _matcher = new();
    private readonly List<Action> _configListeners = new();
    private List<FaultRuleConfig> _rules = new();
    private bool _enabled = true;

    /// <summary>Gets or sets whether fault injection is active.</summary>
    public bool Enabled
    {
        get { _lock.EnterReadLock(); try { return _enabled; } finally { _lock.ExitReadLock(); } }
        set { _lock.EnterWriteLock(); try { _enabled = value; } finally { _lock.ExitWriteLock(); } }
    }

    /// <summary>
    /// Replace the current set of fault rules (called by ConfigFileWatcher).
    /// Notifies all registered config update listeners.
    /// </summary>
    public void UpdateRules(List<FaultRuleConfig> rules)
    {
        List<Action> listeners;

        _lock.EnterWriteLock();
        try
        {
            _rules = rules;
            listeners = new List<Action>(_configListeners);
        }
        finally
        {
            _lock.ExitWriteLock();
        }

        // Notify outside lock
        foreach (var listener in listeners)
        {
            try { listener(); }
            catch (Exception ex) { Console.Error.WriteLine($"[chaos-sdk] Config listener error: {ex.Message}"); }
        }
    }

    /// <summary>
    /// Register a callback invoked when rules change.
    /// Used by ResourceFaultInjector to trigger on config updates.
    /// </summary>
    public void AddConfigUpdateListener(Action listener)
    {
        _lock.EnterWriteLock();
        try { _configListeners.Add(listener); }
        finally { _lock.ExitWriteLock(); }
    }

    /// <summary>
    /// Find all enabled rules whose fault_type starts with <paramref name="prefix"/>
    /// and whose url_pattern matches the URL. Empty prefix matches all types.
    /// </summary>
    public List<FaultRuleConfig> FindMatchingRules(string prefix, string? url = null)
    {
        _lock.EnterReadLock();
        try
        {
            if (!_enabled)
                return new List<FaultRuleConfig>();

            var matched = new List<FaultRuleConfig>();
            foreach (var rule in _rules)
            {
                if (!rule.Enabled) continue;
                if (!string.IsNullOrEmpty(prefix) && !rule.FaultType.StartsWith(prefix, StringComparison.Ordinal))
                    continue;
                if (!string.IsNullOrEmpty(url) && !string.IsNullOrEmpty(rule.UrlPattern))
                {
                    if (!_matcher.Matches(rule.UrlPattern, url))
                        continue;
                }
                matched.Add(rule);
            }
            return matched;
        }
        finally
        {
            _lock.ExitReadLock();
        }
    }

    /// <summary>
    /// Evaluate whether a rule should fire based on its probability (0.0–1.0).
    /// </summary>
    public bool ShouldFire(FaultRuleConfig rule)
    {
        if (rule.Probability <= 0) return false;
        if (rule.Probability >= 1.0) return true;
        return Random.Shared.NextDouble() < rule.Probability;
    }

    /// <summary>
    /// Returns a snapshot of the current rules (for diagnostics).
    /// </summary>
    public List<FaultRuleConfig> GetRules()
    {
        _lock.EnterReadLock();
        try { return new List<FaultRuleConfig>(_rules); }
        finally { _lock.ExitReadLock(); }
    }
}
