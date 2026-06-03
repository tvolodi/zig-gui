# R54 — M5-05: Markup error reporting

> Roadmap item: M5-05  
> Depends on: module 06 (`parse`, `ParseError`, `Parser`)  
> Read `00_constitution.md` before this file.

## Purpose

Parse errors include the source line number and column so the developer can locate the
mistake in the `.ui` file immediately. Currently `ParseError` is an enum variant with no
location information — fixing a parse error requires manually hunting through the markup.
This item adds a `ParseDiagnostic` struct that carries the variant plus line/column, and
changes `parse` to return it on failure.

## What to build

### `ParseDiagnostic` — the new error carrier

Replace the bare `ParseError` return from `parse` with a richer type. The `ParseError` enum
itself is kept (it names the error kind); a `ParseDiagnostic` wraps it with source location.

Add to [06.types.zig](../specs/06.types.zig):

```zig
/// Source location within a `.ui` file (1-based, matching editor conventions).
pub const SourceLoc = struct {
    line:   u32,  // 1-based line number
    column: u32,  // 1-based byte column on that line
};

/// Diagnostic emitted by `parse` on failure.
pub const ParseDiagnostic = struct {
    err:    ParseError,
    loc:    SourceLoc,
    /// A human-readable description of the error. Points into static string storage
    /// (no allocation). Used for `std.log.err` output in the hot-reload path and by the
    /// build-time codegen tool.
    message: []const u8,
};
```

### Changes to `parse` signature

The public `parse` function changes return type to carry the diagnostic on failure. Two
options exist; use **option A** (error union with out-param) to avoid heap allocation:

**Option A — error union with out-param (chosen):**

```zig
/// Parse `.ui` markup. On success returns the root NodeDesc. On failure, writes a
/// ParseDiagnostic to `*diag` (if non-null) and returns error.ParseFailed.
pub fn parse(
    allocator: std.mem.Allocator,
    source:    []const u8,
    diag:      ?*ParseDiagnostic,
) error{ ParseFailed, OutOfMemory }!NodeDesc
```

`ParseError` is retired from the public return type; the new return error set is
`{ParseFailed, OutOfMemory}`. The exact `ParseError` variant is in `diag.err`. Callers
that only care about success/failure pass `null` for `diag`; diagnostic consumers pass a
pointer to a stack-allocated `ParseDiagnostic`.

This is a **breaking change** to `parse`'s signature. All callers must be updated:
- The hot-reload path in `App.run()` (M5-07).
- The build-time codegen tool (M5-06).
- All existing unit tests in `docs/specs/06.acceptance_test.zig`.

### Line and column tracking in `Parser`

Add `line` and `column` fields to the `Parser` internal state struct:

```zig
const Parser = struct {
    src:    []const u8,
    pos:    usize,
    alloc:  std.mem.Allocator,
    line:   u32 = 1,    // NEW: current line (1-based)
    column: u32 = 1,    // NEW: current byte column (1-based)

    fn consume(p: *Parser) ?u8 {
        if (p.pos >= p.src.len) return null;
        const c = p.src[p.pos];
        p.pos += 1;
        if (c == '\n') {
            p.line   += 1;
            p.column  = 1;
        } else {
            p.column += 1;
        }
        return c;
    }

    // skipWs and readName also call consume internally — they get line/column tracking
    // automatically as long as they go through consume().
    // The existing `p.pos += 1` patterns in skipWs / readName / expect must be changed
    // to call consume() instead. (A one-time mechanical substitution.)
};
```

### Error emission helper

Add a private helper that constructs a `ParseDiagnostic` from the current parser state:

```zig
fn makeDiag(p: *const Parser, err: ParseError, message: []const u8) ParseDiagnostic {
    return .{
        .err     = err,
        .loc     = .{ .line = p.line, .column = p.column },
        .message = message,
    };
}
```

Each `return ParseError.UnexpectedToken` in the parser becomes:

```zig
if (diag) |d| d.* = p.makeDiag(.UnexpectedToken, "expected '<'");
return error.ParseFailed;
```

### Error messages

Every `ParseError` variant gets a fixed static message string. These are not allocated;
they are `[]const u8` string literals.

| `ParseError` variant | Example message |
|---|---|
| `UnexpectedToken` | `"unexpected character; expected '<', '/', '>', '=', or a name"` |
| `UnclosedTag` | `"tag was opened but never closed"` |
| `MismatchedTag` | `"closing tag does not match the opening tag"` |
| `MalformedAttribute` | `"malformed attribute; expected NAME=\"value\""` |

