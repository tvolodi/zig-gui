//! home.zig — Home screen for the Showcase Demo (Screen 1).

const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const HomeCtx = struct {
    global: *shared.GlobalState,
};

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *HomeCtx = @ptrCast(@alignCast(ctx.?));

    // Title
    const title_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "zig-gui Showcase" } }};
    const title = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold", .attrs = &title_attrs };

    // Subtitle
    const sub_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "A native GUI framework — GPU-rendered, Zig-native, web-familiar syntax" } }};
    const sub = NodeDesc{ .tag = "Text", .classes = "text-muted", .attrs = &sub_attrs };

    const sep = NodeDesc{ .tag = "Separator", .classes = "my-2" };

    // Card 1 — Fast
    const fast_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Fast" } }};
    const fast_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &fast_h_attrs };
    const fast_b_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Vulkan-backed GPU rendering. No intermediate DOM. One flat draw-command list per frame." } }};
    const fast_b = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &fast_b_attrs };
    const fast_children = [2]NodeDesc{ fast_h, fast_b };
    const fast_card = NodeDesc{ .tag = "Card", .classes = "p-4 gap-2 flex-1", .children = &fast_children };

    // Card 2 — Small
    const small_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Small" } }};
    const small_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &small_h_attrs };
    const small_b_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Zero runtime deps beyond GLFW + Vulkan. Ships as a single binary." } }};
    const small_b = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &small_b_attrs };
    const small_children = [2]NodeDesc{ small_h, small_b };
    const small_card = NodeDesc{ .tag = "Card", .classes = "p-4 gap-2 flex-1", .children = &small_children };

    // Card 3 — Familiar
    const fam_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Familiar" } }};
    const fam_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &fam_h_attrs };
    const fam_b_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "HTML-like markup. Tailwind-subset classes. Reactive signals." } }};
    const fam_b = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &fam_b_attrs };
    const fam_children = [2]NodeDesc{ fam_h, fam_b };
    const fam_card = NodeDesc{ .tag = "Card", .classes = "p-4 gap-2 flex-1", .children = &fam_children };

    const cards_children = [3]NodeDesc{ fast_card, small_card, fam_card };
    const cards = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &cards_children };

    // Footer
    const footer_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Open a screen from the sidebar to explore each feature." } }};
    const footer = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &footer_attrs };

    const content_children = [5]NodeDesc{ title, sub, sep, cards, footer };
    const content = NodeDesc{ .tag = "Column", .classes = "flex-1 gap-4 p-6", .children = &content_children };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), content };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 2); // 2 = Home button
}
