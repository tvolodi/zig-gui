//! 07 — Components — unit tests
//! Edge cases and boundary conditions not fully covered by the acceptance test.

const std = @import("std");
const testing = std.testing;
const C = @import("types.zig");
const store_mod = @import("../03/types.zig");
const theme_mod = @import("../05/types.zig");
const markup_mod = @import("../06/types.zig");

fn testTokens() theme_mod.Tokens {
    return theme_mod.Tokens.light(theme_mod.Palette.default());
}

// ---------------------------------------------------------------------------
// tagToKind — exhaustive coverage of all 7 tags
// ---------------------------------------------------------------------------

test "tagToKind covers all seven kinds" {
    try testing.expectEqual(C.WidgetKind.text, C.tagToKind("Text").?);
    try testing.expectEqual(C.WidgetKind.button, C.tagToKind("Button").?);
    try testing.expectEqual(C.WidgetKind.input, C.tagToKind("Input").?);
    try testing.expectEqual(C.WidgetKind.card, C.tagToKind("Card").?);
    try testing.expectEqual(C.WidgetKind.row, C.tagToKind("Row").?);
    try testing.expectEqual(C.WidgetKind.column, C.tagToKind("Column").?);
    try testing.expectEqual(C.WidgetKind.dropdown, C.tagToKind("Dropdown").?);
    // Case-sensitive: lowercase is unknown
    try testing.expect(C.tagToKind("button") == null);
    try testing.expect(C.tagToKind("text") == null);
    try testing.expect(C.tagToKind("") == null);
}

// ---------------------------------------------------------------------------
// defaultLayoutFor — all 7 kinds
// ---------------------------------------------------------------------------

test "defaultLayoutFor all seven kinds" {
    try testing.expectEqual(store_mod.Display.flex, C.defaultLayoutFor(.row).display);
    try testing.expectEqual(store_mod.FlexDirection.row, C.defaultLayoutFor(.row).direction);
    try testing.expectEqual(store_mod.Display.flex, C.defaultLayoutFor(.column).display);
    try testing.expectEqual(store_mod.FlexDirection.column, C.defaultLayoutFor(.column).direction);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.text).display);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.button).display);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.input).display);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.card).display);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.dropdown).display);
}

// ---------------------------------------------------------------------------
// defaultStyleFor — per-kind defaults
// ---------------------------------------------------------------------------

test "defaultStyleFor button returns buttonPrimary (accent background)" {
    const t = testTokens();
    const s = C.defaultStyleFor(.button, t);
    try testing.expectEqual(t.accent.r, s.background.r);
    try testing.expectEqual(t.accent.g, s.background.g);
    try testing.expectEqual(t.accent.b, s.background.b);
    try testing.expect(s.padding.left > 0);
    try testing.expect(s.padding.top > 0);
}

test "defaultStyleFor card returns cardSurface (bg_surface background)" {
    const t = testTokens();
    const s = C.defaultStyleFor(.card, t);
    try testing.expectEqual(t.bg_surface.r, s.background.r);
    try testing.expect(s.padding.left > 0);
    try testing.expect(s.border_width > 0);
}

test "defaultStyleFor input and dropdown return inputDefault" {
    const t = testTokens();
    const si = C.defaultStyleFor(.input, t);
    const sd = C.defaultStyleFor(.dropdown, t);
    try testing.expectEqual(t.bg_surface.r, si.background.r);
    try testing.expectEqual(si.background.r, sd.background.r);
    try testing.expectEqual(si.border_width, sd.border_width);
}

test "defaultStyleFor text/row/column returns transparent background" {
    const t = testTokens();
    const st = C.defaultStyleFor(.text, t);
    const sr = C.defaultStyleFor(.row, t);
    const sc = C.defaultStyleFor(.column, t);
    try testing.expectEqual(@as(u8, 0), st.background.a);
    try testing.expectEqual(@as(u8, 0), sr.background.a);
    try testing.expectEqual(@as(u8, 0), sc.background.a);
}

// ---------------------------------------------------------------------------
// Scene.count() accuracy
// ---------------------------------------------------------------------------

test "count() tracks element additions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    try testing.expectEqual(@as(u32, 0), scene.count());

    const d1 = try markup_mod.parse(arena.allocator(), "<Text text=\"a\"/>");
    _ = try scene.instantiate(d1, testTokens());
    try testing.expectEqual(@as(u32, 1), scene.count());

    const d2 = try markup_mod.parse(arena.allocator(), "<Button text=\"b\"/>");
    _ = try scene.instantiate(d2, testTokens());
    try testing.expectEqual(@as(u32, 2), scene.count());
}

// ---------------------------------------------------------------------------
// Deeply nested tree: 3 levels, parent links at every level
// ---------------------------------------------------------------------------

