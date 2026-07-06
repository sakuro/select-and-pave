local shortcut_name = "select-and-pave-activate"
local custom_input_name = "select-and-pave-activate-input"
local next_item_input_name = "select-and-pave-next-item"
local previous_item_input_name = "select-and-pave-previous-item"

-- Fixed shortcut-bar icon; the per-item selection tools defined in
-- data-final-fixes.lua get their icon from the paving item they represent.
local icon = "__select-and-pave__/graphics/icons/select-and-pave.png"
local icon_size = 64

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
    type = "custom-input",
    name = next_item_input_name,
    key_sequence = "",
    action = "lua",
  },
  {
    type = "custom-input",
    name = previous_item_input_name,
    key_sequence = "",
    action = "lua",
  },
  {
    type = "shortcut",
    name = shortcut_name,
    action = "lua",
    associated_control_input = custom_input_name,
    localised_description = {"shortcut-description." .. shortcut_name},
    icon = icon,
    icon_size = icon_size,
    small_icon = icon,
    small_icon_size = icon_size,
  },
})
