local paving = require("lib.paving")

-- Always the Space Age Gleba soil tiles, whether or not that MOD is active:
-- a mod-settings value only gets (re-)computed from this default the first
-- time the setting is ever resolved for a given player/save, so branching on
-- `mods["space-age"]` here would only pick the right default for someone who
-- happens to first touch this setting after installing Space Age. Anyone who
-- installs it later would be stuck with the earlier, blank default forever
-- (mod-settings.dat and existing saves both keep whatever value was already
-- recorded, ignoring this prototype's default_value from then on). Keeping
-- the value unconditional means it's already correct if/when Space Age shows
-- up. Without Space Age these names simply don't resolve to anything --
-- see get_protected_tile_names in control.lua, which recognizes exactly this
-- list and stays quiet about it instead of warning.
local protected_tiles_default = table.concat(paving.default_space_age_protected_tiles, ",")

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
    name = "select-and-pave-protected-tiles",
    setting_type = "runtime-global",
    default_value = protected_tiles_default,
    allow_blank = true,
  },
})