test "deeply nested tree has correct parent links at every level" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Row>
        \\    <Button text="deep"/>
        \\  </Row>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const col_id = try scene.instantiate(desc, testTokens());

    var col_it = scene.store().childrenOf(col_id);
    const row_id = col_it.next().?;
    try testing.expect(col_it.next() == null);

    var row_it = scene.store().childrenOf(row_id);
    const btn_id = row_it.next().?;
    try testing.expect(row_it.next() == null);

    // Parent of row is col
    try testing.expectEqual(col_id.index, scene.store().parentOf(row_id).?.index);
    // Parent of button is row
    try testing.expectEqual(row_id.index, scene.store().parentOf(btn_id).?.index);

    try testing.expectEqual(C.WidgetKind.column, scene.kindOf(col_id));
    try testing.expectEqual(C.WidgetKind.row, scene.kindOf(row_id));
    try testing.expectEqual(C.WidgetKind.button, scene.kindOf(btn_id));
}

// ---------------------------------------------------------------------------
// Multiple resets — no stale state
// ---------------------------------------------------------------------------

test "multiple reset cycles leave no stale state" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();

    const d = try markup_mod.parse(arena.allocator(), "<Column><Text text=\"a\"/><Text text=\"b\"/></Column>");

    // First populate + reset
    _ = try scene.instantiate(d, testTokens());
    try testing.expectEqual(@as(u32, 3), scene.count());
    scene.reset();
    try testing.expectEqual(@as(u32, 0), scene.count());

    // Second populate + reset
    _ = try scene.instantiate(d, testTokens());
    try testing.expectEqual(@as(u32, 3), scene.count());
    scene.reset();
    try testing.expectEqual(@as(u32, 0), scene.count());

    // Third populate — kinds must be correct, no residue from previous cycles
    const root3 = try scene.instantiate(d, testTokens());
    try testing.expectEqual(C.WidgetKind.column, scene.kindOf(root3));
    var it = scene.store().childrenOf(root3);
    const c1 = it.next().?;
    const c2 = it.next().?;
    try testing.expect(it.next() == null);
    try testing.expectEqual(C.WidgetKind.text, scene.kindOf(c1));
    try testing.expectEqual(C.WidgetKind.text, scene.kindOf(c2));
    try testing.expectEqualStrings("a", scene.textOf(c1).?);
    try testing.expectEqualStrings("b", scene.textOf(c2).?);
}

// ---------------------------------------------------------------------------
// Style merge: class overrides specific fields while defaults survive
// ---------------------------------------------------------------------------

test "button with text-muted class: text_color changes, background stays accent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = testTokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Button class=\"text-muted\" text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, t);
    const s = scene.styleOf(id);
    // text_color was overridden
    try testing.expectEqual(t.text_muted.r, s.text_color.r);
    try testing.expectEqual(t.text_muted.g, s.text_color.g);
    // background is still accent (default survived)
    try testing.expectEqual(t.accent.r, s.background.r);
    // padding survived
    try testing.expect(s.padding.left > 0);
}

test "row with gap-4 class has gap=16" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Row class=\"gap-4\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    // gap-4 → 4 * 4 = 16
    try testing.expectEqual(@as(f32, 16), scene.store().get(id).gap);
    // Row keeps its flex display
    try testing.expectEqual(store_mod.Display.flex, scene.store().get(id).display);
}

// ---------------------------------------------------------------------------
// Layout merge: flex properties on Column
// ---------------------------------------------------------------------------

test "column with justify-center retains flex and column direction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Column class=\"justify-center\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const node = scene.store().get(id);
    try testing.expectEqual(store_mod.Display.flex, node.display);
    try testing.expectEqual(store_mod.FlexDirection.column, node.direction);
    try testing.expectEqual(store_mod.JustifyContent.center, node.justify_content);
}

// ---------------------------------------------------------------------------
// Text widget — transparent background, no default style
// ---------------------------------------------------------------------------

test "text widget has transparent background and correct text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"hello\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try testing.expectEqual(C.WidgetKind.text, scene.kindOf(id));
    try testing.expectEqualStrings("hello", scene.textOf(id).?);
    // Text has no default style — background is transparent (alpha = 0)
    try testing.expectEqual(@as(u8, 0), scene.styleOf(id).background.a);
}

// ---------------------------------------------------------------------------
// Dropdown default style matches inputDefault
// ---------------------------------------------------------------------------

test "dropdown default style has border and bg_surface background" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = testTokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Dropdown/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, t);
    const s = scene.styleOf(id);
    try testing.expectEqual(t.bg_surface.r, s.background.r);
    try testing.expectEqual(t.bg_surface.g, s.background.g);
    try testing.expect(s.border_width > 0);
}

// ===========================================================================
// R30 — Focus model
// ===========================================================================

test "R30: initial focused_idx is no-focus (maxInt u32)" {
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    try testing.expectEqual(std.math.maxInt(u32), scene.getFocus());
}

