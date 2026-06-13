# RG4 — M17-04: ARIA-like roles in markup

> Roadmap item: M17-04
> Depends on: M17-01 (AccessNode), Module 06 (markup parser)
> Read `00_constitution.md` before this file.

## Purpose

Extend the `.ui` markup parser (module 06) to recognize `role=`, `aria-label=`, and `aria-description=` attributes on any element. These attributes are parsed during `NodeDesc` construction and stored so module 07 can populate the `AccessNode` tree during `Scene.instantiate()`. This enables developers to:

- Override the semantic role of an element (e.g. `<div role="button">` for custom button-like elements).
- Assign human-readable labels to interactive widgets (e.g. `<Button aria-label="Submit form">`).
- Provide longer descriptions (e.g. `<Slider aria-description="Volume control (0-100%)">`).

## What to build

### Module 06 parser extension — `src/06/types.zig`

Extend `NodeDesc` struct to carry accessibility attributes:

```zig
pub const NodeDesc = struct {
    // ... existing fields (tag, classes, text, attributes, children) ...
    
    /// Override the default semantic role for this element.
    /// Parsed from role="button", role="list", etc.
    /// If empty/null, the renderer uses the kind-based default role from RG1.
    role: []const u8 = "",
    
    /// Accessibility label for the element.
    /// Parsed from aria-label="...".
    /// If empty/null, the renderer uses the element's text content or label slot.
    aria_label: []const u8 = "",
    
    /// Longer-form description.
    /// Parsed from aria-description="...".
    aria_description: []const u8 = "",
};
```

### Parser changes — `src/06/parser.zig`

When parsing markup, recognize the three new attributes and store them in `NodeDesc`:

```zig
// In parseNode() or equivalent:
if (attr_name matches "role") {
    node.role = attr_value;
} else if (attr_name matches "aria-label") {
    node.aria_label = attr_value;
} else if (attr_name matches "aria-description") {
    node.aria_description = attr_value;
}
```

These attributes are parsed the same way as existing ones — no special escaping or syntax. They are stripped from the generated `ComputedStyle` (they do NOT become Tailwind classes).

### Validation — `src/06/parser.zig`

When `role=` is specified, validate that it is a known role from the `AccessRole` enum defined in RG1:

```zig
fn parseRole(role_str: []const u8) !AccessRole {
    // Match role_str against AccessRole enum variants (case-insensitive for robustness).
    // Return error if the role is unknown.
    // Examples: "button", "list", "none", "region"
}

// In parseNode():
if (node.role.len > 0) {
    node.parsed_role = try parseRole(node.role);
} else {
    node.parsed_role = null;  // use kind-based default in module 07
}
```

Emit a `ParseDiagnostic` (with source location) if the role is invalid.

### Markup examples

```
<!-- Simple button with explicit role override -->
<Button role="none">
    <!-- This button is semantically "none" — screen readers ignore it -->
</Button>

<!-- Custom button-like element with accessibility label -->
<Card role="button" aria-label="Open settings">
    <Icon src="..." />
</Card>

<!-- Input with description -->
<Input aria-label="Password" aria-description="At least 8 characters, one uppercase, one number" />

<!-- List markup (optional role, usually inferred from tag or classes) -->
<Column role="list">
    <Text role="listitem">Item 1</Text>
    <Text role="listitem">Item 2</Text>
</Column>

<!-- Slider with label and description -->
<Slider aria-label="Volume" aria-description="Volume (0-100%)" min="0" max="100" />

<!-- Region landmarks -->
<Header role="region" aria-label="Application header">
    ...
</Header>
<Footer role="region" aria-label="Application footer">
    ...
</Footer>
```

### Module 07 integration — `Scene.instantiate()`

When an element is instantiated from a `NodeDesc`:

1. **Determine role:**
   - If `NodeDesc.role` is non-empty, parse it and use the resulting `AccessRole`.
   - If `NodeDesc.role` is empty, use `defaultAccessRoleFor(kind)` (from RG1).
   - Call `Scene.setAccessRole(idx, role)`.

2. **Determine name (label):**
   - If `NodeDesc.aria_label` is non-empty, use it as the name.
   - Else if the element has text content (e.g. `<Button>Save</Button>`), use that.
   - Else if the element has a label slot child (e.g. `<Checkbox label="Agree">`), extract the label child's text.
   - Else use empty string.
   - Call `Scene.setAccessName(idx, name)`.

3. **Determine description:**
   - If `NodeDesc.aria_description` is non-empty, use it.
   - Else use empty string.
   - Call `Scene.setAccessDescription(idx, desc)`.

