//! forms.zig — Form widgets showcase screen (Screen 3).

const std = @import("std");
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;
const DropdownOption = mod07.DropdownOption;
const CallbackFn = mod07.CallbackFn;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const FormsCtx = struct {
    global: *shared.GlobalState,
};

// ---------------------------------------------------------------------------
// Persistent option storage (program lifetime)
// ---------------------------------------------------------------------------

var _country_values: [7]u8 = .{ 0, 1, 2, 3, 4, 5, 6 };
var _country_opts: [7]DropdownOption = .{
    .{ .label = "Australia",      .value = &_country_values[0] },
    .{ .label = "Brazil",         .value = &_country_values[1] },
    .{ .label = "Canada",         .value = &_country_values[2] },
    .{ .label = "Germany",        .value = &_country_values[3] },
    .{ .label = "Japan",          .value = &_country_values[4] },
    .{ .label = "United Kingdom", .value = &_country_values[5] },
    .{ .label = "United States",  .value = &_country_values[6] },
};

// ---------------------------------------------------------------------------
// Submit callback — fires a success toast
// ---------------------------------------------------------------------------

pub const SubmitCb = struct {
    global: *shared.GlobalState,

    pub fn onClick(ptr: *anyopaque) void {
        const self: *SubmitCb = @ptrCast(@alignCast(ptr));
        if (self.global.toasts) |tm| {
            const now = if (self.global.app_inner) |ai| ai.frame_time_ms else 0;
            tm.show("Form submitted!", .success, 3000, now);
        }
    }
};

// Module-level storage so callback pointer stays valid
var _submit_cb: SubmitCb = undefined;

// ---------------------------------------------------------------------------
// Slider readout — per-frame tick updates vol_val text from slider state.
// ---------------------------------------------------------------------------

var _slider_idx: u32 = 0;
var _vol_val_idx: u32 = 0;
var _vol_buf: [8]u8 = undefined;

// ---------------------------------------------------------------------------
// Summary panel state — module-level indices and buffers (no heap allocs).
// ---------------------------------------------------------------------------

// Widget indices for the 6 summary Text elements (set during build).
var _sum_name_idx: u32 = 0;
var _sum_email_idx: u32 = 0;
var _sum_country_idx: u32 = 0;
var _sum_newsletter_idx: u32 = 0;
var _sum_contact_idx: u32 = 0;
var _sum_volume_idx: u32 = 0;

// Source widget indices read by tick() to populate the summary.
var _name_input_idx: u32 = 0;
var _email_input_idx: u32 = 0;
var _country_dd_idx: u32 = 0;
var _checkbox_idx: u32 = 0;
// Radio indices (Email=first, Phone=second, Post=third in "contact" group).
var _radio_email_idx: u32 = 0;
var _radio_phone_idx: u32 = 0;
var _radio_post_idx: u32 = 0;

// Stack-allocated format buffers — one per summary line, max 48 chars each.
var _sbuf_name: [48]u8 = undefined;
var _sbuf_email: [48]u8 = undefined;
var _sbuf_country: [48]u8 = undefined;
var _sbuf_newsletter: [24]u8 = undefined;
var _sbuf_contact: [32]u8 = undefined;
var _sbuf_volume: [24]u8 = undefined;

