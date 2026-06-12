//! sidebar.zig — Sidebar NodeDesc builder for the Showcase Demo.
//!
//! Builds the left navigation column with 8 screen-selection buttons.
//! active_name: the name of the currently displayed screen (for visual highlight).

const std = @import("std");
const mod06 = @import("../06/types.zig");

const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;

pub const SCREEN_NAMES = [8][]const u8{
    "home", "text", "forms", "data", "theme", "notifications", "layout", "state",
};

pub const SCREEN_LABELS = [8][]const u8{
    "Home", "Text", "Forms", "Data", "Theme", "Notifications", "Layout", "State",
};

// Module-level static storage — persists for program lifetime, safe for pointer stability.
var _btn_attrs: [8][1]Attr = [_][1]Attr{
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Home" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Text" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Forms" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Data" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Theme" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Notifications" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "Layout" } }},
    [1]Attr{.{ .name = "text", .value = .{ .literal = "State" } }},
};

var _btns: [8]NodeDesc = [_]NodeDesc{
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[0], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[1], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[2], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[3], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[4], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[5], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[6], .children = &.{} },
    .{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[7], .children = &.{} },
};

/// Return the sidebar NodeDesc (children = 8 Buttons at DFS indices 2–9).
/// Safe to call from any screen function; uses module-level storage with program lifetime.
pub fn buildSidebar() NodeDesc {
    return NodeDesc{
        .tag = "Column",
        .classes = "w-36 gap-1 p-2 bg-surface",
        .attrs = &.{},
        .children = &_btns,
    };
}