test "R30: setFocus and getFocus round-trip" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.setFocus(id.index);
    try testing.expectEqual(id.index, scene.getFocus());
}

test "R30: setFocus(maxInt) clears focus" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.setFocus(id.index);
    try testing.expectEqual(id.index, scene.getFocus());
    scene.setFocus(std.math.maxInt(u32));
    try testing.expectEqual(std.math.maxInt(u32), scene.getFocus());
}

test "R30: isFocusable true for button, input, dropdown, checkbox" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Column(0), Button(1), Input(2), Dropdown(3), Checkbox(4)
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Button text="b"/>
        \\  <Input/>
        \\  <Dropdown/>
        \\  <Checkbox/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());
    try testing.expect(scene.isFocusable(1)); // button
    try testing.expect(scene.isFocusable(2)); // input
    try testing.expect(scene.isFocusable(3)); // dropdown
    try testing.expect(scene.isFocusable(4)); // checkbox
}

test "R30: isFocusable false for column, text, row, card, scrollview" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Column(0), Text(1), Row(2), Card(3), ScrollView(4)
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Text text="label"/>
        \\  <Row/>
        \\  <Card/>
        \\  <ScrollView/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());
    try testing.expect(!scene.isFocusable(0)); // column
    try testing.expect(!scene.isFocusable(1)); // text
    try testing.expect(!scene.isFocusable(2)); // row
    try testing.expect(!scene.isFocusable(3)); // card
    try testing.expect(!scene.isFocusable(4)); // scrollview
}

test "R30: focusNext advances through focusable_indices in order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Column(0), Button(1), Button(2), Button(3)
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Button text="a"/>
        \\  <Button text="b"/>
        \\  <Button text="c"/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());
    // focusable_indices = [1, 2, 3]
    scene.setFocus(1);
    scene.focusNext();
    try testing.expectEqual(@as(u32, 2), scene.getFocus());
    scene.focusNext();
    try testing.expectEqual(@as(u32, 3), scene.getFocus());
}

test "R30: focusNext wraps from last to first" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Column(0), Button(1), Button(2), Button(3)
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Button text="a"/>
        \\  <Button text="b"/>
        \\  <Button text="c"/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());
    // focusable_indices = [1, 2, 3]
    scene.setFocus(3); // last focusable
    scene.focusNext();
    try testing.expectEqual(@as(u32, 1), scene.getFocus()); // wraps to first
}

test "R30: focusNext with single focusable element and no prior focus focuses it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    // focusable_indices = [0]; no focus initially
    try testing.expectEqual(std.math.maxInt(u32), scene.getFocus());
    scene.focusNext();
    try testing.expectEqual(id.index, scene.getFocus());
}

test "R30: focusPrev goes backward through focusable_indices" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Column(0), Button(1), Button(2), Button(3)
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Button text="a"/>
        \\  <Button text="b"/>
        \\  <Button text="c"/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());
    // focusable_indices = [1, 2, 3]
    scene.setFocus(3);
    scene.focusPrev();
    try testing.expectEqual(@as(u32, 2), scene.getFocus());
    scene.focusPrev();
    try testing.expectEqual(@as(u32, 1), scene.getFocus());
}

test "R30: focusPrev wraps from first to last" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Column(0), Button(1), Button(2), Button(3)
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Button text="a"/>
        \\  <Button text="b"/>
        \\  <Button text="c"/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());
    // focusable_indices = [1, 2, 3]
    scene.setFocus(1); // first focusable
    scene.focusPrev();
    try testing.expectEqual(@as(u32, 3), scene.getFocus()); // wraps to last
}

test "R30: focusPrev with no prior focus focuses last element" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Column(0), Button(1), Button(2), Button(3)
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Button text="a"/>
        \\  <Button text="b"/>
        \\  <Button text="c"/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());
    // focusable_indices = [1, 2, 3]; no focus
    scene.focusPrev();
    try testing.expectEqual(@as(u32, 3), scene.getFocus());
}

test "R30: setFocus marks the focused element dirty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.elements.clearDirty();
    try testing.expect(!scene.elements.dirty.isSet(id.index));
    scene.setFocus(id.index);
    try testing.expect(scene.elements.dirty.isSet(id.index));
}

// ===========================================================================
// R31 — Button interaction
// ===========================================================================

test "R31: newly instantiated button state is not hovered, pressed, or disabled" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"click\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const state = scene.buttonStateOf(id.index);
    try testing.expect(!state.hovered);
    try testing.expect(!state.pressed);
    try testing.expect(!state.disabled);
}

test "R31: buttonStateOf pressed field round-trips" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.buttonStateOf(id.index).pressed = true;
    try testing.expect(scene.buttonStateOf(id.index).pressed);
    scene.buttonStateOf(id.index).pressed = false;
    try testing.expect(!scene.buttonStateOf(id.index).pressed);
}

