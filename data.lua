local shortcut_name = "select-and-pave-activate"
local custom_input_name = "select-and-pave-activate-input"
local selection_tool_name = "select-and-pave-tool"

-- Borrowed from the base mod so this MOD doesn't need its own art pipeline.
local icon = "__base__/graphics/icons/concrete.png"
local icon_size = 64

data:extend({
  {
    type = "custom-input",
    name = custom_input_name,
    key_sequence = "",
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
  {
    type = "selection-tool",
    name = selection_tool_name,
    icon = icon,
    icon_size = icon_size,
    flags = {"only-in-cursor", "not-stackable"},
    hidden = true,
    stack_size = 1,
    select = {
      mode = {"any-tile"},
      cursor_box_type = "copy",
      border_color = {r = 0.9, g = 0.7, b = 0.2},
    },
    alt_select = {
      mode = {"any-tile"},
      cursor_box_type = "copy",
      border_color = {r = 0.3, g = 0.6, b = 0.9},
    },
  },
})
