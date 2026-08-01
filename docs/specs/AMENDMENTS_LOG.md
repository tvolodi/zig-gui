# Constitution Amendments Log

> Append-only record of every change to `00_constitution.md` made under the Autonomous Amendment
> Procedure (AAP, constitution §8). One row per amendment. Newest at the top.
>
> This log is the owner's asynchronous audit trail: agents amend the constitution without asking,
> and the owner reviews here (plus git history) and may revert. Logging every amendment is the
> one entrenched requirement of the AAP — do not amend the constitution without adding a row.
>
> **Row format:** `date · agent/role · section/invariant · change (old→new summary) · reason · task/run id`

---

## Entries

### 2026-08-01 · implementer · §5 INV-5.1 (additive — Palette, src/05/types.zig) — RN15: distinct dark-mode card-surface stop fixes invisible Card/Input borders
- **Old:** RN14's `Tokens.dark()` mapped `bg_surface` AND `bg_raised` to `p.gray_800` (`#262626`) — the SAME palette stop `border_default` also used. `Palette` had exactly 7 gray stops (`gray_50/100/200/400/600/800/900`), documented at the time as "an accepted approximation given the fixed 7-stop Palette shape (no new field added; out of scope per handoff)."
- **New:** `Palette` gains an additive 8th gray stop, `gray_850: Color = Color.hex(0x171717)` (AI-Qadam's actual dark-mode `--card` value), set explicitly in `Palette.default()`. `Tokens.dark()` now maps `bg_surface` and `bg_raised` to `p.gray_850` instead of `p.gray_800`, while `border_default` remains `p.gray_800` (`#262626`). Card and Input widgets (which resolve via the `bg-raised` + bare `border` Tailwind-subset classes, per `src/app/ui/card.zig` / `input.zig`) now render a fill of `#171717` against a border of `#262626` — genuinely distinct, matching AI-Qadam's ground truth exactly instead of approximating it.
- **Reason:** Workflow 2 (issue resolution) — an independent Visual Tester re-check found Card/Input borders visually invisible, with pixel-sampled evidence that the rendered border hex equaled the rendered fill hex (`#262626` == `#262626`). Root cause traced to the RN14-era 7-stop approximation noted above. Adding one additive palette field (matching the precedent already set by `radius_xl` in the same struct) removes the approximation cleanly with zero signature changes.
- **No invariant was weakened.** INV-4.3 preserved: the new value lives in `Palette` (layer 0), never referenced as a hex literal on a widget or component-style builder. INV-5.1 preserved: `gray_850` is an additive field with a default value; no existing `Palette`/`Tokens` signature changed. `docs/specs/05.acceptance_test.zig` asserts only structural properties (luminance ordering, `card.background == t.bg_surface`) — no hardcoded hex — so it needed no change; confirmed by `zig build test` passing with zero regressions after the remap.
- **Files changed:** `src/05/types.zig` (`Palette.gray_850` field + `Palette.default()` + `Tokens.dark()`).
- **Authority:** enacted under the AAP (§8). No owner sign-off required. task: Workflow 2 issue resolution — Gap 2 (Card/Input border-vs-fill contrast), badge-corner-radius Gap 1 investigated and found already correctly wired (no code change needed there).

### 2026-08-01 · implementer · §5 INV-5.1 (additive — Tokens, src/05/types.zig + src/06/types.zig) — RN14: `ui/` component library visually reproduces AI-Qadam design tokens
- **Old:** `Palette.default()` carried zinc/RN12 neutrals (`gray_*` = zinc-50..950) and a generic teal (`teal_400 = 0x2DD4BF`, `accent_400 = 0x18181B` zinc-900). `Tokens.light/dark` mapped gray stops symmetrically (light and dark ramps sharing the same 7 stops in mirrored roles) and set `radius_lg = 16`. `Tokens` had no `radius_xl` field. `src/app/ui/{button,card,input,badge}.zig` were generic shadcn-style placeholders (e.g. badge used `rounded-full`, card used `p-4`). Module 06's class resolver had no `rounded-xl` or `font-medium` class.
- **New:** `Palette.default()` gray/accent/status stops replaced with AI-Qadam-derived hex values (OKLCH→sRGB from AI-Qadam's actual `tokens.css`): light bg `#FFFFFF`/muted `#F5F5F5`/border `#E5E5E5`/muted-fg `#737373`/fg `#0A0A0A`; dark bg `#0A0A0A`/muted+border `#262626`/muted-fg `#A1A1A1`/fg `#FAFAFA`; primary teal `#39B3AF` (dark) / `#008D89` (light, `accent_600`) / `#5FC4C0` (`accent_200`, dark-mode hover tint); status `ok #00D391`, `warn #FFAB00`, `err #FF6468`. `teal_400` repointed to `#39B3AF` (was `#2DD4BF`). `Tokens.light()`/`dark()` role→stop mappings rewritten (asymmetric per-mode, not mirrored) to fit AI-Qadam's actual non-symmetric ramps; `radius_lg` 16→12; new additive field `radius_xl: f32 = 16` wired in both. `src/06/types.zig` gained `rounded-xl` (→`tokens.radius_xl`) and `font-medium` (→`font_bold = true`, documented as an approximation — no numeric weight scale exists) classes, mirroring existing `rounded-lg`/`font-bold` patterns. `src/app/ui/button.zig` rewritten to AI-Qadam's `h-10 rounded-md px-4 gap-2 text-sm font-medium` base with variant-specific bg/border; `card.zig` to `p-6` (was `p-4`) + `rounded-lg` (now 12px) + `border`; `input.zig` to `h-10 rounded-md px-3`; `badge.zig` to `rounded-sm` (was `rounded-full`, now matches AI-Qadam's 6px exactly) + `h-6` (nearest 4px-scale step to the ground-truth 22px — accepted 2px discrepancy, no arbitrary-value class exists in module 06) + `font-medium`. `src/05/05_test.zig` (mutable unit test) hardcoded hex assertions updated to match. `build.zig` gained a `mod_ui` module descriptor (`src/app/ui/mod.zig`) wired into `demo_mod`, since Zig's module sandboxing blocked the prior relative `@import("../../app/ui/mod.zig")` from `src/demo/screens/components.zig` (import-outside-module-path error) — `src/demo/screens/components.zig` now imports and uses `ui.Button.*`/`ui.Card.*`/`ui.Input.*`/`ui.Badge.*` instead of duplicated inline class strings.
- **Reason:** Task requirement (Validator handoff, Step 1 PASS) — reproduce AI-Qadam's actual design tokens in the `src/app/ui/` component class-string library as a training reference. `docs/specs/05.acceptance_test.zig` tests are structural (luminance ordering, monotonicity, accent-stability-across-modes, token-tracing) not hardcoded-hex, so no frozen-contract change was needed — confirmed by rerunning `zig test`/`zig build test-05` after the palette rewrite (all pass). `radius_xl` is additive only (INV-5.1: no existing signature changed). The `mod_ui` build.zig module was a genuine build-order/tooling gap, not a design choice — resolved under the AAP because `docs/AGENT_GUIDE.md` §8 covers "a task instruction that contradicts an invariant" and this was a mechanical block (Zig's module-path sandboxing) preventing the explicitly-requested "check `components.zig` renders real coverage" step.
- **No invariant was weakened.** INV-4.3 preserved: all new values live in `Palette`/`Tokens` (layers 0/1), never referenced as hex literals on a widget. INV-5.1 preserved: only additive fields (`radius_xl`) and additive classes (`rounded-xl`, `font-medium`); no existing signature changed. INV-3.4 (build order) preserved: `mod_ui` has zero dependencies and sits alongside other `src/app/*` helper modules.
- **Files changed:** `src/05/types.zig`, `src/05/05_test.zig`, `src/06/types.zig`, `src/app/ui/button.zig`, `src/app/ui/card.zig`, `src/app/ui/input.zig`, `src/app/ui/badge.zig`, `src/demo/screens/components.zig`, `build.zig`.
- **Authority:** enacted under the AAP (§8). No owner sign-off required. task: RN14 (AI-Qadam visual analog, `src/app/ui/` component library).

