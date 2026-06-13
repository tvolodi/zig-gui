//! 06 — Markup + style — src/06/types.zig
//!
//! Re-exports the canonical implementation from docs/specs/06.types.zig.
//! The implementation lives in docs/specs/06.types.zig so the acceptance
//! test in docs/specs/ can resolve its imports correctly via build.zig.

const spec = @import("../../docs/specs/06.types.zig");
pub const Attr = spec.Attr;
pub const AttrValue = spec.AttrValue;
pub const ComputedStyle = spec.ComputedStyle;
pub const LayoutNode = spec.LayoutNode;
pub const NodeDesc = spec.NodeDesc;
pub const ParseDiagnostic = spec.ParseDiagnostic;
pub const ParseError = spec.ParseError;
pub const ParseErrorKind = spec.ParseErrorKind;
pub const Resolved = spec.Resolved;
pub const SourceLoc = spec.SourceLoc;
pub const Tokens = spec.Tokens;
pub const parse = spec.parse;
pub const parseFloat = spec.parseFloat;
pub const parseHexColor = spec.parseHexColor;
pub const parseWithDiag = spec.parseWithDiag;
pub const resolveClasses = spec.resolveClasses;
