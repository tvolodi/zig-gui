# RH1 — M18-01: Pattern validation (regex in schema forms)

> Roadmap item: M18-01  
> Depends on: M8 (module 08 schema forms complete)  
> Read `00_constitution.md` before this file.

## Purpose

Enable JSON Schema `pattern` keyword validation in schema-driven forms. A field with `pattern: "^[A-Z][a-z]+$"` validates the string value against a regex pattern. The validator rejects values that do not match, producing a validation error with a user-friendly message.

## HUMAN DECISION REQUIRED

**INV-5.6 constraint:** Zig std has no regex library, and no external regex crate is yet approved. This requirement is **blocked on a dependency decision**.

### Three options presented to the human

#### Option A: Vendor a pure-Zig regex engine (RECOMMENDED)

**Approach:** Port a minimal regex engine to pure Zig (e.g., RE2-style DFA matcher or backtracking NFA).

**Pros:**
- No external C dependency; fully portable
- Tight control over performance and memory
- Aligns with INV-1.1 (no external frameworks)

**Cons:**
- Significant new Zig code (~1000+ lines for a working subset)
- Maintenance burden (regex is notoriously corner-case-heavy)
- Pattern syntax must be documented and tested thoroughly

**Scope if chosen:** Support basic POSIX ERE subset:
- Character classes: `[abc]`, `[a-z]`, `\d`, `\w`, `\s`, negation `[^abc]`
- Anchors: `^` (start), `$` (end)
- Quantifiers: `*` (0+), `+` (1+), `?` (0-1), `{n}`, `{n,m}`
- Escaping: `\.`, `\\`, `\n`, etc.
- Grouping: `(…)` (capture groups optional in v1)
- Alternation: `a|b`
- No lookahead/lookbehind (post-v1)

**Module location:** `src/08/regex.zig` (new file; pure logic, fully testable)

**Non-goal:** Full PCRE or Unicode property escapes — basic patterns only.

#### Option B: Use a pre-approved Zig regex library (if one exists)

**Status:** As of M18 (2026-06-13), no Zig regex library is approved in INV-5.6. This option requires:
1. Human identifies a candidate library
2. Approval is recorded in `00_constitution.md` INV-5.6
3. Build configuration is updated to fetch and link it
4. `src/08/regex.zig` becomes a thin wrapper calling the library

#### Option C: Defer pattern validation to post-v1

**Approach:** Mark `pattern` as deferred. Schema forms handle the keyword gracefully (no error on parsing, but validation is a no-op with a documented limitation).

**Pros:**
- Zero implementation cost now
- Unblocks the rest of M18

**Cons:**
- Schema forms silently ignore `pattern` constraints (user-facing limitation)
- Must document prominently in HOW_TO_USE.md that pattern validation is unsupported

### Recommendation

**Option A (vendor a regex engine)** is strongly recommended because:
1. Regex is part of the JSON Schema standard and expected by users
2. A minimal backtracking engine covers 90% of common patterns
3. Pure Zig implementation aligns with the project's philosophy (no external deps beyond approved list)
4. Once written, the regex engine is reusable across other milestones

**If Option A is not feasible, Option C (defer) is acceptable.** Implement the plumbing to accept `pattern` in the schema walker and validator, but have the validator return "pass" without actually matching. Add a "TODO: regex engine" comment.

---

## What to build (ASSUMING OPTION A IS CHOSEN)

### 1. Regex engine module — `src/08/regex.zig`

A pure, allocation-free regex matcher:

```zig
/// Result of pattern compilation.
pub const CompiledPattern = struct {
    bytecode: []const u8,  // DFA state machine encoding (allocated by caller's arena)
    error_msg: ?[]const u8 = null,
};

/// Compile a regex pattern string into an executable bytecode.
/// Returns error if the pattern is malformed.
pub fn compilePattern(alloc: std.mem.Allocator, pattern: []const u8) !CompiledPattern

/// Match a string against a compiled pattern.
/// Returns true if the entire string matches; false otherwise.
pub fn matches(compiled: CompiledPattern, input: []const u8) bool

/// Simple helpers for common patterns (string escaping, pre-compiled common patterns)
pub fn isValidEmail(input: []const u8) bool  // Uses a pre-compiled pattern
pub fn isValidUrl(input: []const u8) bool    // Uses a pre-compiled pattern
```