### 2026-08-01 · implementer · §5 INV-5.1 (additive — Palette + Tokens, src/05/types.zig) — `teal_400` palette stop + `accent_teal` semantic token for the AI-Qadam visual analog (RAI)
- **Old:** `Palette` carried only `accent_200/400/600` (zinc neutrals). `Tokens` carried `accent`/`accent_hover`/`accent_text` with no brand-specific teal alternative. INV-4.3 forbids hex literals on widgets, so any teal accent on the AI-Qadam screen would have required a literal.
- **New:** Added `teal_400: Color = Color.hex(0x2DD4BF)` to `Palette` (also propagated to `Palette.highContrast()` and `Palette.highContrastDark()`). Added `accent_teal: Color` to `Tokens` and wired it in both `Tokens.light(p)` and `Tokens.dark(p)` as `.accent_teal = p.teal_400`.
- **Reason:** RAI (AI-Qadam visual analog) requires a teal accent on logo, "Sign in" button, "Browse events" CTA, and "Send me a confirmation" button. The existing zinc `accent` would either force a literal (violating INV-4.3) or give the wrong color (`zinc_900` reads as black, not teal). The additive `accent_teal` field lets the AI-Qadam screen reference a brand token without disturbing `accent` for every other showcase screen.
- **No invariant was weakened.** No widget references the new token by a hex literal. INV-5.1 is satisfied: pubic Types signatures are unchanged (only new fields). INV-4.3 is satisfied: widgets reference `tokens.accent_teal`, not raw values.
- **Files changed:** `src/05/types.zig` (Palette + Palette.highContrast + Palette.highContrastDark + Tokens struct + Tokens.light + Tokens.dark).
- **Authority:** enacted under the AAP (§8). No owner sign-off. task: RAI.

