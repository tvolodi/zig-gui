//! R60/R64 — FontFamily re-export.
//! FontFamily now lives in src/02/types.zig so that layoutParagraphEx can use it
//! without violating the upward-import prohibition (INV-3.4).
pub const FontFamily = @import("../02/types.zig").FontFamily;
