# Validator Fixes — Completion Summary

**Date:** 2026-06-03  
**Session:** Implementer — applying 7 validator-identified fixes

---

## What was built

Applied all 7 validation fixes identified by the Validator agent for the M7 Phase 3 codebase:

### Fix 1 — `initialsColor` hex literals removed (`src/09/types.zig`)
Replaced 8-color hardcoded `Color` array with a 4-branch `switch` over `c % 4` returning
`tokens.accent`, `tokens.ok`, `tokens.warn`, `tokens.err`. Satisfies INV-4.3 (no hex
literals in rendering code).

### Fix 2 — Tooltip token names corrected (`src/app/tooltip.zig`)
- `tokens.bg_surface` → `tokens.bg_raised` (background quad)
- `tokens.text_primary` → `tokens.text_body` (glyph color)
- `const font_size: f32 = 13.0` → `tokens.text_sm` (token-derived size)

### Fix 3 — Context menu token names corrected (`src/app/context_menu.zig`)
- `tokens.text_on_accent` → `tokens.accent_text` (highlighted item text)
- `tokens.text_primary` → `tokens.text_body` (normal item text)

### Fix 4 — BadgeState replaced with spec version (`src/07/types.zig`)
Added `BadgeColor = enum { default, success, warning, error_c }`.  
`BadgeState` changed from `{ count: u32, visible: bool, color: Color }` to `{ text: [8]u8, color: BadgeColor }`.  
Badge rendering in `src/09/types.zig` updated to match: checks `bs.text[0] != 0` for
visibility, uses `switch (bs.color)` to pick semantic token color.  
Spec file `docs/specs/07.types.zig` updated with new types.

### Fix 5 — CellTextFn/DataTableRows replaced with spec version (`src/07/types.zig`)
`CellTextFn` changed from `fn(ctx, row: u32, col, buf) []u8` to `fn(row_ptr, col, buf) u8`.  
`DataTableRows` changed from `{ ctx, row_count, cell_text }` to `{ row_ptr, row_size: usize, row_count, cell_fn }`.  
`sortTable` in `src/07/types.zig` updated to compute row pointers via `row_base + key * row_size`.  
DataTable cell rendering in `src/09/types.zig` updated similarly.  
Unit tests in `src/07/m7_widget_test.zig` updated: `testCellText` uses new signature;
three `DataTableRows` literals updated to `row_ptr = &row_indices[0], row_size = @sizeOf(u32)`.  
Spec file `docs/specs/07.types.zig` updated with new types.

### Fix 6 — R7D implementation decision note (`docs/requirements/R7D_context_menu.md`)
Added blockquote at top of file documenting: Model A chosen, `registerNamed` not
implemented, `context_menu` attribute stores u8 index.

### Fix 7 — ROADMAP.md Milestone 7 table updated (`docs/ROADMAP.md`)
Changed `planned` → `done`, added `Requirements` and `Status` columns with links to all
14 requirement files, each row marked `done`.

---

## Tests that pass

- `zig build` — clean compile (no output)
- `test-07` — pass
- `test-07-unit` — pass
- `test-08` — pass
- `test-09-unit` — pass
- `test-m7-widget` — pass
- `test-tooltip` — pass
- `test-context-menu` — pass
- `test-09` — all 12 tests pass (pre-existing zig build stderr issue from VK layer duplicate message)
- `test-app` — all 6 tests pass (pre-existing zig build stderr issue from EventQueue overflow warn)

---

## Documentation updated

- **AGENT_GUIDE.md**: Updated R7B entry (BadgeState new fields, avatar 4-token color),
  updated R79 entry (CellTextFn new signature, row_ptr/row_size pattern).
- **00_constitution.md**: No "Action: update constitution" items found in spec files; no changes required.
- **HOW_TO_USE.md**: Updated Badge code example (new text/BadgeColor API), fixed avatar
  color description (4 tokens not 8-color palette), updated DataTable code example
  (row_ptr/row_size/cell_fn pattern).
- **No new patterns introduced** beyond those already noted above.
