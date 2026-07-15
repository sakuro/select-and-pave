-- Shared between data-final-fixes.lua (data stage) and control.lua (runtime).
-- Data stage sees `place_as_tile.result`/`tile_condition` as plain tile-name
-- strings; runtime sees `place_as_tile_result.result`/`tile_condition` as
-- LuaTilePrototype objects. `normalize` flattens both into plain strings via
-- the caller-supplied `name_of`, so `matches` itself never touches either
-- stage's globals and can be required from both.
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
--- over a tile named `tile_name` with collision mask layers
--- `collision_mask_layers` (a set of layer-name -> true, or nil).
--- `thawed_name`, if given, is the tile `tile_name` thaws into (e.g.
--- Aquilo's frozen-concrete thaws into concrete) -- a frozen tile counts as
--- already paved too, since re-placing it under drag-select just spends the
--- item on a thaw that has no heat source to hold, and will refreeze right
--- back.
function paving.matches(tile_name, collision_mask_layers, normalized, thawed_name)
  if tile_name == normalized.result_name or thawed_name == normalized.result_name then
    return false -- already paved
  end

  if normalized.tile_condition_names and not normalized.tile_condition_names[tile_name] then
    return false
  end

  if not normalized.condition_layers then
    return true
  end

  local intersects = layers_intersect(normalized.condition_layers, collision_mask_layers)

  -- `condition` names layers this item's tile is blocked by default (e.g.
  -- concrete's "water-tile"); `invert` flips it into an allowlist (e.g.
  -- landfill's "only valid where this matches").
  if normalized.invert then
    return intersects
  end
  return not intersects
end

return paving
