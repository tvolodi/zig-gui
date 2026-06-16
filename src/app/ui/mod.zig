//! UI component library — shadcn/ui-equivalent class string constants.
//!
//! Import this file from any screen:
//!   const ui = @import("../../app/ui/mod.zig");
//!
//! Then use class constants in NodeDesc:
//!   NodeDesc{ .tag = "Card",   .classes = ui.Card.surface,  .attrs = &my_attrs }
//!   NodeDesc{ .tag = "Button", .classes = ui.Button.primary, .attrs = &my_attrs }

pub const Badge     = @import("badge.zig");
pub const Button    = @import("button.zig");
pub const Card      = @import("card.zig");
pub const Input     = @import("input.zig");
pub const Separator = @import("separator.zig");
