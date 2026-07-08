# Entity Variant Properties — Design Spec

**Date:** 2026-07-08
**Status:** Approved
**Engine:** Godot 4.7 (stable)
**Language:** GDScript

## 1. Overview

Some sprite entities ship multiple visual variants in one `.tscn` and the
level author must choose which variant a placed instance shows. The motivating
case is `assets/sprites/Spike.tscn`, whose root `Node2D` holds two
`AnimatedSprite2D` children — `"Spike Right"` (visible by default) and
`"SpikeLeft"` (hidden) — representing right-facing and left-facing spikes.

Rather than a spike-specific hack, this spec fills in the **property schema**
the original design (`2026-06-25-keen-reloaded-design.md` §6.3) already
specified but never wired: registry entries declare a `properties` schema of
`{name, default, type}`; the inspector renders editors from that schema; and
`SpriteEntity` applies a generic "variant" rule so any multi-variant sprite
works with no per-sprite code. The mechanism is general (any enum property on
any entity), but only the spike uses it today.

### Requirements

| # | Requirement |
|---|-------------|
| 1 | A placed spike's facing (`right` / `left`) is selectable in the inspector and persists in the `.tres`. |
| 2 | Variant selection is general: declaring an `enum` property on any registered entity yields an `OptionButton` in the inspector and drives visual selection at runtime — no per-entity code. |
| 3 | Property data is self-describing: a placed `EntityDef` carries its full property set (with schema defaults seeded at placement), so the runtime is schema-agnostic. |
| 4 | Existing scripted entities (vorticon, yorp, …) with empty schemas are unchanged in palette, placement, and spawn. |
| 5 | The editor canvas identifies a placed entity's variant at a glance (label suffix). |
| 6 | All existing GUT tests pass; new tests cover schema, inspector writeback, variant visibility, and spike registration. |

### Out of scope

- **Sprite-thumbnail rendering** in the editor canvas (still rect + label;
  tracked as deferred in `2026-07-03-sprite-backed-entities-design.md` §8).
- **Non-visual enum properties** (e.g. gameplay tuning enums). The schema
  supports them, but `SpriteEntity`'s variant rule is the only consumer of
  enum values today; scripted entities that want enum-driven behavior read
  `properties` themselves via the existing `Entity.setup` binding.
- **Migrating existing entities** to declare schemas. All current registrations
  keep `properties = []`.
- **Per-cell multi-placement / drag-rotate** of variants.

## 2. Background — the gap this closes

The design doc (`2026-06-25-keen-reloaded-design.md` line 214) specified
registry entries as:

```
properties: [{ name, default, type }]
```

but the implementation stopped short:

- `EntityRegistry.register(...)` / `register_sprite(...)` accept a `properties`
  Array and store it on the entry, but **every existing registration passes
  `[]`**, so the schema is unused.
- `EntityDef.properties` (`src/data/entity_def.gd:9`) is a per-instance
  `Dictionary` of overrides.
- `InspectorPanel._rebuild_entity_box` (`src/editor/inspector_panel.gd:91`)
  iterates `ent.properties.keys()` — i.e. it renders editors only for keys that
  already exist on the instance, typed by `typeof(val)`. There is **no
  OptionButton / enum path**, and no schema is consulted.
- `LevelEditor._place_entity` (`src/editor/level_editor.gd:251`) creates
  `EntityDef.new(type, x, y)` with an empty `properties` dict, so a freshly
  placed entity has no property keys at all → nothing renders.
- `SpriteEntity.setup` (`src/runtime/entities/sprite_entity.gd:15`) stores
  `properties` but never applies them to its wrapped visual.

Net: the data plumbing exists end-to-end, but nothing populates or consumes a
schema. This spec activates it, adding only the enum case (the one variant
selection needs).

## 3. Property schema model

### 3.1 Schema entry shape

A registry entry's `properties` Array contains schema dictionaries:

```gdscript
{
    "name": String,          # property key, also the EntityDef.properties key
    "default": Variant,      # seeded into EntityDef.properties on placement
    "type": String,          # "int" | "bool" | "string" | "enum"
    "options": Array[String] # required when type == "enum"; else omitted
}
```

Constraints:

- For `type == "enum"`, `options` is non-empty and `default` must be a member
  of `options`. Registration validates this and `push_warning`s (does not
  crash) on violation, falling back to `options[0]`.
- `int` covers both int and float instance values (the inspector already maps
  both to a SpinBox); `default` is an int for `int`.

### 3.2 Where the schema lives

