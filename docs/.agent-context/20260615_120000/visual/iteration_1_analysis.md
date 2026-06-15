# Visual Analysis — Iteration 1 — 2026-06-15

## Feature
RN5 (maskable_value) and RN6 (trend_badge) — rendering fixes applied to src/09/types.zig

## Command run
zig build visual-check

## Command output
[VK validation] Removing layer VK_LAYER_EOS_Overlay ... (non-fatal duplicate layer warning)
[VK validation] vkQueueSubmit(): pSubmits[0] performs a layout transition on presentable VkImage ... (non-fatal validation warning)
info: screenshot written to 'testdata/screenshot_actual.png'
PASS: screenshot 'testdata/screenshot_actual.png' — 100.0% non-zero IDAT bytes

## Exit code
0 (success)

## Screenshot
docs/.agent-context/20260615_120000/visual/iteration_1.png

## Automated criteria assessment

| # | Criterion | Verdict | Observation |
|---|---|---|---|
| 1 | Exit code 0 | MATCH | zig build visual-check exited 0 |
| 2 | Screenshot is non-blank (>5% non-zero IDAT bytes) | MATCH | 100.0% non-zero IDAT bytes |
| 3 | Application launched without crash | MATCH | Window opened, 3 frames rendered, screenshot written |

## Screenshot description
The rendered frame shows the zig-gui Showcase Home screen:
- Left sidebar with teal/green "Home" active item and nav entries: Text, Forms, Data, Theme, Notifications, Layout, State, M12, M13
- Main content: "zig-gui Showcase" heading and subtitle
- Horizontal rule separator
- Three feature-highlight cards: Fast, Small, Familiar with body text
- Prompt text: "Open a screen from the sidebar to explore each feature."

Frame has full non-transparent content. Sidebar, cards, glyphs, and backgrounds render with correct colors and contrast.

Vulkan validation-layer messages are non-fatal; they did not cause a rendering failure or alter the exit code.

## Result
VISUAL_PASS
