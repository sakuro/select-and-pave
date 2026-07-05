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

local function identity(value)
  return value
end

for name, item in pairs(data.raw.item) do
  local place_as_tile = item.place_as_tile
  if place_as_tile then
    local normalized = paving.normalize(place_as_tile, identity)

    -- Precomputes which existing tiles this item could ever pave, so the
    -- normal-select mode only reports (and lets the engine's built-in
    -- counter count) tiles that are actually valid targets.
    local tile_filters = {}
    for tile_name, tile_prototype in pairs(data.raw.tile) do
      local mask = tile_prototype.collision_mask
      if paving.matches(tile_name, mask and mask.layers, normalized) then
        tile_filters[#tile_filters + 1] = tile_name
      end
    end

    local selection_tool = {
      type = "selection-tool",
      name = paving.tool_prefix .. name,
      localised_name = {"item-name." .. name},
      flags = {"only-in-cursor", "not-stackable"},
      hidden = true,
      stack_size = 1,
      select = {
        mode = {"any-tile"},
        tile_filters = tile_filters,
        tile_filter_mode = "whitelist",
        cursor_box_type = "copy",
        border_color = {r = 0.9, g = 0.7, b = 0.2},
        count_button_color = {r = 0.9, g = 0.7, b = 0.2},
      },
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
end