### 2026-06-15 · validator · §5 INV-5.4 + glossary.md (RN-AAP-01 — M27 RN1–RN7 pre-implementation validation)
- **Old INV-5.4:** "Do NOT implement them [non-goals], even if they seem helpful or trivial."  
  No exception clause for "post-vN" deferrals that have been superseded by new requirement documents.
- **New INV-5.4:** Addendum added: a spec's "post-v1/v2" non-goal is a deferral, not a permanent prohibition; when a later human-authored requirement document explicitly targets that item for a named milestone, the deferral is superseded. Implementer must update the original spec's non-goal section at implementation time.
- **Glossary additions (12 new terms, INV-5.5):** `inner_radius`, `center label slot`, `leader line`, `chart annotation`, `callout`, `DateRangeValue`, `date range picker`, `formatCurrency`, `masked value`, `TrendBadge`, `crosshair`, `value flag`.
- **Reason:** Requirement validation for RN0 (M27 dashboard gap analysis) found: (1) RN4 `formatCurrency` conflicts with RE0's explicit "No currency formatting" non-goal under INV-5.4; resolved by clarifying that "post-v1" is a deferral, not a permanent ban, and RN4 is an explicit human-authored requirement for M27. (2) Twelve project terms introduced by RN1–RN7 had no glossary entries (INV-5.5 violation); all twelve added.
- **Files changed:** `docs/specs/00_constitution.md` (INV-5.4 addendum), `docs/specs/glossary.md` (12 new entries).
- **Authority:** enacted under the AAP (§8). No owner sign-off required. task: RN0 requirement validation.

 (AAP-M19 — M19-01 through M19-04 unblocked)
- **Old:** INV-5.6 listed "any HTTP client" as still forbidden; §6 deferred M19-01–04 to post-v1 pending HTTP + bsdiff approval.
- **New:** INV-5.6 extended with two approvals: (1) `std.http` (Zig standard library — zero new package); (2) vendored pure-Zig bsdiff/bspatch implementation in `src/tools/bspatch.zig` (BSDFRAW1 variant, no bzip2, no external C). §6 amended to show deferral superseded.
- **Reason:** The deferral was blocking legitimate roadmap items (M19-01–04). Both additions introduce zero new external packages. `std.http` was already in the Zig standard library (approved in INV-5.6 as "the Zig standard library"); bspatch is vendored source code authored in this repo.
- **Files changed:** `docs/specs/00_constitution.md` (INV-5.6 NOTE added, §6 amended).
- **Authority:** enacted under the AAP (§8). No owner sign-off required.

