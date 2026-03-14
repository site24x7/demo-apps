// Site24x7 Labs Chaos SDK for .NET — Config Helpers
//
// Extract typed values from the fault rule config dictionary.

using System.Text.Json;

namespace Site24x7.Chaos;

/// <summary>
/// Helper methods for extracting typed values from <see cref="FaultRuleConfig.Config"/>.
/// </summary>
public static class ConfigHelpers
{
    /// <summary>
    /// Extract a string value from the config, returning <paramref name="defaultValue"/> if missing.
    /// </summary>
    public static string GetString(FaultRuleConfig rule, string key, string defaultValue = "")
    {
        if (rule.Config.TryGetValue(key, out var val) && val is not null)
        {
            if (val is string s)
                return s;
            if (val is JsonElement je && je.ValueKind == JsonValueKind.String)
                return je.GetString() ?? defaultValue;
            return val.ToString() ?? defaultValue;
        }
        return defaultValue;
    }

    /// <summary>
    /// Extract an integer value from the config, returning <paramref name="defaultValue"/> if missing.
    /// Handles JsonElement (from System.Text.Json deserialization) and numeric types.
    /// </summary>
    public static int GetInt(FaultRuleConfig rule, string key, int defaultValue = 0)
    {
        if (rule.Config.TryGetValue(key, out var val) && val is not null)
        {
            if (val is JsonElement je)
            {
                if (je.ValueKind == JsonValueKind.Number && je.TryGetInt32(out var i))
                    return i;
                if (je.ValueKind == JsonValueKind.Number && je.TryGetDouble(out var d))
                    return (int)d;
            }
            if (val is int intVal) return intVal;
            if (val is long longVal) return (int)longVal;
            if (val is double dblVal) return (int)dblVal;
            if (val is float fltVal) return (int)fltVal;
        }
        return defaultValue;
    }

    /// <summary>
    /// Extract a double value from the config, returning <paramref name="defaultValue"/> if missing.
    /// </summary>
    public static double GetDouble(FaultRuleConfig rule, string key, double defaultValue = 0.0)
    {
        if (rule.Config.TryGetValue(key, out var val) && val is not null)
        {
            if (val is JsonElement je && je.ValueKind == JsonValueKind.Number && je.TryGetDouble(out var d))
                return d;
            if (val is double dblVal) return dblVal;
            if (val is int intVal) return intVal;
            if (val is float fltVal) return fltVal;
        }
        return defaultValue;
    }

    /// <summary>
    /// Clamp an integer to the range [min, max].
    /// </summary>
    public static int Clamp(int value, int min, int max) =>
        Math.Max(min, Math.Min(max, value));
}
