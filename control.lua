local shortcut_name = "select-and-pave-activate"
local custom_input_name = "select-and-pave-activate-input"
local selection_tool_name = "select-and-pave-tool"

-- Prototypes are immutable after load, so this is computed once per game load
-- rather than kept in `storage`.
local paving_items

--- @return table<string, PlaceAsTileResult> item name -> place_as_tile_result
local function get_paving_items()
  if not paving_items then
    paving_items = {}
    for name, prototype in pairs(prototypes.item) do
      local place_as_tile = prototype.place_as_tile_result
      if place_as_tile then
        paving_items[name] = place_as_tile
      end
    end
  end
  return paving_items
end

--- Whether `place_as_tile` allows its result tile to be placed over a tile
--- identified by `tile_name`/`tile_prototype`.
local function matches_place_as_tile(tile_name, tile_prototype, place_as_tile)
  if tile_name == place_as_tile.result.name then
    return false -- already paved
  end

  local tile_condition = place_as_tile.tile_condition
  if tile_condition and #tile_condition > 0 then
    local matched = false
    for _, candidate in pairs(tile_condition) do
      if candidate.name == tile_name then
        matched = true
        break
      end
    end
    if not matched then
      return false
    end
  end

  local condition = place_as_tile.condition
  if not (condition and condition.layers) then
    return true
  end

  local mask = tile_prototype.collision_mask
  local intersects = false
  if mask and mask.layers then
    for layer in pairs(condition.layers) do
      if mask.layers[layer] then
        intersects = true
        break
      end
    end
  end

  -- `condition` names layers this item's tile is blocked by default (e.g.
  -- concrete's "water-tile"); `invert` flips it into an allowlist (e.g.
  -- landfill's "only valid where this matches").
  if place_as_tile.invert then
    return intersects
  end
  return not intersects
end

local function is_placeable(tile, place_as_tile)
  return matches_place_as_tile(tile.name, tile.prototype, place_as_tile)
end

local function is_placeable_on_tile_prototype(tile_prototype, place_as_tile)
  return matches_place_as_tile(tile_prototype.name, tile_prototype, place_as_tile)
end

local function position_key(position)
  return math.floor(position.x) .. "_" .. math.floor(position.y)
end

--- A shorter `tile_condition` whitelist means an item targets a narrower set
--- of tiles (e.g. landfill only lists water tiles, while Space Age's
--- foundation also lists lava/oil-ocean/wetland tiles). Items with no
--- whitelist at all are the least specific and sort last.
local function underlay_specificity(place_as_tile)
  local tile_condition = place_as_tile.tile_condition
  if tile_condition and #tile_condition > 0 then
    return #tile_condition
  end
  return math.huge
end

