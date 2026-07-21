local paving = require("lib.paving")

-- Settings stage can't inspect prototypes yet (data stage hasn't run), but
-- doesn't need to here -- checking the mod's presence via `mods` is enough
-- to pick a sensible default without discovering place_as_tile items
-- generically (that discovery only happens in data-final-fixes.lua).
local protected_items_default = mods["space-age"]
  and table.concat(paving.default_space_age_protected_items, ",")
  or ""

data:extend({
  {
    type = "string-setting",
    name = "select-and-pave-after-selection",
    setting_type = "runtime-per-user",
    default_value = "keep-tool",
    allowed_values = {"keep-tool", "restore-item", "clear-cursor"},
  },
  {
    type = "string-setting",
    name = "select-and-pave-protected-items",
    setting_type = "runtime-global",
    default_value = protected_items_default,
    allow_blank = true,
  },
})
