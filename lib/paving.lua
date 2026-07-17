-- Shared between data-final-fixes.lua (data stage) and control.lua (runtime).
-- Data stage sees tile references (`place_as_tile.result`/`tile_condition`,
-- `thawed_variant`) as plain tile-name strings; runtime sees them as
-- LuaTilePrototype objects. `normalize` and `normalize_tile` flatten both
-- stages' shapes into plain-string forms via the caller-supplied `name_of`,
-- so `matches` itself never touches either stage's globals and can be
-- required from both.
local paving = {}

paving.tool_prefix = "select-and-pave-tool-"

local function tile_condition_names_of(tile_condition, name_of)
  if not (tile_condition and #tile_condition > 0) then
    return nil
  end

  local names = {}
  for _, tile_ref in pairs(tile_condition) do
    names[name_of(tile_ref)] = true
  end
  return names
end

--- @param place_as_tile table data-stage `PlaceAsTile` or runtime `PlaceAsTileResult`
--- @param name_of function extracts a plain tile-name string from a tile reference
function paving.normalize(place_as_tile, name_of)
  return {
    result_name = name_of(place_as_tile.result),
    condition_layers = place_as_tile.condition and place_as_tile.condition.layers,
    invert = place_as_tile.invert,
    tile_condition_names = tile_condition_names_of(place_as_tile.tile_condition, name_of),
  }
end

--- Flattens a tile prototype (data-stage table or runtime LuaTilePrototype)
--- into the plain descriptor `matches` takes: the tile's name, its
--- collision-mask layers (nil when the prototype has no mask), and the name
--- of the tile it thaws into if frozen (nil otherwise).
--- @param tile_prototype table data-stage tile prototype or runtime LuaTilePrototype
--- @param name_of function extracts a plain tile-name string from a tile reference
function paving.normalize_tile(tile_prototype, name_of)
  local mask = tile_prototype.collision_mask
  local thawed = tile_prototype.thawed_variant
  return {
    name = tile_prototype.name,
    layers = mask and mask.layers,
    thawed_name = thawed and name_of(thawed),
  }
end

local function layers_intersect(condition_layers, collision_mask_layers)
  if not collision_mask_layers then
    return false
  end
  for layer in pairs(condition_layers) do
    if collision_mask_layers[layer] then
      return true
    end
  end
  return false
end

--- Whether a normalized place_as_tile's collision-mask condition references
--- `layer` at all (regardless of `invert`). Used to recognize items that are
--- specifically designed around a special-purpose layer (e.g. "empty_space"
--- for space platforms) as opposed to items whose rule simply never
--- mentions it and so can't be assumed valid there.
function paving.condition_references(normalized, layer)
  return normalized.condition_layers ~= nil and normalized.condition_layers[layer] == true
end

--- Whether a normalized place_as_tile allows its result tile to be placed
--- over `tile`, a descriptor from `normalize_tile`. A frozen tile whose
--- `thawed_name` is the item's own result (e.g. Aquilo's frozen-concrete
--- thaws into concrete) counts as already paved too, since re-placing it
--- under drag-select just spends the item on a thaw that has no heat
--- source to hold, and will refreeze right back.
---
--- Known limitation: the engine evaluates `condition` over a square of
--- `place_as_tile.condition_size` tiles around the position; this
--- reimplementation checks only the single tile. Vanilla items all use
--- size 1, but a modded item with a larger radius will diverge here.
--- Runtime checks against a real map position therefore go through the
--- engine instead (control.lua's can_place_tile_ghost); this function
--- remains for data-stage filters and prototype-vs-prototype checks,
--- where no position exists to ask the engine about.
function paving.matches(normalized, tile)
  if tile.name == normalized.result_name or tile.thawed_name == normalized.result_name then
    return false -- already paved
  end

  if normalized.tile_condition_names and not normalized.tile_condition_names[tile.name] then
    return false
  end

  if not normalized.condition_layers then
    return true
  end

  local intersects = layers_intersect(normalized.condition_layers, tile.layers)

  -- `condition` names layers this item's tile is blocked by default (e.g.
  -- concrete's "water-tile"); `invert` flips it into an allowlist (e.g.
  -- landfill's "only valid where this matches").
  if normalized.invert then
    return intersects
  end
  return not intersects
end

return paving
