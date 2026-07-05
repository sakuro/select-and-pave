local shortcut_name = "select-and-pave-activate"
local custom_input_name = "select-and-pave-activate-input"

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
    type = "shortcut",
    name = shortcut_name,
    action = "lua",
    associated_control_input = custom_input_name,
    icon = icon,
    icon_size = icon_size,
    small_icon = icon,
    small_icon_size = icon_size,
  },
})