### 2026-06-14 · implementer · §5 INV-5.3 (drawFrame AtlasHandles signature — RJ1)
- **Old:** `VulkanBackend.drawFrame(commands, atlas: *const anyopaque)` — raw opaque pointer
- **New:** `VulkanBackend.drawFrame(commands, handles: AtlasHandles)` — typed struct; `handles.glyph.backend_obj` is the `*const GpuAtlas`
- **Call sites updated in the same pass (INV-5.3):**
  - `docs/specs/09.acceptance_test.zig` line 384: `drawFrame(&.{}, &gpu_atlas)` → `drawFrame(&.{}, AtlasHandles{ .glyph = ..., .sdf = ..., .image = ... })`
  - `src/app/app.zig` lines 999, 1272: `drawFrame(all_cmds2, &self.atlas_gpu)` → `drawFrame(all_cmds2, AtlasHandles{ .glyph = ..., .sdf = ..., .image = ... })`
- **Also in this pass:** extracted `createSurface` Vulkan branch into `src/01/surface_vulkan.zig` (RJ2 deferred item); `types.zig` now dispatches to `surface_vulkan.createVulkanSurface`
- **Reason:** RJ1 deferred items from M20 — typed `AtlasHandles` per GpuBackend contract (`src/10/types.zig` doc); surface layer extraction required by RJ2 definition of done
- **Authority:** enacted under the AAP (§8). No owner sign-off.

### 2026-06-14 · implementer · §5 new INV-5.7 (src/ as sole compilation source) · SR-03 — moved canonical implementations from docs/specs/ to src/ for modules 03, 04, 05, 06; all build.zig module roots and test files updated to import from src/; docs/specs/*.types.zig files converted to non-compiled mirrors with "GENERATED MIRROR" headers · task: SR-03
- **Old:** Module roots for mod03/04/05/06 in `build.zig` pointed at `docs/specs/NN.types.zig`. Many test files and `src/screens/example.ui.zig` imported directly from `docs/specs/`. No constitution invariant addressed this.
- **New:** `build.zig` module roots now point at `src/NN/types.zig` for all modules. All test files (06_test.zig, 05_test.zig, high_contrast_test.zig, binding_test.zig, example.ui.zig) and the codegen tool (ui_codegen.zig) updated to import from `src/`. `docs/specs/03.types.zig`, `04.types.zig`, `05.types.zig`, `06.types.zig` given "GENERATED MIRROR" headers. INV-5.7 added to §5 of `00_constitution.md`.
- **Additional fixes in-pass (pre-existing issues):**
  - `docs/specs/10.smoke_test.zig` line 31: `@ptrFromInt` Zig 0.16 API — added `@as(*anyopaque, ...)` cast.
  - `src/07/types.zig` `Scene.deinit()`: added `_array_field_state.deinit(gpa)` to fix memory leak.
  - `src/07/types.zig` `defaultLayoutFor(.card)`: changed from `.flex` to `.block` to match 07_test.zig contract.
  - `src/08/08_test.zig` lines 482/512: `StringHashMap{}` → `.init(arena.allocator())` for Zig 0.16.
  - `src/08/08_test.zig` lines 491/521/574: `&.{...}` const-pointer-to-mutable-slice cast → `arena.allocator().dupe(F.Field, ...)`.
  - `src/08/types.zig` `validateScalar`: added type-mismatch check so `oneOf` works correctly.
  - `src/08/regex.zig` `matchesHelper`: fixed character class quantifier handling (`[A-Za-z]+` pattern was broken).
  - `src/01/types.zig` `VulkanBackend`: added `initQuadPipeline(alloc)` alias and changed `drawFrame` to accept `*const anyopaque` to match `docs/specs/09.acceptance_test.zig` frozen contract.
  - `src/09/types.zig` `emitFilledRectAA`: unified to always emit `filled_rect` (acceptance test contract requires `filled_rect` variant for button backgrounds).
  - `src/app/app.zig`: updated `drawFrame` call sites to pass `&self.atlas_gpu` directly.
- **Authority:** enacted under the AAP (§8). No owner sign-off.