test "R31: buttonStateOf hovered field round-trips" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.buttonStateOf(id.index).hovered = true;
    try testing.expect(scene.buttonStateOf(id.index).hovered);
    scene.buttonStateOf(id.index).hovered = false;
    try testing.expect(!scene.buttonStateOf(id.index).hovered);
}

test "R31: queueCallback + fireQueuedCallbacks fires callback exactly once then clears" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());

    var fired: u32 = 0;
    const cb = C.CallbackFn{
        .ptr = &fired,
        .call = struct {
            fn f(ptr: *anyopaque) void {
                const p: *u32 = @ptrCast(@alignCast(ptr));
                p.* += 1;
            }
        }.f,
    };

    // Append to the queue directly (app.zig populates this during mouse events).
    try scene._queued_callbacks.append(scene.gpa, cb);
    // Not fired yet — fire only happens via fireQueuedCallbacks.
    try testing.expectEqual(@as(u32, 0), fired);
    scene.fireQueuedCallbacks();
    try testing.expectEqual(@as(u32, 1), fired);
    // Queue is cleared: a second fire does nothing.
    scene.fireQueuedCallbacks();
    try testing.expectEqual(@as(u32, 1), fired);
}

test "R31: multiple queued callbacks all fire in a single fireQueuedCallbacks call" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());

    var counter: u32 = 0;
    const cb = C.CallbackFn{
        .ptr = &counter,
        .call = struct {
            fn f(ptr: *anyopaque) void {
                const p: *u32 = @ptrCast(@alignCast(ptr));
                p.* += 1;
            }
        }.f,
    };
    try scene._queued_callbacks.append(scene.gpa, cb);
    try scene._queued_callbacks.append(scene.gpa, cb);
    try scene._queued_callbacks.append(scene.gpa, cb);
    scene.fireQueuedCallbacks();
    try testing.expectEqual(@as(u32, 3), counter);
}

test "R31: disabled flag is false by default and can be set true" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try testing.expect(!scene.buttonStateOf(id.index).disabled);
    scene.buttonStateOf(id.index).disabled = true;
    try testing.expect(scene.buttonStateOf(id.index).disabled);
    // Verify manually: app.zig checks `!state.disabled` before setting hovered or pressed.
}

test "R31: setButtonCallback stores on_click in button state" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    var dummy: u32 = 0;
    const cb = C.CallbackFn{
        .ptr = &dummy,
        .call = struct {
            fn f(_: *anyopaque) void {}
        }.f,
    };
    try scene.setButtonCallback(id.index, cb);
    try testing.expect(scene.buttonStateOf(id.index).on_click != null);
}

// ===========================================================================
// R32 — Text input editing
// ===========================================================================

test "R32: inputStateOf initial state has empty text, cursor=0, selection_start=0, active=false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Input/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const state = scene.inputStateOf(id.index);
    try testing.expectEqual(@as(usize, 0), state.text.items.len);
    try testing.expectEqual(@as(u32, 0), state.cursor);
    try testing.expectEqual(@as(u32, 0), state.selection_start);
    try testing.expect(!state.active);
}

test "R32: setInputText stores text; getInputText returns it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Input/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try scene.setInputText(id.index, "hello");
    try testing.expectEqualStrings("hello", scene.getInputText(id.index));
}

test "R32: setInputText places cursor at end of text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Input/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try scene.setInputText(id.index, "hello");
    try testing.expectEqual(@as(u32, 5), scene.inputStateOf(id.index).cursor);
    try testing.expectEqual(@as(u32, 5), scene.inputStateOf(id.index).selection_start);
}

test "R32: setInputText replaces prior text and resets cursor" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Input/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try scene.setInputText(id.index, "first");
    try scene.setInputText(id.index, "second");
    try testing.expectEqualStrings("second", scene.getInputText(id.index));
    try testing.expectEqual(@as(u32, 6), scene.inputStateOf(id.index).cursor);
}

test "R32: no selection initially (selection_start equals cursor)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Input/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try scene.setInputText(id.index, "hello");
    const state = scene.inputStateOf(id.index);
    try testing.expectEqual(state.selection_start, state.cursor);
}

test "R32: selection exists when selection_start differs from cursor" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Input/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try scene.setInputText(id.index, "hello");
    const state = scene.inputStateOf(id.index);
    // Simulate Shift+Left selection: cursor at 5, selection_start at 2
    state.cursor = 5;
    state.selection_start = 2;
    try testing.expect(state.selection_start != state.cursor);
    try testing.expectEqual(@as(u32, 2), state.selection_start);
    try testing.expectEqual(@as(u32, 5), state.cursor);
}

test "R32: setFocus on input sets active=true; clearing focus sets active=false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Input/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try testing.expect(!scene.inputStateOf(id.index).active);
    scene.setFocus(id.index);
    try testing.expect(scene.inputStateOf(id.index).active);
    scene.setFocus(std.math.maxInt(u32));
    try testing.expect(!scene.inputStateOf(id.index).active);
}