--- Finds a generic "underlay" item (e.g. landfill) whose place_as_tile is
--- valid on `tile`, and whose result tile the original `place_as_tile` would
--- in turn be placeable on. Prefers the most specific candidate (see
--- `underlay_specificity`) so a cheap, purpose-built item like landfill is
--- chosen over a broad, general-purpose one like foundation; ties break
--- alphabetically for determinism.
local function choose_underlay(tile, place_as_tile)
  local candidates = {}
  for name, candidate in pairs(get_paving_items()) do
    if is_placeable(tile, candidate) and is_placeable_on_tile_prototype(candidate.result, place_as_tile) then
      candidates[#candidates + 1] = {name = name, place_as_tile = candidate}
    end
  end
  table.sort(candidates, function(a, b)
    local specificity_a, specificity_b = underlay_specificity(a.place_as_tile), underlay_specificity(b.place_as_tile)
    if specificity_a ~= specificity_b then
      return specificity_a < specificity_b
    end
    return a.name < b.name
  end)
  return candidates[1]
end

--- Reads the item the player is holding, either for real (cursor_stack) or
--- as a preview (cursor_ghost). Returns nil if neither is set.
local function get_held_item_name(player)
  local cursor_stack = player.cursor_stack
  if cursor_stack and cursor_stack.valid_for_read then
    return cursor_stack.name, false
  end

  local cursor_ghost = player.cursor_ghost
  if cursor_ghost then
    return cursor_ghost.name.name, true
  end

  return nil, false
end

local function activate(player)
  local held_name, from_ghost = get_held_item_name(player)
  if not held_name or not get_paving_items()[held_name] then
    return
  end

  if not from_ghost then
    if not player.clear_cursor() then
      -- Main inventory full and the stack couldn't be dropped anywhere safe;
      -- bail out rather than risk destroying it.
      return
    end
  end

  storage.pending[player.index] = {name = held_name, from_ghost = from_ghost}
  player.cursor_stack.set_stack({name = selection_tool_name, count = 1})
end

--- Restores the cursor to whatever it held (or previewed) before `activate`
--- swapped it out for the selection tool.
local function restore_cursor(player, pending)
  player.cursor_stack.clear()

  if pending.from_ghost then
    player.cursor_ghost = {name = pending.name}
    return
  end

  local inventory = player.get_main_inventory()
  if not inventory then
    return
  end
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read and stack.name == pending.name then
      player.cursor_stack.swap_stack(stack)
      return
    end
  end
end

local function collect_ghost_positions(surface, area)
  local positions = {}
  for _, ghost in pairs(surface.find_entities_filtered({area = area, type = "tile-ghost"})) do
    positions[position_key(ghost.position)] = true
  end
  return positions
end

local function process_selection(event, is_alt)
  if event.item ~= selection_tool_name then
    return
  end

  local pending = storage.pending[event.player_index]
  if not pending then
    return
  end
  storage.pending[event.player_index] = nil

  local player = game.get_player(event.player_index)
  local place_as_tile = get_paving_items()[pending.name]

  if place_as_tile then
    local surface = event.surface
    local ghost_positions = collect_ghost_positions(surface, event.area)

    for _, tile in pairs(event.tiles) do
      local key = position_key(tile.position)
      if not ghost_positions[key] then
        if is_placeable(tile, place_as_tile) then
          surface.create_entity({
            name = "tile-ghost",
            position = tile.position,
            inner_name = place_as_tile.result.name,
            force = player.force,
            player = player,
            raise_built = true,
          })
          ghost_positions[key] = true
        elseif is_alt then
          local underlay = choose_underlay(tile, place_as_tile)
          if underlay then
            -- Stack both ghosts at once; robots build the underlay (e.g.
            -- landfill) first and the target tile once the underlay makes
            -- the position valid for it, without this MOD tracking the
            -- handoff itself.
            surface.create_entity({
              name = "tile-ghost",
              position = tile.position,
              inner_name = underlay.place_as_tile.result.name,
              force = player.force,
              player = player,
              raise_built = true,
            })
            surface.create_entity({
              name = "tile-ghost",
              position = tile.position,
              inner_name = place_as_tile.result.name,
              force = player.force,
              player = player,
              raise_built = true,
            })
            ghost_positions[key] = true
          end
        end
      end
    end
  end

  restore_cursor(player, pending)
end

script.on_init(function()
  storage.pending = {}
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= shortcut_name then
    return
  end
  local player = game.get_player(event.player_index)
  if player then
    activate(player)
  end
end)

script.on_event(custom_input_name, function(event)
  local player = game.get_player(event.player_index)
  if player then
    activate(player)
  end
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  if not storage.pending[event.player_index] then
    return
  end
  local player = game.get_player(event.player_index)
  local cursor_stack = player.cursor_stack
  local holding_tool = cursor_stack and cursor_stack.valid_for_read and cursor_stack.name == selection_tool_name
  if not holding_tool then
    storage.pending[event.player_index] = nil
  end
end)

script.on_event(defines.events.on_player_removed, function(event)
  storage.pending[event.player_index] = nil
end)

script.on_event(defines.events.on_player_selected_area, function(event)
  process_selection(event, false)
end)

script.on_event(defines.events.on_player_alt_selected_area, function(event)
  process_selection(event, true)
end)
