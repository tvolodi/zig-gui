# Milestone 15 — Internationalisation — Completion Summary

**Date:** 2026-06-13
**Implemented by:** Orchestrator → Implementer agents

## Summary

Milestone 15 adds four locale-aware features that extend the framework for internationalized UI content: number formatting with locale-aware thousands/decimal separators, date formatting with locale-aware date order and month names, a build-time string table codegen tool for i18n, and RTL layout direction support in the flex solver and renderer.

## Files created
- `src/app/locale.zig` — Locale struct, DateOrder enum, formatInt, formatFloat, formatDate, formatDateLong, formatDateShort, StringParam, formatString
- `src/app/locale_test.zig` — 54 unit tests for all locale formatting functions
- `src/tools/string_table_codegen.zig` — Build-time codegen executable that parses strings.en.txt and emits Zig const table with comptime t()
- `src/strings.en.txt` — Initial English string table with 6 entries
- `docs/requirements/RE0_number_formatting.md` — Requirement spec
- `docs/requirements/RE1_date_time_formatting.md` — Requirement spec
- `docs/requirements/RE2_string_table.md` — Requirement spec
- `docs/requirements/RE3_rtl_layout_direction.md` — Requirement spec

## Files modified
- `docs/specs/03.types.zig` — Direction enum, LayoutNode.layout_direction field
- `docs/03_element_store/types.zig` — Same Direction + layout_direction (needed by module 04's import path)
- `docs/specs/04.types.zig` — Flex solver RTL reversal in solveFlex() Phase 3
- `docs/specs/06.types.zig` — direction-rtl, direction-ltr class resolution
- `docs/specs/glossary.md` — Direction, layout_direction glossary entries
- `src/09/types.zig` — RTL text alignment in buildDrawList for .text and .input elements
- `docs/requirements/DEMO_APP.md` — RTL layout section in Layout screen
- `build.zig` — test-locale step, string table codegen step
- `docs/ROADMAP.md` — M15 marked done

## Test results
- `zig build` — passes
- `zig build test-locale` — 54/54 pass
- `zig build test-05` — passes
- `zig build test-06` — passes
- `zig build test-09-unit` — passes
- `zig build test-07-unit` — 85/86 pass (pre-existing defaultLayoutFor test unrelated)
- `zig build test-anim-timeline` — passes
- `test-04` — pre-existing acceptance test mismatch (solve signature changed when dpi_scale was added, acceptance test not updated). Not caused by M15.
