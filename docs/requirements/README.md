# Requirements index

Each file in this directory is a behavioral specification for one roadmap item.
Files are named `R<id>_<slug>.md` where `<id>` matches the milestone table numbering.

| File | Roadmap item | Status |
|---|---|---|
| [R10_app_main_loop.md](R10_app_main_loop.md) | M1-01 — App main loop | `planned` |
| [R11_event_delivery.md](R11_event_delivery.md) | M1-02 — Event delivery | `planned` |
| [R12_window_resize.md](R12_window_resize.md) | M1-03 — Window resize handling | `planned` |
| [R13_frame_pacing.md](R13_frame_pacing.md) | M1-04 — Frame pacing | `planned` |

Implementation order: R10 first (establishes `App`), then R11/R13 in parallel (they touch
different parts of the frame loop), then R12 (depends on both Platform callbacks and the
resize path that R10 sketches).