### 2026-06-14 · implementer · build.zig module wiring (SR-02) · added missing named imports so cross-module `@import` paths resolve under Zig 0.16 module system · reason: SR-02 (`docs/requirements/M0_STABILIZATION.md`) — build was red because (a) `mod04` and `mod05` lacked `../03/types.zig` named-import wiring (causing "import of file outside module path" errors in font-scale-test, high-contrast-test, theme-swap-test, and others), and (b) `accept09_mod` registered its module imports under `../03/types.zig`-style names while `docs/specs/09.acceptance_test.zig` uses the `../03_element_store/types.zig`-style long-form names, causing 09-acceptance-test to fail to find its dependencies · task: SR-02
- **Changes to `build.zig`:**
  - Added `mod04.addImport("../03/types.zig", mod03)` directly after mod04 declaration (mirrors how mod07/mod08/mod09 wire their deps).
  - Added `mod05.addImport("../03/types.zig", mod03)` directly after mod05 declaration.
  - Changed `accept09_mod` import names from `../03/types.zig` → `../03_element_store/types.zig`, `../05/types.zig` → `../05_theme/types.zig`, `../07/types.zig` → `../07_components/types.zig`, `../06/types.zig` → `../06_markup_style/types.zig`, `../01/types.zig` → `../01_platform/types.zig`, `../04/types.zig` → `../04_layout_engine/types.zig` to match the literal strings in the acceptance test file.
- **No constitution invariant changed.** No acceptance-test assertion weakened. Build output after fix: clean (`zig build -Dgpu=vulkan` exits 0, no errors).
- **Authority:** enacted under the AAP (§8). No owner sign-off.

### 2026-06-14 · infra · §5 INV-5.3 (acceptance-test call-site sync) · synced frozen acceptance tests to the 5-arg `LayoutEngine.solve` contract · reason: SR-07 (`docs/requirements/M0_STABILIZATION.md`) — build was red at HEAD because `docs/specs/04.types.zig` had evolved `solve` to take `dpi_scale: f32` (5 args) while the frozen acceptance tests still called the 4-arg form, so `zig build test` could not pass · task: SR-07
- **Old:** `L.solve(&s, root, <constraints>, &scratch)` (4 args) in `docs/specs/04.acceptance_test.zig` (12 call sites) and the local `solve` helper in `docs/specs/09.acceptance_test.zig` (1 call site). Compilation failed with `expected 5 argument(s), found 4`.
- **New:** Each call site now passes `1.0` as `dpi_scale`, matching the default used by every non-frozen caller (`src/04/04_test.zig`, `src/09/09_test.zig`, `src/app/m12_test.zig`, `src/app/app.zig`) and the typical HiDPI factor documented on `solve`. Argument shapes only — no assertion was weakened, no bar lowered. `(AGENT AMENDMENT 2026-06-14)` markers added to both test-file headers.
- **Scope of companion edits (same change):** `docs/specs/04.acceptance_test.zig` (12 call sites + header marker), `docs/specs/09.acceptance_test.zig` (1 call site + header marker), this log row. No change to `docs/specs/04.types.zig` (the contract was already correct at HEAD — only the frozen tests lagged).
- **Authority:** enacted under the AAP (§8) + INV-5.3 (formalised earlier today via SR-06). No owner sign-off.

### 2026-06-14 · implementer · §5 (new INV-5.3), §7 (new green-build gate) · reason: write the phantom INV-5.3 into the body + add green-build gate · task: SR-06 (`docs/requirements/M0_STABILIZATION.md`)
- **Old:** §5 of `00_constitution.md` defined INV-5.1, 5.2, 5.4, 5.5, 5.6 and **skipped 5.3**.
  The "never modify `acceptance_test.zig`" rule was enforced via `CLAUDE.md` and agent notes
  but was absent from the constitution — a phantom rule. There was no green-build gate:
  modules could carry `done` while the build was red (the M20-class deadlock).
- **New:** Added INV-5.3 to §5 as a **procedure** (not an absolute freeze): a frozen
  `acceptance_test.zig` may be changed only in the same reviewed change as the `types.zig`
  signature it verifies, only to keep call sites matching the new contract (never to weaken
  assertions), and the change is recorded via an `(AGENT AMENDMENT …)` marker or
  `AMENDMENTS_LOG.md` row. A bare test edit without a contract change remains forbidden.
  Added the **green-build gate** to §7: no module may carry `done`, and no new milestone may
  start, while `zig build test` fails for any supported `-Dgpu` target. The aggregate `test`
  step was added to `build.zig` as the mechanical check.
- **Scope of companion edits (same change):** `build.zig` (new aggregate `test` step
  depending on every module test step), `docs/agents/AGENT_WORKFLOWS.md` (Module workflow
  Step 4 and §12 corrections updated to reference INV-5.3 instead of an absolute
  prohibition).
- **Markers in constitution:** both INV-5.3 and the green-build gate carry
  `(AGENT AMENDMENT 2026-06-14 via AAP §8)` and cite SR-06 as their source.

