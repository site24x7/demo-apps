// Site24x7 Labs Chaos SDK for .NET — URL Pattern Matcher
//
// Converts glob patterns (*, **) to regular expressions for URL matching.
// Thread-safe via ConcurrentDictionary cache.

using System.Collections.Concurrent;
using System.Text;
using System.Text.RegularExpressions;

namespace Site24x7.Chaos;

/// <summary>
/// Matches URL paths against glob patterns.
/// Patterns use <c>*</c> for single segment and <c>**</c> for any depth.
/// </summary>
public sealed class UrlMatcher
{
    private readonly ConcurrentDictionary<string, Regex> _cache = new();

    /// <summary>
    /// Returns true if the URL path matches the glob pattern.
    /// An empty pattern matches everything.
    /// </summary>
    public bool Matches(string pattern, string urlPath)
    {
        if (string.IsNullOrEmpty(pattern))
            return true;

        var regex = _cache.GetOrAdd(pattern, CompileGlob);

        // Strip query string and fragment
        var path = urlPath;
        var qIdx = path.IndexOf('?');
        if (qIdx >= 0) path = path[..qIdx];
        var hIdx = path.IndexOf('#');
        if (hIdx >= 0) path = path[..hIdx];

        return regex.IsMatch(path);
    }

    private static Regex CompileGlob(string pattern)
    {
        var sb = new StringBuilder("^");
        var i = 0;

        while (i < pattern.Length)
        {
            if (i + 1 < pattern.Length && pattern[i] == '*' && pattern[i + 1] == '*')
            {
                sb.Append(".*");
                i += 2;
                // Skip trailing slash after **
                if (i < pattern.Length && pattern[i] == '/')
                    i++;
            }
            else if (pattern[i] == '*')
            {
                sb.Append("[^/]*");
                i++;
            }
            else
            {
                sb.Append(Regex.Escape(pattern[i].ToString()));
                i++;
            }
        }

        sb.Append('$');
        return new Regex(sb.ToString(), RegexOptions.Compiled | RegexOptions.Singleline);
    }
}
