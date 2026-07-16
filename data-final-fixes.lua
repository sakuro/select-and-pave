-- Runs after every MOD's data.lua/data-updates.lua, so `data.raw.item` and
-- `data.raw.tile` are complete regardless of MOD load order (no dependency
-- on any specific paving-item MOD is needed).
local paving = require("lib.paving")

local function icon_fields(item)
  if item.icons then
    return {icons = item.icons}
  end
  return {icon = item.icon, icon_size = item.icon_size}
end

-- Data-stage tile references are already plain name strings.
local function identity(value)
  return value
end

local function matches_tile(tile_name, tile_prototype, normalized)
  local mask = tile_prototype.collision_mask
  return paving.matches(tile_name, mask and mask.layers, normalized, tile_prototype.thawed_variant)
end

--- Defines a `select-and-pave-tool-<name>` selection-tool prototype for
--- `candidate`. `candidates` is the full list of place_as_tile items, used
--- to work out which tiles some underlay could make paveable.
local function define_selection_tool(candidate, candidates)
  local name, item, normalized = candidate.name, candidate.item, candidate.normalized

  -- Items whose result tile exists and accepts this item on top, i.e.
  -- whatever control.lua's choose_underlay could ever pick for it. (Never
  -- the item itself: matches() rejects placing a tile on its own result.)
  local underlay_normals = {}
  for _, other in pairs(candidates) do
    local result_name = other.normalized.result_name
    local result_prototype = data.raw.tile[result_name]
    if result_prototype and matches_tile(result_name, result_prototype, normalized) then
      underlay_normals[#underlay_normals + 1] = other.normalized
    end
  end

  -- Precomputes which existing tiles this item could ever pave, directly
  -- (tile_filters -- the normal-select whitelist) or with an underlay in
  -- between (alt_tile_filters -- a superset of it), so each mode's native
  -- counter only counts tiles that are actual targets for that mode.
  -- Research state and platform restrictions are runtime concerns that
  -- control.lua re-checks, so the alt counter still overcounts tiles whose
  -- only underlay isn't obtainable yet. Tiles already paved with (or frozen
  -- and thawing back into) this item's result get no underlay, mirroring
  -- control.lua's is_already_paved.
  local tile_filters = {}
  local alt_tile_filters = {}
  for tile_name, tile_prototype in pairs(data.raw.tile) do
    if matches_tile(tile_name, tile_prototype, normalized) then
      tile_filters[#tile_filters + 1] = tile_name
      alt_tile_filters[#alt_tile_filters + 1] = tile_name
    elseif tile_name ~= normalized.result_name
      and tile_prototype.thawed_variant ~= normalized.result_name then
      for _, underlay_normalized in pairs(underlay_normals) do
        if matches_tile(tile_name, tile_prototype, underlay_normalized) then
          alt_tile_filters[#alt_tile_filters + 1] = tile_name
          break
        end
      end
    end
  end

  -- No count_button_color: the engine shows no tile-count badge for modes
  -- with tile_filters set (observed in 2.0 -- unfiltered modes count every
  -- tile in the drag box, filtered ones display nothing), so there is no
  -- counter to color. The badge can't be made to show a paveable-tile count.
  local select = {
    mode = {"any-tile"},
    cursor_box_type = "copy",
    border_color = {r = 0.9, g = 0.7, b = 0.2},
  }
  local alt_select = {
    mode = {"any-tile"},
    cursor_box_type = "copy",
    border_color = {r = 0.3, g = 0.6, b = 0.9},
  }
  -- An empty whitelist is treated as "no filter" by the engine, which would
  -- silently make the native counter report every tile in the drag box
  -- instead of zero; leaving tile_filters/tile_filter_mode unset in that
  -- case is equally harmless (control.lua re-checks placeability at
  -- runtime regardless) but doesn't claim a precision we don't have.
  if #tile_filters > 0 then
    select.tile_filters = tile_filters
    select.tile_filter_mode = "whitelist"
  end
  if #alt_tile_filters > 0 then
    alt_select.tile_filters = alt_tile_filters
    alt_select.tile_filter_mode = "whitelist"
  end

  local selection_tool = {
    type = "selection-tool",
    name = paving.tool_prefix .. name,
    localised_name = item.localised_name or {"item-name." .. name},
    flags = {"only-in-cursor", "not-stackable"},
    hidden = true,
    stack_size = 1,
    select = select,
    alt_select = alt_select,
  }
  for key, value in pairs(icon_fields(item)) do
    selection_tool[key] = value
  end

  data:extend({selection_tool})
end

-- Collects every place_as_tile item across all of data.raw (not just
-- data.raw.item), since `place_as_tile` is a base ItemPrototype field usable
-- by any item subtype (tool, capsule, item-with-tags, ...), and control.lua's
-- runtime `prototypes.item` scan (see get_paving_items in control.lua) covers
-- all of them too. Restricting this to data.raw.item would let control.lua
-- recognize a paving item that has no matching tool prototype here, crashing
-- `player.cursor_stack.set_stack` in activate().
--
-- Collected into a plain list first, rather than calling define_selection_tool
-- (which calls data:extend, mutating data.raw) while still iterating over
-- data.raw itself, since mutating a table mid-`pairs` is undefined behavior.
local paving_candidates = {}
for _, group in pairs(data.raw) do
  for name, prototype in pairs(group) do
    if prototype.place_as_tile then
      paving_candidates[#paving_candidates + 1] = {
        name = name,
        item = prototype,
        normalized = paving.normalize(prototype.place_as_tile, identity),
      }
    end
  end
end

for _, candidate in pairs(paving_candidates) do
  define_selection_tool(candidate, paving_candidates)
end
