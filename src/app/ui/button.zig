//! Button class strings — AI-Qadam visual-analog Button variants (RN14, 2026-08-01).
//!
//! Ground truth (AI-Qadam components.css): height 40px (h-10 on the 4px scale),
//! border-radius 8px (rounded-md), padding 0 16px (px-4), border 1px, font-size 14px
//! (text-sm), font-weight 500 (font-medium — approximated, see src/06/types.zig comment),
//! gap 8px (gap-2).
//!
//! Usage:
//!   const a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Submit" } }};
//!   const n = NodeDesc{ .tag = "Button", .classes = button.primary, .attrs = &a };
//!
//! RN16 (2026-08-01): all variants below opt into `transition-colors` so hover/press color
//! changes ease over ~150ms (AnimTimeline, ease-out) instead of snapping instantly — matches
//! AI-Qadam's own `transition: all 150ms var(--ease-out)`. See docs/AGENT_GUIDE.md §14.7.

const base = "h-10 rounded-md px-4 gap-2 text-sm font-medium transition-colors";

/// Default primary action — filled teal (tokens.accent) background, accent_text foreground.
/// Both come from theme.buttonPrimary (the base style); no override classes needed here.
pub const primary = base;
/// Secondary — raised background with border (AI-Qadam .btn-secondary: bg-raised + border).
pub const secondary = base ++ " border bg-raised";
/// Outline — transparent/canvas background with border (AI-Qadam .btn-outline).
pub const outline = base ++ " border bg-canvas";
/// Ghost — transparent, no border (AI-Qadam .btn-ghost).
pub const ghost = base ++ " bg-transparent";
/// Destructive — caller sets background = tokens.err post-instantiation (AI-Qadam
/// .btn-destructive uses the destructive token as background; not expressible as a static
/// class string since there is no bg-err class in the module-06 resolver).
pub const destructive = base;
/// RN16 — Loading/busy variant: same visual base as primary, but callers additionally set the
/// `loading="true"` attribute (src/07/types.zig ButtonState.loading) to replace the label with
/// a spinner-style busy indicator driven by scene.frame_count. Usage:
///   const a = [1]Attr{.{ .name = "loading", .value = .{ .literal = "true" } }};
///   const n = NodeDesc{ .tag = "Button", .classes = button.loading, .attrs = &a };
pub const loading = base;