test "R32: switching focus from one input to another deactivates the old one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Column(0), Input(1), Input(2)
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Input/>
        \\  <Input/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());
    scene.setFocus(1);
    try testing.expect(scene.inputStateOf(1).active);
    try testing.expect(!scene.inputStateOf(2).active);
    scene.setFocus(2);
    try testing.expect(!scene.inputStateOf(1).active); // deactivated
    try testing.expect(scene.inputStateOf(2).active);
}

// Verify manually: key-event handling (cursor movement, selection, insert, delete)
// lives in app.zig's event loop and is not part of the Scene API.
//   - handleInputKey .right: cursor += 1 (if cursor < text.len)
//   - handleInputKey .left: cursor -= 1 (if cursor > 0)
//   - Shift+Right/Left: selection_start stays, cursor moves
//   - Right without shift with active selection: cursor = max(cursor, selection_start)
//   - Left without shift with active selection: cursor = min(cursor, selection_start)
//   - char event: inserts byte at cursor, increments cursor
//   - Delete key: removes byte at cursor (if cursor < text.len)
//   - Backspace key: removes byte before cursor (if cursor > 0)
//   - Inserting with selection active: replaces [min..max] then inserts at min
//   - Ctrl+A: selection_start = 0, cursor = text.len

// ===========================================================================
// R33 — Dropdown open/close
// ===========================================================================

test "R33: newly created dropdown has is_open=false and selected_idx=0" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Dropdown/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const dd = scene.dropdownStateOf(id.index);
    try testing.expect(!dd.open);
    try testing.expectEqual(@as(u32, 0), dd.selected_idx);
}

test "R33: openDropdown sets is_open=true" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Dropdown/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.openDropdown(id.index);
    try testing.expect(scene.dropdownStateOf(id.index).open);
}

test "R33: closeDropdown sets is_open=false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Dropdown/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.openDropdown(id.index);
    scene.closeDropdown(id.index);
    try testing.expect(!scene.dropdownStateOf(id.index).open);
}

test "R33: toggleDropdown flips open state each call" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Dropdown/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try testing.expect(!scene.dropdownStateOf(id.index).open);
    scene.toggleDropdown(id.index);
    try testing.expect(scene.dropdownStateOf(id.index).open);
    scene.toggleDropdown(id.index);
    try testing.expect(!scene.dropdownStateOf(id.index).open);
}

test "R33: selectDropdownOption updates selected_idx and closes dropdown" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Dropdown/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    var val0: u32 = 10;
    var val1: u32 = 20;
    const options = [_]C.DropdownOption{
        .{ .label = "A", .value = @ptrCast(&val0) },
        .{ .label = "B", .value = @ptrCast(&val1) },
    };
    try scene.setDropdownOptions(id.index, &options);
    scene.openDropdown(id.index);
    try scene.selectDropdownOption(id.index, 1);
    try testing.expectEqual(@as(u32, 1), scene.dropdownStateOf(id.index).selected_idx);
    try testing.expect(!scene.dropdownStateOf(id.index).open); // closed after select
}

test "R33: getDropdownValue returns value at selected_idx" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Dropdown/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    var val0: u32 = 42;
    var val1: u32 = 99;
    const options = [_]C.DropdownOption{
        .{ .label = "first", .value = @ptrCast(&val0) },
        .{ .label = "second", .value = @ptrCast(&val1) },
    };
    try scene.setDropdownOptions(id.index, &options);
    // Default selected_idx = 0 → value is 42
    const v0: *u32 = @ptrCast(@alignCast(scene.getDropdownValue(id.index)));
    try testing.expectEqual(@as(u32, 42), v0.*);
    // Select index 1 → value is 99
    try scene.selectDropdownOption(id.index, 1);
    const v1: *u32 = @ptrCast(@alignCast(scene.getDropdownValue(id.index)));
    try testing.expectEqual(@as(u32, 99), v1.*);
}

test "R33: setFocus on a different element closes the previously open dropdown" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Column(0), Dropdown(1), Button(2)
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Dropdown/>
        \\  <Button text="x"/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, testTokens());
    // Focus the dropdown first, then open it.
    scene.setFocus(1);
    scene.openDropdown(1);
    try testing.expect(scene.dropdownStateOf(1).open);
    // Moving focus away from a focused dropdown closes it.
    scene.setFocus(2);
    try testing.expect(!scene.dropdownStateOf(1).open);
}

// ===========================================================================
// R34 — Checkbox widget
// ===========================================================================

test "R34: newly created checkbox has checked=false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Checkbox/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try testing.expect(!scene.isCheckboxChecked(id.index));
}

test "R34: setCheckboxChecked(true) and isCheckboxChecked round-trip" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Checkbox/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.setCheckboxChecked(id.index, true);
    try testing.expect(scene.isCheckboxChecked(id.index));
}

