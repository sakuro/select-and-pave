local shortcut_name = "select-and-pave-activate"
local custom_input_name = "select-and-pave-activate-input"
local next_item_input_name = "select-and-pave-next-item"
local previous_item_input_name = "select-and-pave-previous-item"

-- Fixed shortcut-bar icon; the per-item selection tools defined in
-- data-final-fixes.lua get their icon from the paving item they represent.
local icon = "__select-and-pave__/graphics/icons/select-and-pave-x56.png"
local icon_size = 56
local small_icon = "__select-and-pave__/graphics/icons/select-and-pave-x24.png"
local small_icon_size = 24

data:extend({
  {
    type = "custom-input",
    name = custom_input_name,
    key_sequence = "ALT + W",
    action = "lua",
  },
  {
    -- Unassigned by default: mods setting a default mouse-wheel key_sequence
    -- has a history of not being reliably recognized, so this is left for
    -- players to bind themselves (e.g. Shift + mouse wheel).
    --
    -- consuming: vanilla zoom fires on wheel input regardless of held
    -- modifiers, so a modifier + wheel binding would otherwise rotate and
    -- zoom at once. Consumption only applies when this input's own key
    -- sequence matches, leaving bare-wheel zoom alone (unless the player
    -- deliberately binds the bare wheel here).
    type = "custom-input",
    name = next_item_input_name,
    key_sequence = "",
    action = "lua",
    consuming = "game-only",
  },
  {
    type = "custom-input",
    name = previous_item_input_name,
    key_sequence = "",
    action = "lua",
    consuming = "game-only",
  },
  {
    type = "shortcut",
    name = shortcut_name,
    action = "lua",
    associated_control_input = custom_input_name,
    localised_description = {"shortcut-description." .. shortcut_name},
    icon = icon,
    icon_size = icon_size,
    small_icon = small_icon,
    small_icon_size = small_icon_size,
  },
})
