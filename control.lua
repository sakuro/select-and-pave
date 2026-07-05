local paving = require("lib.paving")

local shortcut_name = "select-and-pave-activate"
local custom_input_name = "select-and-pave-activate-input"

-- Prototypes are immutable after load, so this is computed once per game load
-- rather than kept in `storage`.
local paving_items

local function tile_prototype_name(tile_prototype)
  return tile_prototype.name
end

--- @return table<string, table> item name -> {result_name, normalized, specificity}
local function get_paving_items()
  if not paving_items then
    paving_items = {}
    for name, prototype in pairs(prototypes.item) do
      local place_as_tile = prototype.place_as_tile_result
      if place_as_tile then
        local specificity = math.huge
        if place_as_tile.tile_condition and #place_as_tile.tile_condition > 0 then
          specificity = #place_as_tile.tile_condition
        end
        paving_items[name] = {
          result_name = place_as_tile.result.name,
          normalized = paving.normalize(place_as_tile, tile_prototype_name),
          specificity = specificity,
        }
      end
    end
  end
  return paving_items
end

local function is_placeable(tile, entry)
  local mask = tile.prototype.collision_mask
  return paving.matches(tile.name, mask and mask.layers, entry.normalized)
end

local function is_placeable_on_tile_prototype(tile_prototype, entry)
  local mask = tile_prototype.collision_mask
  return paving.matches(tile_prototype.name, mask and mask.layers, entry.normalized)
end

local function position_key(position)
  return math.floor(position.x) .. "_" .. math.floor(position.y)
end

--- Finds a generic "underlay" item (e.g. landfill) whose place_as_tile is
--- valid on `tile`, and whose result tile `target_entry` would in turn be
--- placeable on. Prefers the most specific candidate (narrowest
--- `tile_condition`) so a cheap, purpose-built item like landfill is chosen
--- over a broad, general-purpose one like foundation; ties break
--- alphabetically for determinism.
local function choose_underlay(tile, target_entry)
  local candidates = {}
  for name, candidate_entry in pairs(get_paving_items()) do
    if is_placeable(tile, candidate_entry) then
      local candidate_result_tile = prototypes.tile[candidate_entry.result_name]
      if candidate_result_tile and is_placeable_on_tile_prototype(candidate_result_tile, target_entry) then
        candidates[#candidates + 1] = {name = name, entry = candidate_entry}
      end
    end
  end
  table.sort(candidates, function(a, b)
    if a.entry.specificity ~= b.entry.specificity then
      return a.entry.specificity < b.entry.specificity
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
    player.create_local_flying_text({
      text = {"select-and-pave-messages.no-paving-item"},
      position = player.position,
    })
    return
  end

  if not from_ghost then
    if not player.clear_cursor() then
      -- Main inventory full and the stack couldn't be dropped anywhere safe;
      -- bail out rather than risk destroying it.
      return
    end
  end

  storage.pending[player.index] = {from_ghost = from_ghost}
  player.cursor_stack.set_stack({name = paving.tool_prefix .. held_name, count = 1})
end

--- Restores the cursor to whatever it held (or previewed) before `activate`
--- swapped it out for the selection tool.
local function restore_cursor(player, held_name, from_ghost)
  player.cursor_stack.clear()

  if from_ghost then
    player.cursor_ghost = {name = held_name}
    return
  end

  local inventory = player.get_main_inventory()
  if not inventory then
    return
  end
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read and stack.name == held_name then
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

--- Extracts the held item's name from a `select-and-pave-tool-<name>`
--- prototype name, or nil if `tool_name` isn't one of ours.
local function held_item_name_from_tool(tool_name)
  if tool_name and tool_name:sub(1, #paving.tool_prefix) == paving.tool_prefix then
    return tool_name:sub(#paving.tool_prefix + 1)
  end
  return nil
end

local function place_ghost(surface, player, position, tile_name)
  surface.create_entity({
    name = "tile-ghost",
    position = position,
    inner_name = tile_name,
    force = player.force,
    player = player,
    raise_built = true,
  })
end

local function process_tile(surface, player, tile, entry, is_alt, ghost_positions)
  local key = position_key(tile.position)
  if ghost_positions[key] then
    return
  end

  if is_placeable(tile, entry) then
    place_ghost(surface, player, tile.position, entry.result_name)
    ghost_positions[key] = true
    return
  end

  if not is_alt then
    return
  end

  local underlay = choose_underlay(tile, entry)
  if not underlay then
    return
  end

  -- Stack both ghosts at once; robots build the underlay (e.g. landfill)
  -- first and the target tile once the underlay makes the position valid
  -- for it, without this MOD tracking the handoff itself.
  place_ghost(surface, player, tile.position, underlay.entry.result_name)
  place_ghost(surface, player, tile.position, entry.result_name)
  ghost_positions[key] = true
end

local function process_selection(event, is_alt)
  local held_name = held_item_name_from_tool(event.item)
  if not held_name then
    return
  end

  local pending = storage.pending[event.player_index]
  if not pending then
    return
  end
  storage.pending[event.player_index] = nil

  local player = game.get_player(event.player_index)
  local entry = get_paving_items()[held_name]

  if entry then
    local surface = event.surface
    local ghost_positions = collect_ghost_positions(surface, event.area)
    for _, tile in pairs(event.tiles) do
      process_tile(surface, player, tile, entry, is_alt, ghost_positions)
    end
  end

  restore_cursor(player, held_name, pending.from_ghost)
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
  local holding_tool = cursor_stack and cursor_stack.valid_for_read
    and held_item_name_from_tool(cursor_stack.name) ~= nil
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