Example in `instantiateNode()`:

```zig
// Determine accessibility role
const access_role = if (node.role.len > 0) 
    parseRole(node.role) 
else 
    defaultAccessRoleFor(kind);

scene.setAccessRole(idx, access_role);

// Determine name
const access_name = if (node.aria_label.len > 0)
    node.aria_label
else if (node.text.len > 0)
    node.text
else
    "";

scene.setAccessName(idx, try arena.dupe(u8, access_name));

// Determine description
const access_desc = node.aria_description;
if (access_desc.len > 0) {
    scene.setAccessDescription(idx, try arena.dupe(u8, access_desc));
}
```

### Glossary entry — `docs/specs/glossary.md`

Add entries for the new attributes:

```
## aria-label

An accessibility attribute (M17-04) that assigns a human-readable label to an element.
Parsed from markup as `aria-label="text"` and stored in `AccessNode.name`. Takes precedence
over the element's text content when both are present. Used by screen readers to identify
interactive widgets and regions.

See: M17-04 (RG4), `src/06/types.zig` NodeDesc.aria_label, `src/07/types.zig` AccessNode.name.

---

## aria-description

An accessibility attribute (M17-04) that assigns a longer description to an element.
Parsed from markup as `aria-description="text"` and stored in `AccessNode.description`.
Used by screen readers to provide context or instructions. May be omitted if empty.

See: M17-04 (RG4), `src/06/types.zig` NodeDesc.aria_description, `src/07/types.zig` AccessNode.description.

---

## role= (accessibility attribute)

An accessibility attribute (M17-04) that overrides the semantic role of an element.
Parsed from markup as `role="button"`, `role="list"`, etc., and stored in `AccessNode.role`.
Valid values are the `AccessRole` enum variants. If invalid, a `ParseDiagnostic` is emitted.
When absent, the role is inferred from the element's `WidgetKind` via `defaultAccessRoleFor()`.

See: M17-04 (RG4), M17-01 (RG1), `src/06/types.zig` NodeDesc.role, `src/06/parser.zig` parseRole().
```

## Non-goals (DO NOT implement — INV-5.4)

- **No aria-\* attributes beyond aria-label and aria-description.** aria-live, aria-controls, aria-owns, aria-current, etc., are post-v1.
- **No role validation in the renderer.** If an invalid role is specified, the parser catches it and emits a diagnostic; the renderer does NOT validate roles at runtime.
- **No automatic role inference from child elements.** Only explicit `role=` attributes or kind-based defaults are used.
- **No attribute translation.** aria-label is not automatically transformed from other attributes (e.g. title, placeholder).
- **No macOS or other platform support.** This is a markup feature for all platforms, but the bridges (RG2, RG3) are Windows/Linux only.

## Acceptance criteria

1. `NodeDesc` struct gains `role`, `aria_label`, `aria_description` fields (all `[]const u8`, default empty).
2. The `.ui` parser recognizes `role=`, `aria-label=`, and `aria-description=` attributes on any element.
3. Parser stores the attribute values into `NodeDesc` without modification (no escaping required; they are plain strings).
4. Parser validates `role=` values against the `AccessRole` enum and emits a `ParseDiagnostic` with source location if invalid.
5. `Scene.instantiate()` reads these attributes from `NodeDesc` and populates `AccessNode` via:
   - `setAccessRole()` with the parsed role (or kind-based default).
   - `setAccessName()` with aria-label (or element text, or label slot).
   - `setAccessDescription()` with aria-description.
6. The three attributes do NOT appear in resolved `ComputedStyle` or affect layout/rendering. They are accessibility-only.
7. Unit tests cover:
   - Parsing valid role values (e.g. "button", "list", "none").
   - Parsing invalid role values and catching the diagnostic.
   - Parsing aria-label and aria-description on various element kinds.
   - Scene.instantiate() correctly reads the attributes and populates AccessNode.
   - Name resolution priority: aria-label > text content > label slot.
   - Attributes are arena-allocated and released on scene reset.
8. Examples in `docs/requirements/DEMO_APP.md` show at least three accessibility patterns:
   - Custom button with `role="button"`.
   - Input with `aria-label=` and `aria-description=`.
   - List region with role="list" and role="listitem" children.
9. No Zig compiler errors or warnings.
10. Hot-reload (if enabled) correctly re-parses changed role/aria attributes.

## Open questions

None. The feature is scoped: parse three attributes, store them in NodeDesc, use them in Scene.instantiate(). The bridges (RG2, RG3) are responsible for exposing these to the OS accessibility APIs.