Unchanged: `register()` / `register_sprite()` already store the `properties`
Array on the entry (`src/core/entity_registry.gd:17`, `:34`). No signature
change. Both entry points gain one guard: for each schema entry with
`type == "enum"`, if `default` is not in `options` (or `options` is empty),
`push_warning` and coerce `default` to `options[0]` (no crash). A new helper
retrieves the (possibly coerced) schema:

```gdscript
func get_properties_schema(type_id: String) -> Array:
    return Array(_entries.get(type_id, {}).get("properties", []))
```

## 4. Placement seeds defaults

File: `src/editor/level_editor.gd`, `_place_entity` (line 251).

Today:

```gdscript
undo_stack.execute(level, AddEntityCmd.new(EntityDef.new(selected_entity_type, cell.x, cell.y)))
```

Change: build the properties dict from the schema defaults before constructing
the `EntityDef`:

```gdscript
var props := _default_properties(selected_entity_type)
undo_stack.execute(level, AddEntityCmd.new(
    EntityDef.new(selected_entity_type, cell.x, cell.y, props)))
```

with

```gdscript
func _default_properties(type_id: String) -> Dictionary:
    var out: Dictionary = {}
    for entry in EntityRegistry.get_properties_schema(type_id):
        var n: String = String(entry.get("name", ""))
        if n == "":
            continue
        out[n] = entry.get("default", null)
    return out
```

Rationale: the placed `EntityDef` becomes self-describing. Runtime reads
`def.properties` only — it never consults the registry schema, so old saves
and hand-edited `.tres` files keep working, and the runtime stays decoupled
from editor-side schema knowledge. `keen1.player_spawn` placement
(`set_selected_entity_type == "keen1.player_spawn"` special case) is
unaffected — it has an empty schema.

## 5. Schema-driven inspector (schema-first, instance-key fallback)

File: `src/editor/inspector_panel.gd`, `_rebuild_entity_box` (line 91).

Today the loop is `for key in ent.properties.keys()`, typed by `typeof(val)`.
That loop is what makes `keen1.level_entrance` editable: its registration has
an empty schema, but its instances carry `target_level_id` (String) and
`blocks_until_completed` (bool) — `test_editor_map_kind.gd:55` places such an
instance and asserts the inspector renders `Prop_target_level_id` /
`Prop_blocks_until_completed`. A purely schema-driven switch would regress
that. So the new render order is **schema-first, then instance-key fallback**:

1. Render one control per schema entry (using the schema `type`), reading the
   value from `ent.properties[key]` with the schema `default` as fallback.
2. Then render a control for any instance key **not** already covered by the
   schema, using the existing `typeof`-based construction (the current code
   path, unchanged).

```gdscript
var schema := EntityRegistry.get_properties_schema(ent.type)
var covered: Dictionary = {}   # key -> true, for the fallback pass
# 1. schema-driven controls
for s in schema:
    var key: String = String(s.get("name", ""))
    if key == "":
        continue
    covered[key] = true
    var val = ent.properties.get(key, s.get("default"))
    match String(s.get("type", "")):
        "enum":
            var options: Array = s.get("options", [])
            var ob := OptionButton.new()
            ob.name = "Prop_" + key
            for opt in options:
                ob.add_item(String(opt))
            var idx := options.find(val)
            ob.select(idx if idx >= 0 else 0)
            var k_enum: Variant = key
            ob.item_selected.connect(func(i: int) -> void:
                ent.properties[k_enum] = options[i])
            _entity_box.add_child(_labeled(key, ob))
        "bool":
            # existing CheckBox branch, val-sourced, name = "Prop_" + key
            ...
        "int":
            # existing SpinBox branch, val-sourced, name = "Prop_" + key
            ...
        _:
            # "string" / unknown → existing LineEdit branch
            ...
# 2. instance-key fallback (keys present on the entity but not in schema)
for key in ent.properties.keys():
    if covered.has(key):
        continue
    # existing typeof branch: TYPE_INT/TYPE_FLOAT → SpinBox,
    # TYPE_BOOL → CheckBox, TYPE_STRING → LineEdit (unchanged)
    ...
```

Details:

- The X / Y SpinBoxes and the `Delete entity` button are unchanged.
- Control nodes keep the existing `name = "Prop_" + key` convention so
  `find_child("Prop_target_level_id")` (and new spike tests) still resolve.
- `enum` is the only new `match` arm; `int`/`bool`/`string` reuse the existing
  control construction verbatim, just re-sourced from schema + instance value.
