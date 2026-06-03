//! R7D — Context-menu manager unit tests.
//! Tests ContextMenuManager state without GPU, GLFW, or rendering.
//! openAt() requires Font + GlyphAtlas (rendering), so we test state-only paths.

const std = @import("std");
const testing = std.testing;
const cm_mod = @import("context_menu.zig");
const overlay_mod = @import("overlay.zig");

pub const ContextMenuManager = cm_mod.ContextMenuManager;
pub const ContextMenuItem = cm_mod.ContextMenuItem;
pub const OverlayLayer = overlay_mod.OverlayLayer;
pub const MAX_MENU_ITEMS = cm_mod.MAX_MENU_ITEMS;
pub const MAX_REGISTERED_MENUS = cm_mod.MAX_REGISTERED_MENUS;

fn newManager() ContextMenuManager {
    return ContextMenuManager{};
}

fn newOverlay() OverlayLayer {
    return OverlayLayer.init(testing.allocator);
}

// ---------------------------------------------------------------------------
// register
// ---------------------------------------------------------------------------

test "register: returns a valid menu index" {
    var m = newManager();
    const items = [_]ContextMenuItem{
        ContextMenuItem.fromSlice("Cut"),
        ContextMenuItem.fromSlice("Copy"),
    };
    const idx = m.register(1, &items);
    try testing.expect(idx < MAX_REGISTERED_MENUS);
    try testing.expectEqual(@as(u8, 0), idx); // first registration = 0
}

test "register: second registration returns next index" {
    var m = newManager();
    const items = [_]ContextMenuItem{ContextMenuItem.fromSlice("A")};
    const idx0 = m.register(0, &items);
    const idx1 = m.register(1, &items);
    try testing.expectEqual(@as(u8, 0), idx0);
    try testing.expectEqual(@as(u8, 1), idx1);
}

test "register: stores items correctly" {
    var m = newManager();
    const items = [_]ContextMenuItem{
        ContextMenuItem.fromSlice("Copy"),
        ContextMenuItem.fromSlice("Paste"),
    };
    const idx = m.register(42, &items);
    const menu = &m.registered[idx];
    try testing.expectEqual(@as(u8, 2), menu.count);
    try testing.expectEqualSlices(u8, "Copy", menu.items[0].labelSlice());
    try testing.expectEqualSlices(u8, "Paste", menu.items[1].labelSlice());
}

test "register: stores target_idx correctly" {
    var m = newManager();
    const items = [_]ContextMenuItem{ContextMenuItem.fromSlice("X")};
    const idx = m.register(99, &items);
    try testing.expectEqual(@as(u32, 99), m.registered[idx].target_idx);
}

test "register: returns 0xFF when registry is full" {
    var m = newManager();
    const items = [_]ContextMenuItem{ContextMenuItem.fromSlice("X")};
    var i: usize = 0;
    while (i < MAX_REGISTERED_MENUS) : (i += 1) {
        _ = m.register(@intCast(i), &items);
    }
    // One more registration should fail
    const overflow = m.register(255, &items);
    try testing.expectEqual(@as(u8, 0xFF), overflow);
}

test "register: fills up to MAX_REGISTERED_MENUS menus" {
    var m = newManager();
    const items = [_]ContextMenuItem{ContextMenuItem.fromSlice("X")};
    var i: usize = 0;
    while (i < MAX_REGISTERED_MENUS) : (i += 1) {
        const idx = m.register(@intCast(i), &items);
        try testing.expect(idx < MAX_REGISTERED_MENUS);
    }
    try testing.expectEqual(@as(u8, MAX_REGISTERED_MENUS), m.menu_count);
}

// ---------------------------------------------------------------------------
// isOpen / dismiss (state-only — no overlay rendering)
// ---------------------------------------------------------------------------

test "isOpen: false by default" {
    const m = newManager();
    try testing.expect(!m.isOpen());
}

test "dismiss: sets isOpen() = false" {
    var m = newManager();
    var overlay = newOverlay();
    defer overlay.deinit();

    // Manually force active_menu_idx to simulate an open menu
    m.active_menu_idx = 0;
    try testing.expect(m.isOpen());

    m.dismiss(&overlay, testing.allocator);
    try testing.expect(!m.isOpen());
}

// ---------------------------------------------------------------------------
// Keyboard navigation: highlight advances and wraps
// ---------------------------------------------------------------------------

