//! aiqadam.zig — AI-Qadam visual analog (Screen 14 — sidebar index 15).
//!
//! Iterative v1 build of the homepage at https://aiqadam.org. Mirrors the existing
//! showcase layout pattern (sidebar + scrollable content) — the AI-Qadam screen
//! reuses the shared sidebar like every other showcase screen so the navigation
//! infrastructure keeps working. The content panel is rendered with the dark
//! palette and the additive `tokens.accent_teal` token (Palette.teal_400 = 0x2DD4BF)
//! for the brand accent (logo, "Sign in" button, "Browse events" CTA, "Send me a
//! confirmation" button).
//!
//! See `docs/requirements/RAI_aiqadam_visual_analog.md` for the canonical spec.

const std = @import("std");
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const AiQadamCtx = struct {
    global: *shared.GlobalState,
};

// ---------------------------------------------------------------------------
// Static attribute storage (program lifetime — pointer stability).
// ---------------------------------------------------------------------------
var _logo_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "\xe2\x9c\xa8 AI Qadam" } }};

var _nav_events_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Events" } }};
var _nav_lb_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Leaderboard" } }};

var _pill_country_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "\xf0\x9f\x87\xba\xf0\x9f\x87\xbf Uzbekistan" } }};
var _pill_lang_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "English" } }};
var _btn_register_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Register" } }};
var _btn_signin_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Sign in" } }};

var _eyebrow_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "AI QADAM \xe2\x80\x94 COMMUNITY PLATFORM" } }};
var _heading_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "AI engineers, building together across Central Asia." } }};
var _subtitle_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Multi-tenant community platform for AI engineers across Central Asia." } }};
var _cta_browse_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Browse events" } }};
var _cta_tg_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Join on Telegram" } }};

var _stat1_eyebrow_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "COUNTRIES SERVED" } }};
var _stat1_value_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "3" } }};
var _stat2_eyebrow_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "OPERATOR TENANTS" } }};
var _stat2_value_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "uz \xc2\xb7 kz \xc2\xb7 tj" } }};
var _stat3_eyebrow_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "CHANNEL" } }};
var _stat3_value_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Open community" } }};

var _nl_heading_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Get events in your city" } }};
var _nl_sub_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Monthly digest. No spam. Unsubscribe in one click." } }};
var _email_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Email" } }};
var _email_ph_attrs = [1]Attr{.{ .name = "placeholder", .value = .{ .literal = "you@domain.com" } }};
var _city_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "City (optional)" } }};
var _city_ph_attrs = [1]Attr{.{ .name = "placeholder", .value = .{ .literal = "Tashkent, Almaty, Dushanbe\xe2\x80\xa6" } }};
var _topics_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Topics you care about (optional)" } }};
var _submit_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Send me a confirmation" } }};

var _topics = [_][]const u8{
    "AI/ML", "LLMs", "fintech", "robotics", "devtools", "infra", "data",
    "computer-vision", "nlp", "mlops", "hands-on-builder",
};

var _footer_brand_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "AI Qadam" } }};
var _footer_tag_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Community-as-platform for Central Asian AI engineers." } }};
var _footer_countries_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "3 countries served" } }};
var _follow_eyebrow_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "FOLLOW" } }};
var _follow_link_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Telegram \xe2\x86\x97" } }};
var _contact_eyebrow_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "CONTACT" } }};
var _contact_partners_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Partners" } }};
var _contact_press_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Press" } }};
var _copyright_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "\xc2\xa9 2026 AI Qadam \xc2\xb7 Community-as-platform for Central Asian AI engineers" } }};