### 2026-06-14 · implementer · §2 INV-2.3 (addendum) · amended renderer/seam signature to stable `DrawListParams` form · reason: SR-04 (Milestone S) — `buildDrawList` had grown 3 positional parameters (subpixel_atlas, subpixel_text, sdf_atlas), breaking call sites and the frozen 09 acceptance test each time a backend/quality feature landed · task: SR-04
- **Old:** `fn buildDrawList(alloc, scene, atlas, image_atlas, font, tokens, subpixel_atlas, subpixel_text, sdf_atlas)` — 9 positional parameters; each new atlas re-broke every caller and the acceptance test.
- **New:** `fn buildDrawList(alloc, scene, params: DrawListParams)` — two fixed arguments plus a single params struct. Adding a future atlas is a field addition with a default; zero call-site edits. Acceptance test (09.acceptance_test.zig) call sites updated in the same change under the contract-amendment procedure (INV-5.3, formalised by SR-06).
- **Scope of companion edits (same change):** `src/09/types.zig` (new `DrawListParams` + new signature), `src/app/app.zig` (2 call sites), `src/09/09_test.zig` (18 call sites), `src/app/m12_test.zig` (4 call sites), `docs/specs/09.acceptance_test.zig` (7 call sites, also repairs the broken stray-arg form from RJ1), `docs/HOW_TO_USE.md` (doc example refreshed), `docs/specs/glossary.md` (DrawListParams term added).
- **Authority:** enacted under the AAP (§8). No owner sign-off.

### 2026-06-14 · architect/analyst · §0 header, §7 "When in doubt", new §8 (AAP) · reason: enable autonomous self-amendment · task: governance change (owner-directed)
- **Old:** Constitution conflicts and ambiguities required agents to STOP and surface the
  conflict to the owner; "explicit human override in the current task" was the only resolution
  path. `CLAUDE.md` and `AGENT_WORKFLOWS.md` routed constitution conflicts and new-dependency
  decisions to an `_escalation.md` and a human pause.
- **New:** Added §8 Autonomous Amendment Procedure. Agents now amend the constitution themselves
  (draft → apply with `(AGENT AMENDMENT …)` marker → log here → update glossary if needed →
  resume), with no review gate and no owner ratification. Human override is retained but becomes
  asynchronous (audit + revert via this log and git). The §0 header and §7 step 4 were rewritten
  to point at the AAP instead of human escalation.
- **Scope of companion edits (same change):** `CLAUDE.md` "What you NEVER do" / escalation rules
  and `AGENT_WORKFLOWS.md` (escalation protocol §11, Workflow step-1 validation gates, new
  Workflow 5 — Autonomous Constitution Amendment) updated to match.
- **Entrenched:** The AAP and this logging requirement remain in force over themselves; changing
  them is itself an amendment that must be logged here.

<!-- Add new amendments ABOVE this line, newest first, using the row format in the header. -->

### 2026-06-15 · implementer · §5 INV-5.3 (02.acceptance_test.zig call-site sync) · M24 renamed GlyphKey.codepoint → glyph_id; acceptance test call sites updated under INV-5.3
- **Old:** `GlyphKey.codepoint: u21` — field name and type used in `docs/specs/02.acceptance_test.zig` (5 literal occurrences) and declared in `docs/specs/02.types.zig`.
- **New:** `GlyphKey.glyph_id: u32` — matching the canonical implementation in `src/02/types.zig` which was updated during M24 (complex-script / HarfBuzz). The field holds a font-internal glyph index rather than a Unicode codepoint. `docs/specs/02.acceptance_test.zig` and `docs/specs/02.types.zig` updated to use `glyph_id` on all 5 call sites and the struct declaration respectively.
- **Contract change origin:** M24-01 (RK0) renamed the field in `src/02/types.zig` — the canonical implementation was already correct; only the spec mirror and frozen test lagged.
- **Assertion strength:** unchanged. No assertion weakened; only field-name call sites updated to match the existing contract.
- **Files changed:** `docs/specs/02.acceptance_test.zig` (5 GlyphKey literal sites), `docs/specs/02.types.zig` (struct declaration).
- **Authority:** enacted under the AAP (§8) + INV-5.3 (contract-amendment procedure). task: M27 regression fix — Fix 1.