test "R34: setCheckboxChecked(false) clears checked state" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Checkbox/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.setCheckboxChecked(id.index, true);
    scene.setCheckboxChecked(id.index, false);
    try testing.expect(!scene.isCheckboxChecked(id.index));
}

test "R34: toggle via checkboxStateOf pointer flips checked twice returning to original" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Checkbox/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const state = scene.checkboxStateOf(id.index);
    state.checked = !state.checked; // first toggle → true
    try testing.expect(scene.isCheckboxChecked(id.index));
    state.checked = !state.checked; // second toggle → false
    try testing.expect(!scene.isCheckboxChecked(id.index));
}

test "R34: setCheckboxChecked marks element dirty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Checkbox/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.elements.clearDirty();
    try testing.expect(!scene.elements.dirty.isSet(id.index));
    scene.setCheckboxChecked(id.index, true);
    try testing.expect(scene.elements.dirty.isSet(id.index));
}

test "R34: checkbox is included in focusable_indices (Tab order)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Checkbox/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try testing.expect(scene.isFocusable(id.index));
}

test "R34: checkbox initial state has hovered=false, pressed=false, disabled=false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Checkbox/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const state = scene.checkboxStateOf(id.index);
    try testing.expect(!state.hovered);
    try testing.expect(!state.pressed);
    try testing.expect(!state.disabled);
}

// ===========================================================================
// R35 — Scroll container
// ===========================================================================

test "R35: newly created scrollview has scroll_y=0 and scroll_x=0" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<ScrollView/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const off = scene.getScrollOffset(id.index);
    try testing.expectEqual(@as(f32, 0), off.y);
    try testing.expectEqual(@as(f32, 0), off.x);
}

test "R35: setScrollOffset and getScrollOffset round-trip both axes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<ScrollView/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.setScrollOffset(id.index, 50.0, 25.0);
    const off = scene.getScrollOffset(id.index);
    try testing.expectEqual(@as(f32, 50.0), off.y);
    try testing.expectEqual(@as(f32, 25.0), off.x);
}

test "R35: scrollBy(50) equivalent: offset increases by 50 from zero" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<ScrollView/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const before_y = scene.getScrollOffset(id.index).y;
    scene.setScrollOffset(id.index, before_y + 50.0, 0);
    try testing.expectEqual(@as(f32, 50.0), scene.getScrollOffset(id.index).y);
}

test "R35: scrollStateOf exposes all fields with correct initial values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<ScrollView/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const ss = scene.scrollStateOf(id.index);
    try testing.expectEqual(@as(f32, 0), ss.scroll_y);
    try testing.expectEqual(@as(f32, 0), ss.scroll_x);
    try testing.expectEqual(@as(f32, 0), ss.content_height);
    try testing.expectEqual(@as(f32, 0), ss.content_width);
    try testing.expect(!ss.dragging_v_scrollbar);
    try testing.expect(!ss.dragging_h_scrollbar);
}

test "R35: setScrollOffset marks element dirty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<ScrollView/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.elements.clearDirty();
    try testing.expect(!scene.elements.dirty.isSet(id.index));
    scene.setScrollOffset(id.index, 10.0, 0.0);
    try testing.expect(scene.elements.dirty.isSet(id.index));
}

test "R35: multiple scroll operations accumulate correctly" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<ScrollView/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    // Simulate three app-layer scrollBy(50) calls
    var y: f32 = 0;
    y += 50;
    scene.setScrollOffset(id.index, y, 0);
    y += 50;
    scene.setScrollOffset(id.index, y, 0);
    y += 50;
    scene.setScrollOffset(id.index, y, 0);
    try testing.expectEqual(@as(f32, 150.0), scene.getScrollOffset(id.index).y);
}

test "R35: scrollview defaultLayoutFor has display=block and overflow=hidden" {
    const layout = C.defaultLayoutFor(.scrollview);
    try testing.expectEqual(store_mod.Display.block, layout.display);
    try testing.expectEqual(store_mod.Overflow.hidden, layout.overflow);
}

// Note: Clamping (scroll offset bounded by [0, content_height - container_height])
// is computed and applied in app.zig's wheel-scroll handler, not in Scene.setScrollOffset.
// Verify manually: attempting to scroll below 0 or past max_scroll via the app
// should clamp to the valid range.

// ===========================================================================
// R50 — Inline style:* attributes applied via instantiate
//
// NOTE: The parser's isNameChar does not allow ':' in attribute names, so
// style:* NodeDescs cannot be built via markup_mod.parse. We construct
// NodeDesc structs directly to exercise the instantiateNode code path.
// ===========================================================================