Where the context provides more specificity (e.g. mismatched tag name known), the message
string is chosen from a small set of static strings, not formatted dynamically. No
`std.fmt.allocPrint` in the parser — keeping it allocation-free (INV-3.1 spirit).

### `parse` wrapper update

```zig
pub fn parse(
    allocator: std.mem.Allocator,
    source:    []const u8,
    diag:      ?*ParseDiagnostic,
) error{ ParseFailed, OutOfMemory }!NodeDesc {
    var p = Parser.init(allocator, source);
    p.skipWs();
    const node = p.parseNode(diag) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ParseFailed,
    };
    return node;
}
```

`parseNode` (and all inner parse functions) carry `diag: ?*ParseDiagnostic` as a parameter
and write to it before returning a parse error.

### Logging convention

The hot-reload path logs on parse failure:

```zig
var diag: ParseDiagnostic = undefined;
const root = parse(arena.allocator(), source, &diag) catch |err| {
    if (err == error.ParseFailed) {
        std.log.err("[hot-reload] {}:{}: {} — {s}",
            .{ diag.loc.line, diag.loc.column, diag.err, diag.message });
    }
    continue;  // keep old scene on parse failure
};
```

The codegen tool exits non-zero and prints the diagnostic to stderr.

### Module location

```zig
src/06/types.zig          — SourceLoc, ParseDiagnostic, parse signature change, Parser.line/column
docs/specs/06.types.zig   — SourceLoc, ParseDiagnostic, updated parse signature
docs/specs/06.acceptance_test.zig — updated to pass diag=null where no diagnostic is needed
docs/requirements/R54_markup_error_reporting.md
```

## Public API

New in module 06:

```zig
pub const SourceLoc = struct { line: u32, column: u32 }
pub const ParseDiagnostic = struct { err: ParseError, loc: SourceLoc, message: []const u8 }
// parse signature changes: gains diag: ?*ParseDiagnostic, returns error{ParseFailed,OutOfMemory}
```

`ParseError` enum remains unchanged (still the name set for error variants).

## Non-goals (DO NOT implement — INV-5.4)

- **No multiple diagnostics per parse** — the parser stops at the first error and emits one
  diagnostic. Collecting all errors in a pass requires error recovery, which is post-v1.
- **No source snippet / caret display** — the diagnostic gives line/column only; no
  `"  ^^^^^^"` underline. That is a display concern for the calling tool, not the parser.
- **No warnings** — only errors; no lint-style advisory messages.
- **No structured error codes** — the `ParseError` enum IS the error code; no numeric codes.
- **No Unicode-aware column counting** — column is byte offset from the start of the line.
  This is correct for the Latin/Cyrillic scope (INV-1.3); multi-byte UTF-8 sequences advance
  column by their byte count, not by Unicode code-point or grapheme-cluster count.

## Acceptance criteria

1. `zig build test-06` passes. All existing tests updated to pass `diag=null` where the
   test does not inspect diagnostics. New test cases:
   - `parse` on `"<Text"` (unclosed) returns `error.ParseFailed` and sets
     `diag.err = .UnclosedTag`.
   - `parse` on `"<Column><Text/></Row>"` (mismatched close tag) sets
     `diag.err = .MismatchedTag`, `diag.loc.line = 1`, `diag.loc.column > 1`.
   - `parse` on a multi-line file where the error is on line 3 sets `diag.loc.line = 3`.
   - `parse` with `diag=null` on an invalid file returns `error.ParseFailed` without
     crashing (no null-pointer dereference).
   - Valid markup still parses successfully.

2. Column tracking: given `"<Text\nclass=\"foo\">bar"`, a parse error on line 2 reports the
   correct column within line 2 (not the absolute byte offset from the file start).

3. The `parse` signature change is backward-compatible in terms of behavior: callers that
   pass `null` for `diag` get the same success/failure behavior as before.

4. No dynamic allocation in the diagnostic path (static message strings only).

5. Checklist fully ticked.

## Open questions

None. The out-param approach (`?*ParseDiagnostic`) avoids heap allocation and is idiomatic
for Zig's error handling model. The breaking signature change is small and mechanical — only
callers of `parse` need updating.
