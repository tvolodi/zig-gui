//! sidebar.zig — Sidebar NodeDesc builder for the Showcase Demo.
//!
//! Builds the left navigation column with 8 screen-selection buttons.
//! active_name: the name of the currently displayed screen (for visual highlight).

const std = @import("std");
const mod06 = @import("../06/types.zig");

const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;

pub const SCREEN_NAMES = [14][]const u8{
    "home", "text", "forms", "data", "theme", "notifications", "layout", "state", "m12", "m13", "dashboard", "ecommerce", "components", "aiqadam",
};

pub const SCREEN_LABELS = [14][]const u8{
    "Home", "Text", "Forms", "Data", "Theme", "Notifications", "Layout", "State", "M12", "M13", "Dashboard", "Ecommerce", "Components", "AI-Qadam",
};

// Module-level static storage — persists for program lifetime, safe for pointer stability.
var _btn_attrs: [14][1]Attr = [_][1]Attr{
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Home" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Text" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Forms" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Data" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Theme" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Notifications" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Layout" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "State" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "M12" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "M13" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Dashboard" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Ecommerce" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Components" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "AI-Qadam" } }},
};

var _btns: [14]NodeDesc = [_]NodeDesc{
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[0], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[1], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[2], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[3], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[4], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[5], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[6], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[7], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[8], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[9], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[10], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[11], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[12], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[13], .children = &.{} },
};

/// Return the sidebar NodeDesc (children = 10 Buttons at DFS indices 2–11).
/// Safe to call from any screen function; uses module-level storage with program lifetime.
pub fn buildSidebar() NodeDesc {
    return NodeDesc{
        .tag = "Column",
        .classes = "w-36 gap-1 p-2 bg-surface",
        .attrs = &.{},
        .children = &_btns,
    };
}