test "R50: style:background sets ComputedStyle.background from hex color" {
    // Construct NodeDesc directly — parser cannot handle ':' in attr names.
    const attrs = [_]markup_mod.Attr{
        .{ .name = "style:background", .value = .{ .literal = "#FF0000" } },
        .{ .name = "text",             .value = .{ .literal = "x" } },
    };
    const desc = markup_mod.NodeDesc{
        .tag = "Text", .classes = "", .attrs = &attrs, .children = &.{},
    };
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const s = scene.styleOf(id);
    try testing.expectEqual(@as(u8, 255), s.background.r);
    try testing.expectEqual(@as(u8, 0),   s.background.g);
    try testing.expectEqual(@as(u8, 0),   s.background.b);
    try testing.expectEqual(@as(u8, 255), s.background.a);
}

test "R50: style:opacity sets ComputedStyle.opacity" {
    const attrs = [_]markup_mod.Attr{
        .{ .name = "style:opacity", .value = .{ .literal = "0.5" } },
        .{ .name = "text",          .value = .{ .literal = "x" } },
    };
    const desc = markup_mod.NodeDesc{
        .tag = "Text", .classes = "", .attrs = &attrs, .children = &.{},
    };
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const s = scene.styleOf(id);
    try testing.expectApproxEqAbs(@as(f32, 0.5), s.opacity, 0.001);
}

test "R50: unknown style:foo attribute does not crash and style is unchanged" {
    const attrs = [_]markup_mod.Attr{
        .{ .name = "style:foo", .value = .{ .literal = "bar" } },
        .{ .name = "text",      .value = .{ .literal = "x" } },
    };
    const desc = markup_mod.NodeDesc{
        .tag = "Text", .classes = "", .attrs = &attrs, .children = &.{},
    };
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    // Must not error; style is unchanged (unknown prop silently ignored)
    const id = try scene.instantiate(desc, testTokens());
    _ = id;
}

test "R50: malformed style:radius retains class-derived value" {
    // rounded-md sets a class-derived radius; style:radius="abc" is silently ignored
    const attrs = [_]markup_mod.Attr{
        .{ .name = "style:radius", .value = .{ .literal = "abc" } },
        .{ .name = "text",         .value = .{ .literal = "x" } },
    };
    const desc = markup_mod.NodeDesc{
        .tag = "Text", .classes = "rounded-md", .attrs = &attrs, .children = &.{},
    };
    const t = testTokens();
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, t);
    // The class-derived radius_md value should still be there (malformed ignored)
    try testing.expectApproxEqAbs(t.radius_md, scene.styleOf(id).radius, 0.001);
}

test "R50: inline style:background overrides class-derived background" {
    // bg-canvas sets a theme-derived background; style:background="#AABBCC" must win
    const attrs = [_]markup_mod.Attr{
        .{ .name = "style:background", .value = .{ .literal = "#AABBCC" } },
        .{ .name = "text",             .value = .{ .literal = "x" } },
    };
    const desc = markup_mod.NodeDesc{
        .tag = "Text", .classes = "bg-canvas", .attrs = &attrs, .children = &.{},
    };
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const s = scene.styleOf(id);
    try testing.expectEqual(@as(u8, 0xAA), s.background.r);
    try testing.expectEqual(@as(u8, 0xBB), s.background.g);
    try testing.expectEqual(@as(u8, 0xCC), s.background.b);
    try testing.expectEqual(@as(u8, 255),  s.background.a);
}

test "R50: style:opacity clamped to 0.0-1.0 range (value above 1)" {
    const attrs = [_]markup_mod.Attr{
        .{ .name = "style:opacity", .value = .{ .literal = "2.0" } },
        .{ .name = "text",          .value = .{ .literal = "x" } },
    };
    const desc = markup_mod.NodeDesc{
        .tag = "Text", .classes = "", .attrs = &attrs, .children = &.{},
    };
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    // applyInlineStyle clamps opacity to [0.0, 1.0]
    try testing.expectApproxEqAbs(@as(f32, 1.0), scene.styleOf(id).opacity, 0.001);
}

test "R50: style:background with bind value is silently skipped" {
    // A bind value in a style:* attribute must be silently ignored (non-goal per R50)
    const attrs = [_]markup_mod.Attr{
        .{ .name = "style:background", .value = .{ .bind = "user.color" } },
        .{ .name = "text",             .value = .{ .literal = "x" } },
    };
    const desc = markup_mod.NodeDesc{
        .tag = "Text", .classes = "bg-canvas", .attrs = &attrs, .children = &.{},
    };
    const t = testTokens();
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, t);
    // Background from bg-canvas class should survive (bind not evaluated)
    const s = scene.styleOf(id);
    try testing.expectEqual(t.bg_canvas.r, s.background.r);
    try testing.expectEqual(t.bg_canvas.g, s.background.g);
    try testing.expectEqual(t.bg_canvas.b, s.background.b);
}

// ===========================================================================
// R52 — Conditional rendering: isHidden, setHidden, if= attribute
// ===========================================================================

