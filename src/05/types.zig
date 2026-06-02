//! 05 — Theme — src/05/types.zig
//!
//! Re-exports the canonical implementation from docs/specs/05.types.zig.
//! The implementation lives in docs/specs/05.types.zig so the acceptance
//! test in docs/specs/ can resolve its imports correctly via build.zig.

pub usingnamespace @import("../../docs/specs/05.types.zig");