**Design:**
- Use a bytecode interpreter (simple VM) rather than tree-walking
- State machine compiled as a linear byte sequence: `[opcode, arg, opcode, arg, ...]`
- Support POSIX ERE: `^`, `$`, `.`, `*`, `+`, `?`, `[…]`, `(…)`, `|`, `\`
- Match semantics: anchored to full string (as if pattern is implicitly `^(…)$`)
- Deterministic: no backtracking ambiguity (DFA-like, though may use bounded NFA if simpler)
- No allocations during matching — only during compilation

**Limitations (by design):**
- No capture groups returned (pattern matching only, no extraction)
- No lookahead/lookbehind
- No case-insensitive flag (use `[Aa]` for case-insensitive ranges)
- No Unicode property escapes (`\p{Letter}`)

### 2. Validator extension — `src/08/validator.zig`

Update the `validate` function to check `pattern`:

```zig
// Inside ValidationError enum:
pub const ValidationError = struct {
    path: []const u8,
    kind: enum {
        required_missing,
        type_mismatch,
        min_length,
        max_length,
        minimum,
        maximum,
        enum_not_allowed,
        pattern_mismatch,  // NEW
    },
    message: []const u8,
};

// Inside validator function:
fn validateValue(alloc: Allocator, value: *const Value, schema: *const Schema, path: []const u8) ![]ValidationError {
    // ... existing validation ...

    // NEW: Check pattern if present and value is a string
    if (schema.pattern) |pattern_str| {
        if (value.* == .string) {
            const string_val = value.string;
            const compiled = try compilePattern(alloc, pattern_str);
            defer alloc.free(compiled.bytecode);
            
            if (!matches(compiled, string_val)) {
                try errors.append(.{
                    .path = path,
                    .kind = .pattern_mismatch,
                    .message = try std.fmt.allocPrint(alloc, 
                        "value does not match pattern '{s}'", .{pattern_str}),
                });
            }
        }
    }
}
```

### 3. Schema types extension — `docs/specs/08.types.zig`

```zig
pub const Schema = struct {
    // ... existing fields ...
    pattern: ?[]const u8 = null,  // NEW: regex pattern for string validation
};
```

### 4. Tests

**Unit tests** — `src/08/regex_test.zig`:
- Basic matches: `matches("abc", "abc")` → true, `matches("abc", "def")` → false
- Anchors: `^abc$` matches "abc" but not "xabc" or "abcx"
- Character classes: `[a-z]+` matches "hello" but not "hello123"
- Quantifiers: `a*b` matches "b", "ab", "aab"; `a+b` does NOT match "b"
- Escape sequences: `\.` matches ".", `\\d` matches literal "d" (not a digit)
- Alternation: `cat|dog` matches "cat" or "dog" but not "bird"
- Invalid patterns: `compilePattern("(unclosed")` returns error

**Integration tests** — `src/08/08_test.zig`:
- Schema with `pattern` field; field with `type: "string"` and `pattern: "^[A-Z]"`
- `validate` rejects "abc" (no capital), accepts "Abc"
- Error message includes pattern text

## Non-goals (DO NOT implement — INV-5.4)

- **No capture groups** — pattern matching only, not extraction
- **No case-insensitive flag** — use character classes for case-insensitive matching
- **No Unicode properties** — `\p{Letter}` not supported; use explicit ranges like `[a-zA-Z]`
- **No lookahead/lookbehind** — `(?=…)`, `(?!…)` not supported
- **No backreferences** — `\1`, `\2` not supported
- **No modifiers or flags** — patterns are simple strings, no `/pattern/flags` syntax
- **No `.matches()` in schema runtime** — only during `validate()` call

## Acceptance criteria

1. **Regex engine compiles and tests pass:**
   - `zig test src/08/regex_test.zig` runs without error
   - All pattern/match test cases pass (basic literals, character classes, quantifiers, anchors, alternation, escapes)
   - Performance: matching a 100-char string against a typical pattern completes in <1 ms

2. **Validator integration:**
   - `zig build test-08` passes
   - Schema with `pattern: "^[A-Z]"` on a string field validates correctly
   - `validate()` produces a `.pattern_mismatch` error with a clear message for non-matching values

3. **Documentation:**
   - `glossary.md` updated with `PatternValidator` or similar term (if new glossary entry is needed)
   - Comment in `regex.zig` documents supported POSIX ERE subset and limitations

4. **No regression:**
   - All module 08 existing tests pass
   - All downstream tests pass (modules 09 and app layer)

---

## If Option A is not approved

**Option C fallback:** Update the validator to accept `pattern` in the schema but silently skip it:

```zig
// Pattern validation is a no-op for now
if (schema.pattern) |_| {
    // TODO: regex engine deferred to post-v1
}
```

Document in `HOW_TO_USE.md`:

```
## Known Limitations

- **Pattern validation (M18-01):** Schema `pattern` keyword is parsed but not validated.
  Patterns are accepted without error, but values are not checked against them.
  This is deferred pending a regex engine implementation.
```