- The label is the property `name` (e.g. `facing`). Capitalization is left to
  Godot's display; no extra metadata needed for v1.
- **Backward compatibility:** `keen1.level_entrance` (empty schema, instance
  keys) is rendered entirely by the fallback pass — identical to today, so
  `test_editor_map_kind.gd` passes unchanged. Entities with an empty schema
  and empty instance properties render nothing (unchanged).

## 6. SpriteEntity variant application

File: `src/runtime/entities/sprite_entity.gd`, `setup` (line 15).

Add a generic variant rule applied after the children are attached (they are —
`EntityRegistry.instantiate` calls `attach_sprite` before `setup`):

```gdscript
func setup(p_type_id: String, p_props: Dictionary = {}) -> void:
    type_id = p_type_id
    properties = p_props
    _apply_variant_properties()
```

`_apply_variant_properties` iterates the registry schema for `type_id`; for
each `enum` property it selects which descendant CanvasItem is visible:

```gdscript
func _apply_variant_properties() -> void:
    for s in EntityRegistry.get_properties_schema(type_id):
        if String(s.get("type", "")) != "enum":
            continue
        var options: Array = s.get("options", [])
        if options.is_empty():
            continue
        var key: String = String(s.get("name", ""))
        var val := String(properties.get(key, s.get("default", "")))
        _select_variant_child(options, val)

## Variant group = the set of descendant CanvasItems whose node names contain
## an enum option (case-insensitive). Show the one whose option == val; hide
## the rest. Descendants not matching any option are left untouched. Descendant
## walk is required because attach_sprite() adds the sprite scene's root as the
## wrapper's only child, so the variant sprites are grandchildren (e.g. the
## spike's `"Spike Right"` / `"SpikeLeft"` live under the `"Spike"` root).
func _select_variant_child(options: Array, val: String) -> void:
    var want := val.to_lower()
    var matched: CanvasItem = null
    var to_hide: Array[CanvasItem] = []
    for c in _descendants(self):
        if not (c is CanvasItem):
            continue
        var nm := String(c.name).to_lower()
        for o in options:
            if nm.contains(String(o).to_lower()):
                if String(o).to_lower() == want:
                    matched = c
                else:
                    to_hide.append(c)
                break
    for c in to_hide:
        c.visible = false
    if matched != null:
        matched.visible = true

func _descendants(n: Node) -> Array[Node]:
    var out: Array[Node] = []
    for c in n.get_children():
        out.append(c)
        out.append_array(_descendants(c))
    return out
```

### Convention (documented)

A sprite with N visual variants authors N sibling `CanvasItem` nodes anywhere
in the wrapped scene's subtree whose **node names contain their enum option
value** (case-insensitive). Exactly one should be visible in the `.tscn` (the
default); `SpriteEntity` enforces the rest at runtime by walking descendants
and toggling `.visible`.

For the spike this holds with **zero node renames**:

- option `"right"` → child `"Spike Right"` (`.to_lower()` = `"spike right"`,
  contains `"right"`) — matched when `val == "right"`.
- option `"left"` → child `"SpikeLeft"` (`.to_lower()` = `"spikeleft"`,
  contains `"left"`) — matched when `val == "left"`.

Ambiguity caveat: do not name sibling variant children so that one option
value is a substring of another child's name (e.g. options `["right",
"topright"]` with children named `"Right"` / `"TopRight"`). The first
option-level match wins; keep option values mutually non-substring, or make
child names exactly the option value. Documented in the class docstring.

`SpriteEntity` remains collision-free, AI-free, signal-free — it only toggles
`.visible` on its own children.

## 7. Spike registration

File: `src/episodes/keen1/episode.gd`, `register_entities` (line 12).

Add:

```gdscript
registry.register_sprite("keen1.spike", registry.CATEGORY_HAZARD, "Spike",
    "res://assets/sprites/Spike.tscn",
    [{name = "facing", default = "right", type = "enum",
      options = ["right", "left"]}])