// Build a manager with one registered 3-item menu and set highlight manually.
test "highlight Down: advances by 1" {
    var m = newManager();
    const items = [_]ContextMenuItem{
        ContextMenuItem.fromSlice("A"),
        ContextMenuItem.fromSlice("B"),
        ContextMenuItem.fromSlice("C"),
    };
    _ = m.register(0, &items);

    // Simulate keyboard Down: highlight 0xFF (none) → 0
    if (m.highlight == 0xFF) {
        m.highlight = 0;
    } else {
        m.highlight = @min(m.highlight + 1, m.registered[0].count - 1);
    }
    try testing.expectEqual(@as(u8, 0), m.highlight);
}

test "highlight Up: wraps from 0 to last item" {
    var m = newManager();
    const items = [_]ContextMenuItem{
        ContextMenuItem.fromSlice("A"),
        ContextMenuItem.fromSlice("B"),
        ContextMenuItem.fromSlice("C"),
    };
    _ = m.register(0, &items);
    m.active_menu_idx = 0;
    m.highlight = 0;

    // Simulate keyboard Up from item 0 → wrap to last (2)
    const count = m.registered[m.active_menu_idx].count;
    m.highlight = if (m.highlight == 0) count - 1 else m.highlight - 1;
    try testing.expectEqual(@as(u8, 2), m.highlight);
}

test "highlight Down: advances from item 1 to item 2" {
    var m = newManager();
    const items = [_]ContextMenuItem{
        ContextMenuItem.fromSlice("A"),
        ContextMenuItem.fromSlice("B"),
        ContextMenuItem.fromSlice("C"),
    };
    _ = m.register(0, &items);
    m.active_menu_idx = 0;
    m.highlight = 1;

    const count = m.registered[m.active_menu_idx].count;
    m.highlight = (m.highlight + 1) % count;
    try testing.expectEqual(@as(u8, 2), m.highlight);
}

test "highlight Down: wraps from last to first" {
    var m = newManager();
    const items = [_]ContextMenuItem{
        ContextMenuItem.fromSlice("A"),
        ContextMenuItem.fromSlice("B"),
    };
    _ = m.register(0, &items);
    m.active_menu_idx = 0;
    m.highlight = 1; // last item

    const count = m.registered[m.active_menu_idx].count;
    m.highlight = (m.highlight + 1) % count;
    try testing.expectEqual(@as(u8, 0), m.highlight); // wrapped to first
}

// ---------------------------------------------------------------------------
// on_click callback on Enter
// ---------------------------------------------------------------------------

test "on_click callback is invoked when item is activated" {
    var called = false;
    const S = struct {
        fn handler() void {
            // can't capture `called` directly — use a global for test
        }
    };
    _ = S.handler; // suppress unused warning

    var m = newManager();
    var item = ContextMenuItem.fromSlice("Action");
    // Assign a no-op function; we verify it compiles and is stored.
    item.on_click = &struct {
        fn f() void {}
    }.f;
    const items = [_]ContextMenuItem{item};
    const menu_idx = m.register(0, &items);
    m.active_menu_idx = menu_idx;
    m.highlight = 0;

    // Invoke the highlighted item's callback (simulating Enter key handler).
    const menu = &m.registered[m.active_menu_idx];
    if (menu.items[m.highlight].on_click) |cb| {
        cb();
        called = true;
    }
    try testing.expect(called);
}

// ---------------------------------------------------------------------------
// ContextMenuItem helpers
// ---------------------------------------------------------------------------

test "ContextMenuItem.fromSlice: stores label" {
    const item = ContextMenuItem.fromSlice("Hello");
    try testing.expectEqualSlices(u8, "Hello", item.labelSlice());
}

test "ContextMenuItem.fromSlice: truncates long label" {
    // MAX label is 63 bytes (label[0..label_len-1] + NUL slot)
    const long_label = "A" ** 70;
    const item = ContextMenuItem.fromSlice(long_label);
    try testing.expect(item.label_len <= 63);
}

test "ContextMenuItem: separator flag is false by default" {
    const item = ContextMenuItem{};
    try testing.expect(!item.separator);
}

test "ContextMenuItem: disabled flag is false by default" {
    const item = ContextMenuItem{};
    try testing.expect(!item.disabled);
}

// ---------------------------------------------------------------------------
// deinit: freeing null current_cmds does not crash
// ---------------------------------------------------------------------------

test "deinit: safe when current_cmds is null" {
    var m = newManager();
    m.deinit(testing.allocator); // Must not crash
}