// ---------------------------------------------------------------------------
// build
// ---------------------------------------------------------------------------

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *AiQadamCtx = @ptrCast(@alignCast(ctx.?));

    // -----------------------------------------------------------------------
    // Header — sticky row with logo, nav, pills, buttons
    // -----------------------------------------------------------------------
    const logo = NodeDesc{ .tag = "Text", .classes = "text-base font-bold", .attrs = &_logo_attrs };
    const nav_events = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &_nav_events_attrs };
    const nav_lb = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &_nav_lb_attrs };
    const nav_children = [2]NodeDesc{ nav_events, nav_lb };
    const nav = NodeDesc{ .tag = "Row", .classes = "gap-4 items-center", .children = &nav_children };

    const pill_country = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-7 text-xs border items-center", .attrs = &_pill_country_attrs };
    const pill_lang = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-7 text-xs border items-center", .attrs = &_pill_lang_attrs };
    const btn_register = NodeDesc{ .tag = "Button", .classes = "border bg-canvas", .attrs = &_btn_register_attrs };
    const btn_signin = NodeDesc{ .tag = "Button", .classes = "", .attrs = &_btn_signin_attrs };
    const right_children = [4]NodeDesc{ pill_country, pill_lang, btn_register, btn_signin };
    const right = NodeDesc{ .tag = "Row", .classes = "gap-2 items-center", .children = &right_children };

    const header_left = [2]NodeDesc{ logo, nav };
    const header_children = [2]NodeDesc{ header_left[0], header_left[1] };
    const header_row_left = NodeDesc{ .tag = "Row", .classes = "gap-6 items-center", .children = &header_children };
    const header_full_children = [2]NodeDesc{ header_row_left, right };
    const header_full = NodeDesc{ .tag = "Row", .classes = "w-full justify-between items-center p-4 border", .children = &header_full_children };

    // -----------------------------------------------------------------------
    // Hero — centered, eyebrow + heading + subtitle + 2 CTAs
    // -----------------------------------------------------------------------
    const eyebrow = NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_eyebrow_attrs };
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold", .attrs = &_heading_attrs };
    const subtitle = NodeDesc{ .tag = "Text", .classes = "text-base", .attrs = &_subtitle_attrs };
    const cta_browse = NodeDesc{ .tag = "Button", .classes = "", .attrs = &_cta_browse_attrs };
    const cta_tg = NodeDesc{ .tag = "Button", .classes = "border bg-canvas", .attrs = &_cta_tg_attrs };
    const cta_children = [2]NodeDesc{ cta_browse, cta_tg };
    const cta_row = NodeDesc{ .tag = "Row", .classes = "gap-3 justify-center", .children = &cta_children };

    const hero_contents_children = [4]NodeDesc{ eyebrow, heading, subtitle, cta_row };
    const hero_contents = NodeDesc{ .tag = "Column", .classes = "gap-4 items-center max-w-2xl", .children = &hero_contents_children };
    const hero_center = NodeDesc{ .tag = "Column", .classes = "w-full items-center p-10", .children = &[1]NodeDesc{hero_contents} };

    // -----------------------------------------------------------------------
    // Stats row — 3 equal columns
    // -----------------------------------------------------------------------
    const stat1_eyebrow = NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_stat1_eyebrow_attrs };
    const stat1_value = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold", .attrs = &_stat1_value_attrs };
    const stat1_inner_children = [2]NodeDesc{ stat1_eyebrow, stat1_value };
    const stat1_inner = NodeDesc{ .tag = "Column", .classes = "gap-2 items-center", .children = &stat1_inner_children };
    const stat1 = NodeDesc{ .tag = "Card", .classes = "p-4 gap-1 flex-1 items-center", .children = &[1]NodeDesc{stat1_inner} };

    const stat2_eyebrow = NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_stat2_eyebrow_attrs };
    const stat2_value = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold", .attrs = &_stat2_value_attrs };
    const stat2_inner_children = [2]NodeDesc{ stat2_eyebrow, stat2_value };
    const stat2_inner = NodeDesc{ .tag = "Column", .classes = "gap-2 items-center", .children = &stat2_inner_children };
    const stat2 = NodeDesc{ .tag = "Card", .classes = "p-4 gap-1 flex-1 items-center", .children = &[1]NodeDesc{stat2_inner} };

    const stat3_eyebrow = NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_stat3_eyebrow_attrs };
    const stat3_value = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold", .attrs = &_stat3_value_attrs };
    const stat3_inner_children = [2]NodeDesc{ stat3_eyebrow, stat3_value };
    const stat3_inner = NodeDesc{ .tag = "Column", .classes = "gap-2 items-center", .children = &stat3_inner_children };
    const stat3 = NodeDesc{ .tag = "Card", .classes = "p-4 gap-1 flex-1 items-center", .children = &[1]NodeDesc{stat3_inner} };

    const stats_row_children = [3]NodeDesc{ stat1, stat2, stat3 };
    const stats_row = NodeDesc{ .tag = "Row", .classes = "gap-4 w-full p-4", .children = &stats_row_children };

    // -----------------------------------------------------------------------
    // Newsletter card — full-width card with form
    // -----------------------------------------------------------------------
    const nl_heading = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &_nl_heading_attrs };
    const nl_sub = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &_nl_sub_attrs };

    // Email field
    const email_lbl = NodeDesc{ .tag = "Text", .classes = "text-xs font-bold", .attrs = &_email_lbl_attrs };
    const email_in = NodeDesc{ .tag = "Input", .classes = "w-full", .attrs = &_email_ph_attrs };
    const email_field_children = [2]NodeDesc{ email_lbl, email_in };
    const email_field = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &email_field_children };

    // City field
    const city_lbl = NodeDesc{ .tag = "Text", .classes = "text-xs font-bold", .attrs = &_city_lbl_attrs };
    const city_in = NodeDesc{ .tag = "Input", .classes = "w-full", .attrs = &_city_ph_attrs };
    const city_field_children = [2]NodeDesc{ city_lbl, city_in };
    const city_field = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &city_field_children };

    // Topics row — wrapped row of small pill cards
    const topics_lbl = NodeDesc{ .tag = "Text", .classes = "text-xs font-bold", .attrs = &_topics_lbl_attrs };

    // Module-level static storage for each pill's Attr array (pointer stable).
    var _t_attrs0 = [1]Attr{.{ .name = "text", .value = .{ .literal = "AI/ML" } }};
    var _t_attrs1 = [1]Attr{.{ .name = "text", .value = .{ .literal = "LLMs" } }};
    var _t_attrs2 = [1]Attr{.{ .name = "text", .value = .{ .literal = "fintech" } }};
    var _t_attrs3 = [1]Attr{.{ .name = "text", .value = .{ .literal = "robotics" } }};
    var _t_attrs4 = [1]Attr{.{ .name = "text", .value = .{ .literal = "devtools" } }};
    var _t_attrs5 = [1]Attr{.{ .name = "text", .value = .{ .literal = "infra" } }};
    var _t_attrs6 = [1]Attr{.{ .name = "text", .value = .{ .literal = "data" } }};
    var _t_attrs7 = [1]Attr{.{ .name = "text", .value = .{ .literal = "computer-vision" } }};
    var _t_attrs8 = [1]Attr{.{ .name = "text", .value = .{ .literal = "nlp" } }};
    var _t_attrs9 = [1]Attr{.{ .name = "text", .value = .{ .literal = "mlops" } }};
    var _t_attrs10 = [1]Attr{.{ .name = "text", .value = .{ .literal = "hands-on-builder" } }};

    // Trick: `_topics` is a const slice of *literal* strings; we need *Attr* arrays.
    // The literals are stored in the per-pill `_t_attrs*` arrays — the `text` literal
    // of each one must match the topic exactly so post-instantiation styling can
    // identify them by text content if needed.
    const pill0 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs0 };
    const pill1 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs1 };
    const pill2 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs2 };
    const pill3 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs3 };
    const pill4 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs4 };
    const pill5 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs5 };
    const pill6 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs6 };
    const pill7 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs7 };
    const pill8 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs8 };
    const pill9 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs9 };
    const pill10 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-3 h-6 text-xs border", .attrs = &_t_attrs10 };
    const pills_children = [11]NodeDesc{ pill0, pill1, pill2, pill3, pill4, pill5, pill6, pill7, pill8, pill9, pill10 };
    const pills_row = NodeDesc{ .tag = "Row", .classes = "gap-2 flex-wrap", .children = &pills_children };

    // Submit button (filled teal — wired via post-instantiation background override)
    const submit_btn = NodeDesc{ .tag = "Button", .classes = "", .attrs = &_submit_attrs };

    const newsletter_inner_children = [7]NodeDesc{
        nl_heading, nl_sub, topics_lbl, pills_row, email_field, city_field, submit_btn,
    };
    // The 7 logical items above are placed in order — the form layout is:
    //   heading, sub, topics_lbl, pills_row, email_field, city_field, submit_btn
    const newsletter_card = NodeDesc{ .tag = "Card", .classes = "p-6 gap-4 w-full", .children = &newsletter_inner_children };

    // -----------------------------------------------------------------------
    // Footer — 3-column grid + bottom copyright strip
    // -----------------------------------------------------------------------
    const footer_brand = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold", .attrs = &_footer_brand_attrs };
    const footer_tag = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &_footer_tag_attrs };
    const footer_countries = NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_footer_countries_attrs };
    const brand_col_children = [3]NodeDesc{ footer_brand, footer_tag, footer_countries };
    const brand_col = NodeDesc{ .tag = "Column", .classes = "gap-2 flex-1", .children = &brand_col_children };

    const follow_eyebrow = NodeDesc{ .tag = "Text", .classes = "text-xs font-bold", .attrs = &_follow_eyebrow_attrs };
    const follow_link = NodeDesc{ .tag = "Button", .classes = "text-sm", .attrs = &_follow_link_attrs };
    const follow_col_children = [2]NodeDesc{ follow_eyebrow, follow_link };
    const follow_col = NodeDesc{ .tag = "Column", .classes = "gap-2 flex-1", .children = &follow_col_children };

    const contact_eyebrow = NodeDesc{ .tag = "Text", .classes = "text-xs font-bold", .attrs = &_contact_eyebrow_attrs };
    const contact_partners = NodeDesc{ .tag = "Button", .classes = "text-sm", .attrs = &_contact_partners_attrs };
    const contact_press = NodeDesc{ .tag = "Button", .classes = "text-sm", .attrs = &_contact_press_attrs };
    const contact_col_children = [3]NodeDesc{ contact_eyebrow, contact_partners, contact_press };
    const contact_col = NodeDesc{ .tag = "Column", .classes = "gap-2 flex-1", .children = &contact_col_children };

    const footer_cols_children = [3]NodeDesc{ brand_col, follow_col, contact_col };
    const footer_cols = NodeDesc{ .tag = "Row", .classes = "gap-6 w-full p-4", .children = &footer_cols_children };

    const copyright = NodeDesc{ .tag = "Text", .classes = "text-xs w-full p-4 border", .attrs = &_copyright_attrs };

    const footer_children = [2]NodeDesc{ footer_cols, copyright };
    const footer = NodeDesc{ .tag = "Column", .classes = "gap-2 w-full p-4", .children = &footer_children };

    // -----------------------------------------------------------------------
    // Master content column: header + hero + stats + newsletter + footer
    // -----------------------------------------------------------------------
    const content_children = [5]NodeDesc{ header_full, hero_center, stats_row, newsletter_card, footer };
    const content = NodeDesc{ .tag = "Column", .classes = "flex-1 gap-4", .children = &content_children };
    const scroll = NodeDesc{ .tag = "ScrollView", .classes = "flex-1", .children = &[1]NodeDesc{content} };

    // -----------------------------------------------------------------------
    // Root layout — sidebar + scrollable content
    // -----------------------------------------------------------------------
    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), scroll };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 15); // 15 = AI-Qadam button (sidebar index 14 → element index 15)

    // -----------------------------------------------------------------------
    // Post-instantiation styling:
    //   1. Brand teal color on the logo, "Sign in", "Browse events", and
    //      "Send me a confirmation" buttons (uses tokens.accent_teal).
    //   2. Header "Sign in" and "Browse events" buttons get the teal background.
    //   3. Sign-in, Browse-events, and Send-confirmation buttons get white
    //      text (accent_text) for contrast on teal.
    //   4. Country / language pill text color set to muted (default text).
    //   5. "Sign in" / "Register" buttons: registered button has bg-canvas
    //      and a border (already in classes); Sign in needs the teal background
    //      injected via style override.
    // -----------------------------------------------------------------------
    var i: u32 = 0;
    while (i < scene._kind.items.len) : (i += 1) {
        const txt = scene.textOf(.{ .index = i, .gen = 0 });
        if (txt == null) continue;

        // AI Qadam logo — teal mono accent (text only — we have no font_mono
        // class, so we tint the text. The visual feel is approximated by the
        // teal color + bold + small size.)
        if (std.mem.eql(u8, txt.?, "AI Qadam")) {
            // Two AI Qadam text nodes exist: the header logo (small) and the
            // footer brand (large). Both should be teal.
            scene._style.items[i].text_color = tokens.accent_teal;
        }

        // Filled teal CTAs
        if (std.mem.eql(u8, txt.?, "Sign in") or
            std.mem.eql(u8, txt.?, "Browse events") or
            std.mem.eql(u8, txt.?, "Send me a confirmation"))
        {
            if (scene.kindOfIdx(i) == .button) {
                scene._style.items[i].background = tokens.accent_teal;
                scene._style.items[i].text_color = tokens.accent_text;
            }
        }

        // Header eyebrow letter-spacing simulation: the eyebrow text is rendered
        // slightly smaller with extra horizontal "breathing room" via
        // reduced font size and centered position. We just keep text-xs; the
        // visual approximation is acceptable for v1.
        // (No letter_spacing field exists in ComputedStyle.)
        if (std.mem.eql(u8, txt.?, "AI QADAM \xe2\x80\x94 COMMUNITY PLATFORM")) {
            // Cast to uppercase visually via text-xs; no letter-spacing class
            // available in v1.
            scene._style.items[i].font_size = tokens.text_xs;
        }

        // Register button border is already in classes; nothing to override.
        // "Join on Telegram" stays outlined (default Button class with .border
        // .bg-canvas — already set in classes).
        // Pills (country / language): text color stays default (text_body) so
        // they read against the surface; no override needed.

        // 3 countries served text — small, muted already (text-xs).
        // Footer copyright row gets a top border (Separator already adds it).
    }

    // Add a separator above the footer copyright — the Copyright text already
    // has a class `border` which uses border_default; that gives the top
    // divider line.
}
