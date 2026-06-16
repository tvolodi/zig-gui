//! Button class strings — shadcn Button variants.
//!
//! Usage:
//!   const a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Submit" } }};
//!   const n = NodeDesc{ .tag = "Button", .classes = button.primary, .attrs = &a };

/// Default primary action — accent background applied by renderer.
pub const primary     = "w-full";
/// Secondary/cancel — raised background with border.
pub const secondary   = "border bg-raised";
/// Outline — canvas background with border.
pub const outline     = "border bg-canvas";
/// Ghost — transparent, no border.
pub const ghost       = "bg-canvas";
/// Destructive — caller sets background = tokens.err post-instantiation.
pub const destructive = "bg-raised";
