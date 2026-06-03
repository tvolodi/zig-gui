# R7B — M7-12: Avatar / badge

> Roadmap item: M7-12  
> Depends on: M4-04 (image/icon rendering — `ImageAtlas`, `ImageId`), M4-01 (pseudo-state styling)  
> Read `00_constitution.md` before this file.

## Purpose

An `<Avatar>` displays a circular image or a two-letter initials fallback. A `<Badge>` is a
small colored pill that can be attached to any element (typically an avatar or button) as a
child, rendered in the top-right corner. Both are new `WidgetKind` variants; `Avatar` uses
the `ImageAtlas` from M4-04; `Badge` is a pure geometry + text element.

## What to build

### Widget kinds

```zig
pub const WidgetKind = enum { /* ...existing... */ avatar, badge };

// tagToKind: "Avatar" → .avatar, "Badge" → .badge
// defaultLayoutFor: .avatar → { .display = .block, .width = px 40, .height = px 40 }
// defaultLayoutFor: .badge  → { .display = .block }
```

### `AvatarState`

```zig
pub const AvatarState = struct {
    image_id:  ImageId = 0,         // 0 = no image; show initials fallback
    initials:  [2]u8   = .{ '?', 0 }, // up to 2 chars; null-terminated
    size_px:   f32     = 40,
};

pub const Scene = struct {
    _avatar_state: std.ArrayListUnmanaged(AvatarState) = .empty,

    pub fn avatarStateOf(self: *Scene, idx: u32) *AvatarState

    pub fn setAvatarImage(self: *Scene, idx: u32, id: ImageId) void

    pub fn setAvatarInitials(self: *Scene, idx: u32, initials: []const u8) void
};
```

Markup:

```html
<Avatar image_id="42" size="40" />
<Avatar initials="JD" class="w-12 h-12" />
```

During `instantiate`, `image_id` attr is parsed as `u16`; `initials` is stored (up to 2 bytes).

### `Avatar` rendering in `buildDrawList`

```zig
const S = state.size_px;
const cx = layout_rect.x + layout_rect.w / 2;
const cy = layout_rect.y + layout_rect.h / 2;

// Circle background (clip radius = S/2 approximated by radius):
const circle = Rect{ .x = layout_rect.x, .y = layout_rect.y, .w = S, .h = S };

if (state.image_id != 0) {
    // Image: emit as image_rect with the circle rect.
    const uv = image_atlas.getRect(state.image_id);
    try cmds.append(.{ .image_rect = .{
        .dst  = circle,
        .uv   = .{ .x = uv.uv_x, .y = uv.uv_y, .w = uv.uv_w, .h = uv.uv_h },
        .tint = Color{ .r = 255, .g = 255, .b = 255, .a = 255 },
    }});
} else {
    // Initials fallback: colored circle + text.
    // Hash the initials to pick a background from a small palette.
    const bg = initialsColor(state.initials[0], tokens);
    try cmds.append(.{ .filled_rect = .{ .rect = circle, .color = bg,
                                         .radius = S / 2 } });
    // Center the initials text (use a GlyphCmd for each character).
    // For simplicity in v1, emit two glyphs side by side.
    // (Full centering requires hitching into layoutParagraph — use approximation.)
    const init_str = state.initials[0..if (state.initials[1] != 0) @as(usize, 2) else 1];
    _ = init_str; // emit via the normal text path if textOf returns the initials
}
```

`initialsColor` returns one of four token colors based on the first character mod 4:

```zig
fn initialsColor(c: u8, tokens: Tokens) Color {
    return switch (c % 4) {
        0 => tokens.accent,
        1 => tokens.ok_400,
        2 => tokens.info_400,
        else => tokens.warn_400,
    };
}
```

The initials text is stored in the `Scene._text` slot for the avatar element (via the normal
text mechanism), so the existing glyph emission path handles it.

### `Badge` widget and state

`<Badge>` is a child element overlaid at the top-right of its parent using absolute
positioning. In v1, "absolute positioning" is approximated by rendering the badge's rect at
a fixed offset from the parent's top-right corner in `buildDrawList`, outside the normal
layout flow.

```zig
pub const BadgeState = struct {
    text:    [8]u8 = .{0} ** 8,  // short label (count, status dot, etc.); null-terminated
    color:   BadgeColor = .default,
};

pub const BadgeColor = enum { default, success, warning, error_c };  // "error" is a keyword
```

```html
<Avatar>
    <Badge text="3" color="error" />
</Avatar>
```

During `buildDrawList`, after drawing the avatar, if a badge child exists, draw it at:

```zig
const badge_rect = Rect{
    .x = avatar_rect.x + avatar_rect.w - badge_w / 2,
    .y = avatar_rect.y - badge_h / 2,
    .w = badge_w,
    .h = badge_h,
};
```

The badge is always rendered in the overlay layer (via `OverlayLayer`) to avoid being
clipped by parent scissor rects. `App.run()` calls `overlay.setSlot(badge_slot_id, cmds)`.

### Module location

```
src/07/types.zig   — WidgetKind.avatar/.badge, AvatarState, BadgeState, avatarStateOf, setAvatarImage, setAvatarInitials
src/09/types.zig   — avatar/badge rendering in buildDrawList
docs/requirements/R7B_avatar_badge.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No image cropping to circle** — the avatar image is a square; cropping to a circle
  requires a mask or SDF which is post-v1. The `radius` field on `image_rect` is not
  currently supported; the filled circle background is layered behind the image.
- **No status indicator dot** — only text badges; no colored dot variant.
- **No badge animation** — static; no pulse or bounce.
- **No avatar group** (overlapping stacked avatars) — post-v1.

## Acceptance criteria

1. `zig build test-07` passes. `<Avatar initials="AB"/>` instantiates; `setAvatarImage`
   sets `image_id`. `<Avatar><Badge text="5"/></Avatar>` instantiates with two elements.
2. Integration: avatar with initials renders colored circle + letters. Avatar with image
   renders the image. Badge "3" appears at top-right. Checklist ticked.
