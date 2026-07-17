-- Plain-Lua unit tests for lib/paving.lua -- no Factorio, no test framework.
-- Run from the repository root: lua tests/paving_test.lua (mise run test)
package.path = "./?.lua;" .. package.path
local paving = require("lib.paving")

local failures = 0

local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    io.write(("FAIL %s: got %s, want %s\n"):format(name, tostring(got), tostring(want)))
  end
end

local function identity(value)
  return value
end

-- Fixtures mirror vanilla definitions (see base/prototypes/item.lua):
-- concrete is blocked by water, landfill wants ground-free tiles from an
-- explicit water list. The invert item is hypothetical (pre-2.0 landfill
-- style): valid only where the mask matches.
local concrete = paving.normalize({
  result = "concrete",
  condition = {layers = {water_tile = true}},
}, identity)

local landfill = paving.normalize({
  result = "landfill",
  condition = {layers = {ground_tile = true}},
  tile_condition = {"water", "deepwater"},
}, identity)

local invert_item = paving.normalize({
  result = "invert-result",
  condition = {layers = {water_tile = true}},
  invert = true,
}, identity)

local unconditional = paving.normalize({result = "plain-result"}, identity)

local ground = {ground_tile = true}
local water = {water_tile = true, item = true, player = true}

--- Tile descriptor literal, shaped like paving.normalize_tile's result.
local function tile(name, layers, thawed_name)
  return {name = name, layers = layers, thawed_name = thawed_name}
end

-- normalize
check("normalize keeps result name", concrete.result_name, "concrete")
check("normalize keeps condition layers", concrete.condition_layers.water_tile, true)
check("normalize without tile_condition", concrete.tile_condition_names, nil)
check("normalize builds tile_condition set", landfill.tile_condition_names.water, true)
check("normalize treats empty tile_condition as none",
  paving.normalize({result = "r", tile_condition = {}}, identity).tile_condition_names, nil)
check("normalize extracts names via name_of",
  paving.normalize({result = {name = "obj"}}, function(ref) return ref.name end).result_name, "obj")

-- normalize_tile: data-stage shape (plain strings) and runtime shape (objects)
local data_tile = paving.normalize_tile(
  {name = "frozen-concrete", collision_mask = {layers = ground}, thawed_variant = "concrete"}, identity)
check("normalize_tile keeps name", data_tile.name, "frozen-concrete")
check("normalize_tile lifts mask layers", data_tile.layers.ground_tile, true)
check("normalize_tile keeps thawed name", data_tile.thawed_name, "concrete")
local runtime_tile = paving.normalize_tile(
  {name = "frozen-concrete", collision_mask = {layers = ground}, thawed_variant = {name = "concrete"}},
  function(ref) return ref.name end)
check("normalize_tile extracts thawed name via name_of", runtime_tile.thawed_name, "concrete")
local bare_tile = paving.normalize_tile({name = "void"}, identity)
check("normalize_tile without mask", bare_tile.layers, nil)
check("normalize_tile without thawed variant", bare_tile.thawed_name, nil)

-- matches: already-paved short circuit
check("own result tile is already paved", paving.matches(concrete, tile("concrete", ground)), false)
check("frozen tile thawing into result is already paved",
  paving.matches(concrete, tile("frozen-concrete", ground, "concrete")), false)
check("frozen tile thawing into something else is not",
  paving.matches(concrete, tile("frozen-x", ground, "x")), true)

-- matches: tile_condition whitelist
check("landfill allowed on listed water", paving.matches(landfill, tile("water", water)), true)
check("landfill rejected on unlisted tile",
  paving.matches(landfill, tile("oil-ocean-shallow", {water_tile = true})), false)
check("listed tile still vetoed by condition layers",
  paving.matches(landfill, tile("water", {ground_tile = true})), false)

-- matches: collision-mask condition (default: blocked where layers intersect)
check("concrete blocked on water", paving.matches(concrete, tile("water", water)), false)
check("concrete allowed on ground", paving.matches(concrete, tile("grass", ground)), true)
check("nil mask cannot intersect", paving.matches(concrete, tile("void", nil)), true)

-- matches: invert flips the condition into an allowlist
check("invert item allowed where mask matches", paving.matches(invert_item, tile("water", water)), true)
check("invert item rejected where mask does not", paving.matches(invert_item, tile("grass", ground)), false)
check("invert item rejected on nil mask", paving.matches(invert_item, tile("void", nil)), false)

-- matches: no condition at all
check("unconditional item places anywhere", paving.matches(unconditional, tile("anything", water)), true)

-- condition_references
check("references its own layer", paving.condition_references(invert_item, "water_tile"), true)
check("does not reference other layers", paving.condition_references(concrete, "ground_tile"), false)
check("no condition references nothing", paving.condition_references(unconditional, "water_tile"), false)

if failures > 0 then
  io.write(("%d failure(s)\n"):format(failures))
  os.exit(1)
end
io.write("all tests passed\n")
