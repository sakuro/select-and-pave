-- Shared between data-final-fixes.lua (data stage) and control.lua (runtime).
-- Data stage sees `place_as_tile.result`/`tile_condition` as plain tile-name
-- strings; runtime sees `place_as_tile_result.result`/`tile_condition` as
-- LuaTilePrototype objects. `normalize` flattens both into plain strings via
-- the caller-supplied `name_of`, so `matches` itself never touches either
-- stage's globals and can be required from both.
local paving = {}

paving.tool_prefix = "select-and-pave-tool-"

--- @param place_as_tile table data-stage `PlaceAsTile` or runtime `PlaceAsTileResult`
--- @param name_of function extracts a plain tile-name string from a tile reference
function paving.normalize(place_as_tile, name_of)
  local tile_condition_names
  if place_as_tile.tile_condition and #place_as_tile.tile_condition > 0 then
    tile_condition_names = {}
    for _, tile_ref in pairs(place_as_tile.tile_condition) do
      tile_condition_names[name_of(tile_ref)] = true
    end
  end

  return {
    result_name = name_of(place_as_tile.result),
    condition_layers = place_as_tile.condition and place_as_tile.condition.layers,
    invert = place_as_tile.invert,
    tile_condition_names = tile_condition_names,
  }
end

--- Whether a normalized place_as_tile allows its result tile to be placed
--- over a tile named `tile_name` with collision mask layers
--- `collision_mask_layers` (a set of layer-name -> true, or nil).
function paving.matches(tile_name, collision_mask_layers, normalized)
  if tile_name == normalized.result_name then
    return false -- already paved
  end

  if normalized.tile_condition_names and not normalized.tile_condition_names[tile_name] then
    return false
  end

  if not normalized.condition_layers then
    return true
  end

  local intersects = false
  if collision_mask_layers then
    for layer in pairs(normalized.condition_layers) do
      if collision_mask_layers[layer] then
        intersects = true
        break
      end
    end
  end

  -- `condition` names layers this item's tile is blocked by default (e.g.
  -- concrete's "water-tile"); `invert` flips it into an allowlist (e.g.
  -- landfill's "only valid where this matches").
  if normalized.invert then
    return intersects
  end
  return not intersects
end

return paving
