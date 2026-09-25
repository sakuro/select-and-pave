local paving = require("lib.paving")

local function identity(value)
  return value
end

--- Tile descriptor literal, shaped like paving.normalize_tile's result.
local function tile(name, layers, thawed_name)
  return { name = name, layers = layers, thawed_name = thawed_name }
end

-- Fixtures mirror vanilla definitions (see base/prototypes/item.lua): concrete
-- is blocked by water; landfill wants tiles from an explicit water list. The
-- invert item is hypothetical (pre-2.0 landfill style): valid only where the
-- mask matches.
local concrete = paving.normalize({
  result = "concrete",
  condition = { layers = { water_tile = true } },
}, identity)

local landfill = paving.normalize({
  result = "landfill",
  condition = { layers = { ground_tile = true } },
  tile_condition = { "water", "deepwater" },
}, identity)

local invert_item = paving.normalize({
  result = "invert-result",
  condition = { layers = { water_tile = true } },
  invert = true,
}, identity)

local unconditional = paving.normalize({ result = "plain-result" }, identity)

local ground = { ground_tile = true }
local water = { water_tile = true, item = true, player = true }

describe("paving.normalize", function()
  it("keeps the result name", function()
    assert.are.equal("concrete", concrete.result_name)
  end)

  it("keeps the condition layers", function()
    assert.is_true(concrete.condition_layers.water_tile)
  end)

  it("leaves tile_condition_names nil without a tile_condition", function()
    assert.is_nil(concrete.tile_condition_names)
  end)

  it("builds a tile_condition name set", function()
    assert.is_true(landfill.tile_condition_names.water)
  end)

  it("treats an empty tile_condition as none", function()
    local normalized = paving.normalize({ result = "r", tile_condition = {} }, identity)
    assert.is_nil(normalized.tile_condition_names)
  end)

  it("extracts names via name_of", function()
    local normalized = paving.normalize({ result = { name = "obj" } }, function(ref)
      return ref.name
    end)
    assert.are.equal("obj", normalized.result_name)
  end)
end)

describe("paving.normalize_tile", function()
  local data_tile = paving.normalize_tile(
    { name = "frozen-concrete", collision_mask = { layers = ground }, thawed_variant = "concrete" },
    identity
  )

  it("keeps the tile name", function()
    assert.are.equal("frozen-concrete", data_tile.name)
  end)

  it("lifts the collision-mask layers", function()
    assert.is_true(data_tile.layers.ground_tile)
  end)

  it("keeps the thawed name from a data-stage string", function()
    assert.are.equal("concrete", data_tile.thawed_name)
  end)

  it("extracts the thawed name from a runtime object via name_of", function()
    local runtime_tile = paving.normalize_tile(
      { name = "frozen-concrete", collision_mask = { layers = ground }, thawed_variant = { name = "concrete" } },
      function(ref)
        return ref.name
      end
    )
    assert.are.equal("concrete", runtime_tile.thawed_name)
  end)

  it("leaves layers nil without a collision mask", function()
    assert.is_nil(paving.normalize_tile({ name = "void" }, identity).layers)
  end)

  it("leaves thawed_name nil without a thawed variant", function()
    assert.is_nil(paving.normalize_tile({ name = "void" }, identity).thawed_name)
  end)
end)

describe("paving.matches", function()
  describe("already-paved short circuit", function()
    it("rejects the item's own result tile", function()
      assert.is_false(paving.matches(concrete, tile("concrete", ground)))
    end)

    it("rejects a frozen tile that thaws into the result", function()
      assert.is_false(paving.matches(concrete, tile("frozen-concrete", ground, "concrete")))
    end)

    it("allows a frozen tile that thaws into something else", function()
      assert.is_true(paving.matches(concrete, tile("frozen-x", ground, "x")))
    end)
  end)

  describe("tile_condition whitelist", function()
    it("allows a listed tile", function()
      assert.is_true(paving.matches(landfill, tile("water", water)))
    end)

    it("rejects an unlisted tile", function()
      assert.is_false(paving.matches(landfill, tile("oil-ocean-shallow", { water_tile = true })))
    end)

    it("still vetoes a listed tile via the condition layers", function()
      assert.is_false(paving.matches(landfill, tile("water", { ground_tile = true })))
    end)
  end)

  describe("collision-mask condition", function()
    it("blocks where the layers intersect", function()
      assert.is_false(paving.matches(concrete, tile("water", water)))
    end)

    it("allows where the layers do not intersect", function()
      assert.is_true(paving.matches(concrete, tile("grass", ground)))
    end)

    it("cannot intersect a nil mask", function()
      assert.is_true(paving.matches(concrete, tile("void", nil)))
    end)
  end)

  describe("invert", function()
    it("allows where the mask matches", function()
      assert.is_true(paving.matches(invert_item, tile("water", water)))
    end)

    it("rejects where the mask does not match", function()
      assert.is_false(paving.matches(invert_item, tile("grass", ground)))
    end)

    it("rejects a nil mask", function()
      assert.is_false(paving.matches(invert_item, tile("void", nil)))
    end)
  end)

  it("places an unconditional item anywhere", function()
    assert.is_true(paving.matches(unconditional, tile("anything", water)))
  end)
end)

describe("paving.condition_references", function()
  it("recognizes a referenced layer", function()
    assert.is_true(paving.condition_references(invert_item, "water_tile"))
  end)

  it("does not recognize an unreferenced layer", function()
    assert.is_false(paving.condition_references(concrete, "ground_tile"))
  end)

  it("recognizes nothing without a condition", function()
    assert.is_false(paving.condition_references(unconditional, "water_tile"))
  end)
end)

describe("paving.parse_name_list", function()
  it("splits on commas", function()
    assert.is_true(paving.parse_name_list("foo, bar,\nbaz").foo)
  end)

  it("splits on newlines", function()
    assert.is_true(paving.parse_name_list("foo, bar,\nbaz").baz)
  end)

  it("trims surrounding whitespace", function()
    assert.is_true(paving.parse_name_list("foo, bar,\nbaz").bar)
  end)

  it("yields nothing for an empty string", function()
    assert.is_nil(next(paving.parse_name_list("")))
  end)

  it("ignores blank entries", function()
    assert.is_nil(next(paving.parse_name_list(" , ,\n")))
  end)
end)
