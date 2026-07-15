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

--- Defines a `select-and-pave-tool-<name>` selection-tool prototype for
--- `item`, if it has `place_as_tile`. No-op otherwise.
local function define_selection_tool(name, item)
  local place_as_tile = item.place_as_tile
  if not place_as_tile then
    return
  end

  local function identity(value)
    return value
  end

  local normalized = paving.normalize(place_as_tile, identity)

  -- Precomputes which existing tiles this item could ever pave, so the
  -- normal-select mode only reports (and lets the engine's built-in
  -- counter count) tiles that are actually valid targets.
  local tile_filters = {}
  for tile_name, tile_prototype in pairs(data.raw.tile) do
    local mask = tile_prototype.collision_mask
    if paving.matches(tile_name, mask and mask.layers, normalized, tile_prototype.thawed_variant) then
      tile_filters[#tile_filters + 1] = tile_name
    end
  end

  local select = {
    mode = {"any-tile"},
    cursor_box_type = "copy",
    border_color = {r = 0.9, g = 0.7, b = 0.2},
    count_button_color = {r = 0.9, g = 0.7, b = 0.2},
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

  local selection_tool = {
    type = "selection-tool",
    name = paving.tool_prefix .. name,
    localised_name = item.localised_name or {"item-name." .. name},
    flags = {"only-in-cursor", "not-stackable"},
    hidden = true,
    stack_size = 1,
    select = select,
    alt_select = {
      -- Deliberately unfiltered: alt-select's whole purpose is to also
      -- catch tiles the normal whitelist above excludes.
      mode = {"any-tile"},
      cursor_box_type = "copy",
      border_color = {r = 0.3, g = 0.6, b = 0.9},
    },
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
      paving_candidates[#paving_candidates + 1] = {name = name, item = prototype}
    end
  end
end

for _, candidate in pairs(paving_candidates) do
  define_selection_tool(candidate.name, candidate.item)
end
