//! 03 — Element store — src/03/types.zig
//!
//! Re-exports the canonical implementation from docs/specs/03.types.zig.

const spec = @import("../../docs/specs/03.types.zig");
pub const NONE = spec.NONE;
pub const ElementId = spec.ElementId;
pub const Rect = spec.Rect;
pub const Size = spec.Size;
pub const Constraints = spec.Constraints;
pub const Insets = spec.Insets;
pub const Dimension = spec.Dimension;
pub const TrackSize = spec.TrackSize;
pub const Display = spec.Display;
pub const FlexDirection = spec.FlexDirection;
pub const JustifyContent = spec.JustifyContent;
pub const AlignItems = spec.AlignItems;
pub const LayoutNode = spec.LayoutNode;
pub const ElementStore = spec.ElementStore;
pub const Element = spec.Element;