test "R52: if=false literal starts element hidden" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(),
        \\<Text if="false" text="x"/>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try testing.expect(scene.isHidden(id.index));
}

test "R52: if=true literal starts element visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(),
        \\<Text if="true" text="x"/>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try testing.expect(!scene.isHidden(id.index));
}

test "R52: setHidden true sets display to none" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    // Initially not hidden
    try testing.expect(!scene.isHidden(id.index));
    scene.setHidden(id.index, true);
    try testing.expect(scene.isHidden(id.index));
    // display should be .none
    try testing.expectEqual(store_mod.Display.none, scene.elements.layout.items[id.index].display);
}

test "R52: setHidden false restores original display value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Row text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    // Row has display=.flex by default
    const orig_display = scene.elements.layout.items[id.index].display;
    try testing.expectEqual(store_mod.Display.flex, orig_display);

    scene.setHidden(id.index, true);
    try testing.expectEqual(store_mod.Display.none, scene.elements.layout.items[id.index].display);

    scene.setHidden(id.index, false);
    try testing.expect(!scene.isHidden(id.index));
    // display is restored
    try testing.expectEqual(orig_display, scene.elements.layout.items[id.index].display);
}

test "R52: setHidden marks element dirty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.elements.clearDirty();
    try testing.expect(!scene.elements.dirty.isSet(id.index));

    scene.setHidden(id.index, true);
    try testing.expect(scene.elements.dirty.isSet(id.index));
}

test "R52: setHidden false also marks element dirty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    scene.setHidden(id.index, true);
    scene.elements.clearDirty();
    try testing.expect(!scene.elements.dirty.isSet(id.index));

    scene.setHidden(id.index, false);
    try testing.expect(scene.elements.dirty.isSet(id.index));
}

test "R52: setHidden no-op when state already matches" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    // Already not hidden; calling setHidden(false) again should be a no-op (no panic)
    scene.elements.clearDirty();
    scene.setHidden(id.index, false);
    // No dirty set because state didn't change
    try testing.expect(!scene.elements.dirty.isSet(id.index));
}

// ===========================================================================
// R53 — removeChildren and instantiateUnder
// ===========================================================================

test "R53: removeChildren removes all direct children and their subtrees" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Text text="a"/>
        \\  <Text text="b"/>
        \\  <Row><Text text="c"/></Row>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const root_id = try scene.instantiate(desc, testTokens());
    // Column(0) + Text(1) + Text(2) + Row(3) + Text(4) = 5 live
    try testing.expectEqual(@as(u32, 5), scene.count());

    scene.removeChildren(root_id.index);

    // All children removed; only the Column root remains
    try testing.expectEqual(@as(u32, 1), scene.count());
    // Column itself is still valid
    try testing.expect(scene.elements.isValid(root_id));
    // No children left
    var it = scene.elements.childrenOf(root_id);
    try testing.expect(it.next() == null);
}

test "R53: instantiateUnder appends new element as child of given parent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Create a container first
    const container_desc = try markup_mod.parse(arena.allocator(), "<Column/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const container_id = try scene.instantiate(container_desc, testTokens());
    try testing.expectEqual(@as(u32, 1), scene.count());

    // Instantiate a child under it
    const child_desc = try markup_mod.parse(arena.allocator(), "<Text text=\"item\"/>");
    const child_id = try scene.instantiateUnder(container_id, child_desc, testTokens());

    try testing.expectEqual(@as(u32, 2), scene.count());
    // Child's parent is the container
    const parent = scene.elements.parentOf(child_id).?;
    try testing.expectEqual(container_id.index, parent.index);
    // Container has exactly one child
    var it = scene.elements.childrenOf(container_id);
    const first = it.next().?;
    try testing.expect(it.next() == null);
    try testing.expectEqual(child_id.index, first.index);
}

test "R53: removeChildren followed by instantiateUnder produces correct child count" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Text text="old1"/>
        \\  <Text text="old2"/>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const root_id = try scene.instantiate(desc, testTokens());
    try testing.expectEqual(@as(u32, 3), scene.count());

    // Remove children
    scene.removeChildren(root_id.index);
    try testing.expectEqual(@as(u32, 1), scene.count());

    // Add new children
    const item_desc = try markup_mod.parse(arena.allocator(), "<Text text=\"new\"/>");
    _ = try scene.instantiateUnder(root_id, item_desc, testTokens());
    _ = try scene.instantiateUnder(root_id, item_desc, testTokens());
    _ = try scene.instantiateUnder(root_id, item_desc, testTokens());

    try testing.expectEqual(@as(u32, 4), scene.count());
    // Exactly 3 children under root
    var it = scene.elements.childrenOf(root_id);
    var count: u32 = 0;
    while (it.next()) |_| count += 1;
    try testing.expectEqual(@as(u32, 3), count);
}