```

Notes:

- `CATEGORY_HAZARD` — a spike is lethal on contact. Pure-visual today (no
  damage script — see §9 future), but categorized as a hazard so the palette
  groups it correctly and future gameplay wiring finds it.
- Default `"right"` matches the `.tscn`'s visible child, so an unedited placed
  spike renders exactly as the authored scene.
- The spike's existing children (`"Spike Right"`, `"SpikeLeft"`) satisfy the
  §6 convention with no edits to `Spike.tscn`.

## 8. Editor canvas label (polish)

File: `src/editor/canvas_editor.gd`, entity draw loop (line 73).

Today each entity renders as an orange rect plus a `draw_string` of `e.type`
(line 76). Append **enum variant values** (schema-driven) so variants are
identifiable at design time — the canvas still draws rects, not sprites, so
this is the cheapest useful signal:

```gdscript
var label := e.type
for s in EntityRegistry.get_properties_schema(e.type):
    if String(s.get("type", "")) != "enum":
        continue
    var k: String = String(s.get("name", ""))
    var v := String(e.properties.get(k, s.get("default", "")))
    if v != "":
        label = "%s (%s)" % [label, v]
draw_string(..., label, ...)
```

Restricted to enum schema properties (not all instance properties) so the
suffix is deterministic and variant-focused: a placed spike reads
`keen1.spike (right)` / `keen1.spike (left)`. Entities with no enum schema
entries (everything else today, including `keen1.level_entrance`) get no
suffix — unchanged.

## 9. Deferred / future

- **Spike damage.** This spec makes the spike *placeable and variant-aware*
  only. Lethal-on-contact behavior is out of scope; the spike currently has no
  script and deals no damage. A follow-up can attach a hazard script
  (`extends Hazard`) or wrap via `register()` once gameplay is needed.
- **Sprite-thumbnail canvas rendering.** Still rect + label; see
  `2026-07-03-sprite-backed-entities-design.md` §8.
- **Richer property metadata** (display labels, ranges, tooltips). The schema
  carries only what variant selection needs today; extend per-requirement.
- **Enum-driven behavior on scripted entities.** `Entity.setup` already binds
  matching `properties` keys onto instance vars (`entity.gd:26-28`), so a
  scripted entity reading an enum value works without changes — just declare
  the schema and consume the bound var.
- **Backfill `keen1.level_entrance` schema.** Its `target_level_id` (String)
  and `blocks_until_completed` (bool) are currently rendered only via the §5
  instance-key fallback (so a *placed* entrance has no property UI until keys
  exist). Declaring a schema for it would make placement seed defaults and
  surface controls immediately. Out of scope here — it works today via the
  fallback for pre-seeded / hand-authored instances; backfilling is a separate
  ergonomic improvement.

## 10. Testing

### Unit (`tests/unit/`)

- **Schema retrieval:** `get_properties_schema` returns the declared Array for
  a registered type and `[]` for unknown / empty-schema types.
- **Enum validation:** registering an enum whose `default` is not in `options`
  warns and falls back to `options[0]` (does not crash).
- **Placement seeding:** after `_place_entity` for `keen1.spike`, the appended
  `EntityDef.properties == {"facing": "right"}`. An empty-schema type (e.g.
  `keen1.vorticon`) places with `{}`.
- **Inspector enum writeback:** selecting an entity and changing the `facing`
  OptionButton writes the chosen option into `ent.properties["facing"]`.
- **SpriteEntity variant visibility:** instantiate `keen1.spike` with
  `{facing:"right"}` → child `"Spike Right"` visible, `"SpikeLeft"` hidden;
  with `{facing:"left"}` → inverse; with `{}` (no key) → schema default
  `"right"` applies.
- **Spike registration:** `keen1.spike` is in `get_palette_entries()` under
  `CATEGORY_HAZARD` with the expected schema; `instantiate` returns a
  `SpriteEntity` at the requested position in group `"entity"`.
- **No regression:** existing scripted entities (`keen1.yorp`) instantiate
  unchanged and are not wrapped in `SpriteEntity`; their (empty) schema
  produces no inspector controls.

### Existing tests

`test_sprite_entity.gd`, `test_entity_registry_instantiate.gd`,
`test_episode.gd`, `test_editor_workflow.gd`, and `test_editor_map_kind.gd`
must pass unchanged. The schema-driven inspector (§5) preserves the
instance-key fallback path, so `test_editor_map_kind.gd`'s
`Prop_target_level_id` / `Prop_blocks_until_completed` assertions still hold
(level_entrance has an empty schema → rendered by the fallback). Existing
registrations stay `[]`, so assertions on empty `properties` arrays hold.

### Manual

Editor: select the Entity tool, pick `Spike` from the palette (Hazards group),
place a cell → inspector shows a `facing` OptionButton defaulting to `right`;
switch to `left` → the canvas label updates to `keen1.spike (left)`. Save →
reopen the `.tres`: the `EntityDef` round-trips with `facing` intact. Test ▶:
the placed spike renders with the chosen facing.

Run `./tests/run_all.sh` after changes — must pass before commit.