/// Called each dirty frame via AppInner.per_frame_fn.
/// Reads the slider value, formats it as an integer string, and calls scene.setText.
/// Also refreshes the 6 summary-panel Text elements from live form state.
/// Guards against wrong-screen (other screens may have elements at the same indices).
pub fn tick(scene: *Scene) void {
    if (_slider_idx == 0) return;
    if (_slider_idx >= scene.elements.layout.items.len) return;
    if (scene.kindOfIdx(_slider_idx) != .slider) return;

    // --- Volume readout ---
    const val = scene.getSliderValue(_slider_idx);
    const val_int: i32 = @intFromFloat(@round(val));
    const vol_str = std.fmt.bufPrint(&_vol_buf, "{d}", .{val_int}) catch return;
    scene.setText(_vol_val_idx, vol_str);
    if (_vol_val_idx < scene.elements.dirty.bit_length)
        scene.elements.dirty.set(_vol_val_idx);

    // --- Summary panel (only when summary indices are wired) ---
    if (_sum_name_idx == 0) return;

    // Name
    const name_text = if (_name_input_idx < scene._input_state.items.len)
        scene.getInputText(_name_input_idx)
    else
        "";
    const s_name = std.fmt.bufPrint(&_sbuf_name, "Name: {s}", .{name_text}) catch "Name: ?";
    scene.setText(_sum_name_idx, s_name);
    if (_sum_name_idx < scene.elements.dirty.bit_length)
        scene.elements.dirty.set(_sum_name_idx);

    // Email
    const email_text = if (_email_input_idx < scene._input_state.items.len)
        scene.getInputText(_email_input_idx)
    else
        "";
    const s_email = std.fmt.bufPrint(&_sbuf_email, "Email: {s}", .{email_text}) catch "Email: ?";
    scene.setText(_sum_email_idx, s_email);
    if (_sum_email_idx < scene.elements.dirty.bit_length)
        scene.elements.dirty.set(_sum_email_idx);

    // Country (read from dropdown selected label)
    const country_label: []const u8 = blk: {
        if (_country_dd_idx < scene._dropdown_state.items.len) {
            const dd = scene.dropdownStateOf(_country_dd_idx);
            if (dd.options.items.len > 0) break :blk dd.options.items[dd.selected_idx].label;
        }
        break :blk "";
    };
    const s_country = std.fmt.bufPrint(&_sbuf_country, "Country: {s}", .{country_label}) catch "Country: ?";
    scene.setText(_sum_country_idx, s_country);
    if (_sum_country_idx < scene.elements.dirty.bit_length)
        scene.elements.dirty.set(_sum_country_idx);

    // Newsletter
    const subscribed = if (_checkbox_idx < scene._checkbox_state.items.len)
        scene.isCheckboxChecked(_checkbox_idx)
    else
        false;
    const s_newsletter = std.fmt.bufPrint(&_sbuf_newsletter, "Newsletter: {s}", .{if (subscribed) "Yes" else "No"}) catch "Newsletter: ?";
    scene.setText(_sum_newsletter_idx, s_newsletter);
    if (_sum_newsletter_idx < scene.elements.dirty.bit_length)
        scene.elements.dirty.set(_sum_newsletter_idx);

    // Contact (first selected radio label, or "—")
    const contact_label: []const u8 = blk: {
        if (_radio_email_idx < scene._radio_state.items.len and scene.isRadioSelected(_radio_email_idx)) break :blk "Email";
        if (_radio_phone_idx < scene._radio_state.items.len and scene.isRadioSelected(_radio_phone_idx)) break :blk "Phone";
        if (_radio_post_idx < scene._radio_state.items.len and scene.isRadioSelected(_radio_post_idx)) break :blk "Post";
        break :blk "\xe2\x80\x94"; // em-dash
    };
    const s_contact = std.fmt.bufPrint(&_sbuf_contact, "Contact: {s}", .{contact_label}) catch "Contact: ?";
    scene.setText(_sum_contact_idx, s_contact);
    if (_sum_contact_idx < scene.elements.dirty.bit_length)
        scene.elements.dirty.set(_sum_contact_idx);

    // Volume (reuse the already-formatted vol_str)
    const s_volume = std.fmt.bufPrint(&_sbuf_volume, "Volume: {s}", .{vol_str}) catch "Volume: ?";
    scene.setText(_sum_volume_idx, s_volume);
    if (_sum_volume_idx < scene.elements.dirty.bit_length)
        scene.elements.dirty.set(_sum_volume_idx);
}

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
    const c: *FormsCtx = @ptrCast(@alignCast(ctx.?));
    _submit_cb = SubmitCb{ .global = c.global };

    const heading_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Form Widgets" } }};
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl", .attrs = &heading_attrs };
    const sep = NodeDesc{ .tag = "Separator" };

    // --- Name input ---
    const name_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Full name" } }};
    const name_lbl   = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &name_lbl_attrs };
    const name_in_attrs = [1]Attr{.{ .name = "placeholder", .value = .{ .literal = "Enter your name" } }};
    const name_input = NodeDesc{ .tag = "Input", .classes = "w-full", .attrs = &name_in_attrs };
    const name_children = [2]NodeDesc{ name_lbl, name_input };
    const name_group = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &name_children };

    // --- Email input ---
    const email_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Email address" } }};
    const email_lbl   = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &email_lbl_attrs };
    const email_in_attrs = [1]Attr{.{ .name = "placeholder", .value = .{ .literal = "you@example.com" } }};
    const email_input = NodeDesc{ .tag = "Input", .classes = "w-full", .attrs = &email_in_attrs };
    const email_children = [2]NodeDesc{ email_lbl, email_input };
    const email_group = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &email_children };

    // --- Textarea ---
    const notes_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Notes" } }};
    const notes_lbl   = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &notes_lbl_attrs };
    const notes_val_attrs = [1]Attr{.{ .name = "placeholder", .value = .{ .literal = "Type here\xE2\x80\xA6" } }};
    const notes_ta   = NodeDesc{ .tag = "Textarea", .classes = "w-full h-32", .attrs = &notes_val_attrs };
    const notes_children = [2]NodeDesc{ notes_lbl, notes_ta };
    const notes_group = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &notes_children };

    // --- Dropdown ---
    const country_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Country" } }};
    const country_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &country_lbl_attrs };
    const country_dd  = NodeDesc{ .tag = "Dropdown", .classes = "w-full" };
    const country_children = [2]NodeDesc{ country_lbl, country_dd };
    const country_group = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &country_children };

    // --- Checkbox ---
    const cb_attrs = [1]Attr{.{ .name = "label", .value = .{ .literal = "Subscribe to newsletter" } }};
    const checkbox = NodeDesc{ .tag = "Checkbox", .attrs = &cb_attrs };

    // --- Radio group ---
    const radio_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Preferred contact" } }};
    const radio_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &radio_lbl_attrs };
    const r_email_attrs = [2]Attr{
        .{ .name = "label", .value = .{ .literal = "Email" } },
        .{ .name = "group", .value = .{ .literal = "contact" } },
    };
    const r_phone_attrs = [2]Attr{
        .{ .name = "label", .value = .{ .literal = "Phone" } },
        .{ .name = "group", .value = .{ .literal = "contact" } },
    };
    const r_post_attrs = [2]Attr{
        .{ .name = "label", .value = .{ .literal = "Post" } },
        .{ .name = "group", .value = .{ .literal = "contact" } },
    };
    const r_email = NodeDesc{ .tag = "Radio", .attrs = &r_email_attrs };
    const r_phone = NodeDesc{ .tag = "Radio", .attrs = &r_phone_attrs };
    const r_post  = NodeDesc{ .tag = "Radio", .attrs = &r_post_attrs };
    const radios_children = [4]NodeDesc{ radio_lbl, r_email, r_phone, r_post };
    const radios_group = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &radios_children };

    // --- Slider ---
    const slider_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Volume" } }};
    const slider_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &slider_lbl_attrs };
    const slider_attrs = [3]Attr{
        .{ .name = "min",   .value = .{ .literal = "0" } },
        .{ .name = "max",   .value = .{ .literal = "100" } },
        .{ .name = "value", .value = .{ .literal = "50" } },
    };
    const slider = NodeDesc{ .tag = "Slider", .classes = "flex-1", .attrs = &slider_attrs };
    const vol_val_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "50" } }};
    const vol_val = NodeDesc{ .tag = "Text", .classes = "w-8", .attrs = &vol_val_attrs };
    const slider_row_children = [2]NodeDesc{ slider, vol_val };
    const slider_row = NodeDesc{ .tag = "Row", .classes = "gap-3 items-center", .children = &slider_row_children };
    const slider_children = [2]NodeDesc{ slider_lbl, slider_row };
    const slider_group = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &slider_children };

    // --- Buttons ---
    // Bug 5 fix: add flex-1 so both buttons share available row width equally.
    // Mismatch 1 fix: apply ghost style at instantiation time via classes so the Reset
    // button text is always visible (bg-surface text-body border border-default).
    // This avoids the fragile post-instantiation index-based override.
    const submit_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Submit" } }};
    const submit_btn   = NodeDesc{ .tag = "Button", .classes = "flex-1", .attrs = &submit_attrs };
    const reset_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Reset" } }};
    const reset_btn    = NodeDesc{ .tag = "Button", .classes = "flex-1 bg-surface text-body border border-default", .attrs = &reset_attrs };
    const btn_row_children = [2]NodeDesc{ submit_btn, reset_btn };
    const btn_row = NodeDesc{ .tag = "Row", .classes = "gap-3 w-full", .children = &btn_row_children };

    // --- Summary panel ---
    // Mismatch 2 fix: live summary card below button row showing current form values.
    // Six Text elements updated each frame via tick(). Initial placeholder text is
    // overwritten on the first tick() call.
    const sum_name_attrs       = [1]Attr{.{ .name = "text", .value = .{ .literal = "Name: " } }};
    const sum_email_attrs      = [1]Attr{.{ .name = "text", .value = .{ .literal = "Email: " } }};
    const sum_country_attrs    = [1]Attr{.{ .name = "text", .value = .{ .literal = "Country: " } }};
    const sum_newsletter_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Newsletter: No" } }};
    const sum_contact_attrs    = [1]Attr{.{ .name = "text", .value = .{ .literal = "Contact: \xe2\x80\x94" } }};
    const sum_volume_attrs     = [1]Attr{.{ .name = "text", .value = .{ .literal = "Volume: 50" } }};
    const sum_name_txt       = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &sum_name_attrs };
    const sum_email_txt      = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &sum_email_attrs };
    const sum_country_txt    = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &sum_country_attrs };
    const sum_newsletter_txt = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &sum_newsletter_attrs };
    const sum_contact_txt    = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &sum_contact_attrs };
    const sum_volume_txt     = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &sum_volume_attrs };
    const summary_children = [6]NodeDesc{
        sum_name_txt, sum_email_txt, sum_country_txt,
        sum_newsletter_txt, sum_contact_txt, sum_volume_txt,
    };
    const summary_card = NodeDesc{ .tag = "Card", .classes = "p-3 gap-1 bg-canvas", .children = &summary_children };

    // --- Form card ---
    const form_children = [9]NodeDesc{
        name_group, email_group, notes_group, country_group,
        checkbox, radios_group, slider_group, btn_row, summary_card,
    };
    const form_card = NodeDesc{ .tag = "Card", .classes = "p-4 gap-4", .children = &form_children };

    // --- Schema form section ---
    const schema_sep = NodeDesc{ .tag = "Separator" };
    const schema_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Schema-driven form (module 08)" } }};
    const schema_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &schema_h_attrs };
    const schema_note_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "A Form widget built from a JSON Schema at compile time." } }};
    const schema_note = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &schema_note_attrs };

    const prod_name_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Product name *" } }};
    const prod_name_lbl   = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &prod_name_lbl_attrs };
    const prod_name_input = NodeDesc{ .tag = "Input", .classes = "w-full" };
    const prod_name_g_children = [2]NodeDesc{ prod_name_lbl, prod_name_input };
    const prod_name_g = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &prod_name_g_children };

    const prod_price_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Price (USD) *" } }};
    const prod_price_lbl   = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &prod_price_lbl_attrs };
    const prod_price_input = NodeDesc{ .tag = "Input", .classes = "w-full" };
    const prod_price_g_children = [2]NodeDesc{ prod_price_lbl, prod_price_input };
    const prod_price_g = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &prod_price_g_children };

    const prod_stock_attrs = [1]Attr{.{ .name = "label", .value = .{ .literal = "In stock" } }};
    const prod_stock = NodeDesc{ .tag = "Checkbox", .attrs = &prod_stock_attrs };

    const validate_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Validate" } }};
    const validate_btn = NodeDesc{ .tag = "Button", .attrs = &validate_attrs };

    const schema_form_children = [5]NodeDesc{ schema_h, schema_note, prod_name_g, prod_price_g, prod_stock };
    const schema_form = NodeDesc{ .tag = "Card", .classes = "p-4 gap-3", .children = &schema_form_children };

    const schema_children = [3]NodeDesc{ schema_sep, schema_form, validate_btn };
    const schema_sect = NodeDesc{ .tag = "Column", .classes = "gap-3", .children = &schema_children };

    // --- Scroll wrapper ---
    const body_children = [3]NodeDesc{ form_card, schema_sect, NodeDesc{ .tag = "Separator" } };
    const body_col = NodeDesc{ .tag = "Column", .classes = "gap-4", .children = &body_children };
    const scroll = NodeDesc{ .tag = "ScrollView", .classes = "flex-1", .children = &[1]NodeDesc{
        NodeDesc{ .tag = "Column", .classes = "p-2", .children = &[1]NodeDesc{body_col} },
    } };

    const content_children = [3]NodeDesc{ heading, sep, scroll };
    const content = NodeDesc{ .tag = "Column", .classes = "flex-1 gap-3 p-6", .children = &content_children };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), content };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 4); // 4 = Forms button

    // Wire dropdown options.
    // DFS indices (pre-order): 0=root, 1=sidebar, 2-9=sidebar btns, 10=content,
    //   11=heading, 12=sep, 13=scroll, 14=inner-col(p-2), 15=body-col,
    //   16=form_card,
    //   17=name_group, 18=name_lbl, 19=name_input,
    //   20=email_group, 21=email_lbl, 22=email_input,
    //   23=notes_group, 24=notes_lbl, 25=notes_ta,
    //   26=country_group, 27=country_lbl, 28=country_dd,
    //   29=checkbox,
    //   30=radios_group, 31=radio_lbl, 32=r_email, 33=r_phone, 34=r_post,
    //   35=slider_group, 36=slider_lbl, 37=slider_row, 38=slider, 39=vol_val,
    //   40=btn_row, 41=submit_btn,
    //   42=reset_btn  ← ghost style applied via classes (bg-surface text-body border border-default)
    //   43=summary_card, 44=sum_name, 45=sum_email, 46=sum_country,
    //   47=sum_newsletter, 48=sum_contact, 49=sum_volume
    //   (schema section follows at 50+)
    try scene.setDropdownOptions(28, &_country_opts);

    // Wire submit button callback.
    try scene.setButtonCallback(41, CallbackFn{
        .ptr = &_submit_cb,
        .call = SubmitCb.onClick,
    });

    // Record slider and readout indices for per-frame tick.
    _slider_idx = 38;
    _vol_val_idx = 39;

    // Record source widget indices for the summary panel.
    _name_input_idx    = 19;
    _email_input_idx   = 22;
    _country_dd_idx    = 28;
    _checkbox_idx      = 29;
    _radio_email_idx   = 32;
    _radio_phone_idx   = 33;
    _radio_post_idx    = 34;

    // Record summary Text element indices.
    _sum_name_idx       = 44;
    _sum_email_idx      = 45;
    _sum_country_idx    = 46;
    _sum_newsletter_idx = 47;
    _sum_contact_idx    = 48;
    _sum_volume_idx     = 49;
}
