package internal

import (
	"regexp"
	"strings"
	"sync"
)

// URLMatcher compiles glob patterns into regexps and caches them.
// Thread-safe via sync.RWMutex.
//
// Glob rules:
//   - "*"  matches a single path segment (anything except '/')
//   - "**" matches any number of path segments (including zero)
//   - All other characters are literal-escaped
type URLMatcher struct {
	mu    sync.RWMutex
	cache map[string]*regexp.Regexp
}

// NewURLMatcher creates a new URL matcher with an empty cache.
func NewURLMatcher() *URLMatcher {
	return &URLMatcher{cache: make(map[string]*regexp.Regexp)}
}

// Matches returns true if the given URL path matches the glob pattern.
// An empty pattern matches everything.
func (m *URLMatcher) Matches(pattern, urlPath string) bool {
	if pattern == "" {
		return true
	}

	re := m.getOrCompile(pattern)
	if re == nil {
		return false
	}

	// Strip query string and fragment for matching
	path := urlPath
	if idx := strings.IndexByte(path, '?'); idx >= 0 {
		path = path[:idx]
	}
	if idx := strings.IndexByte(path, '#'); idx >= 0 {
		path = path[:idx]
	}

	return re.MatchString(path)
}

func (m *URLMatcher) getOrCompile(pattern string) *regexp.Regexp {
	m.mu.RLock()
	re, ok := m.cache[pattern]
	m.mu.RUnlock()
	if ok {
		return re
	}

	compiled := compileGlob(pattern)

	m.mu.Lock()
	m.cache[pattern] = compiled
	m.mu.Unlock()

	return compiled
}

// compileGlob converts a URL glob pattern to a regexp.
// It handles ** (any path), * (single segment), and literal escaping.
func compileGlob(pattern string) *regexp.Regexp {
	var b strings.Builder
	b.WriteString("^")

	i := 0
	for i < len(pattern) {
		if i+1 < len(pattern) && pattern[i] == '*' && pattern[i+1] == '*' {
			b.WriteString(".*")
			i += 2
			// Skip trailing slash after **
			if i < len(pattern) && pattern[i] == '/' {
				i++
			}
		} else if pattern[i] == '*' {
			b.WriteString("[^/]*")
			i++
		} else {
			// Escape regex metacharacters
			ch := pattern[i]
			if isRegexMeta(ch) {
				b.WriteByte('\\')
			}
			b.WriteByte(ch)
			i++
		}
	}

	b.WriteString("$")

	re, err := regexp.Compile(b.String())
	if err != nil {
		return nil
	}
	return re
}

func isRegexMeta(ch byte) bool {
	switch ch {
	case '.', '+', '?', '(', ')', '[', ']', '{', '}', '|', '^', '$', '\\':
		return true
	}
	return false
}
