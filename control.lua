local paving = require("lib.paving")

local shortcut_name = "select-and-pave-activate"
local custom_input_name = "select-and-pave-activate-input"
local next_item_input_name = "select-and-pave-next-item"
local previous_item_input_name = "select-and-pave-previous-item"

-- Prototypes are immutable after load, so these are computed once per game
-- load rather than kept in `storage`.
local paving_items
local unlock_technologies

local function tile_prototype_name(tile_prototype)
  return tile_prototype.name
end

local function specificity_of(place_as_tile)
  if place_as_tile.tile_condition and #place_as_tile.tile_condition > 0 then
    return #place_as_tile.tile_condition
  end
  return math.huge
end

--- @return table<string, table<string, boolean>> item name -> set of
--- technology names, any one of which unlocks a recipe producing that item.
--- Items with a recipe already enabled at the start of the game (no
--- research needed) are omitted entirely.
local function get_unlock_technologies()
  if unlock_technologies then
    return unlock_technologies
  end

  -- recipe name -> set of item names it produces
  local recipe_items = {}
  -- item name -> true if some recipe producing it needs no research
  local always_available = {}
  for recipe_name, recipe in pairs(prototypes.recipe) do
    local items = {}
    for _, product in pairs(recipe.products) do
      if product.type == "item" then
        items[product.name] = true
        if recipe.enabled then
          always_available[product.name] = true
        end
      end
    end
    recipe_items[recipe_name] = items
  end

  unlock_technologies = {}
  for tech_name, technology in pairs(prototypes.technology) do
    for _, effect in pairs(technology.effects) do
      if effect.type == "unlock-recipe" then
        for item_name in pairs(recipe_items[effect.recipe] or {}) do
          if not always_available[item_name] then
            unlock_technologies[item_name] = unlock_technologies[item_name] or {}
            unlock_technologies[item_name][tech_name] = true
          end
        end
      end
    end
  end

  return unlock_technologies
end

local function build_paving_entry(name, place_as_tile)
  return {
    result_name = place_as_tile.result.name,
    normalized = paving.normalize(place_as_tile, tile_prototype_name),
    specificity = specificity_of(place_as_tile),
    required_technologies = get_unlock_technologies()[name],
  }
end

--- @return table<string, table> item name -> {result_name, normalized, specificity, required_technologies}
local function get_paving_items()
  if paving_items then
    return paving_items
  end

  paving_items = {}
  for name, prototype in pairs(prototypes.item) do
    local place_as_tile = prototype.place_as_tile_result
    if place_as_tile then
      paving_items[name] = build_paving_entry(name, place_as_tile)
    end
  end
  return paving_items
end

--- Whether `force` can currently obtain `entry`'s item (no gating recipe, or
--- at least one unlocking technology already researched).
local function is_available(entry, force)
  local technologies = entry.required_technologies
  if not technologies then
    return true
  end
  for tech_name in pairs(technologies) do
    local technology = force.technologies[tech_name]
    if technology and technology.researched then
      return true
    end
  end
  return false
end

-- Space platform surfaces expose this collision layer on their bare tiles;
-- only items whose place_as_tile condition specifically references it (e.g.
-- Space Age's space-platform-foundation) are meaningful there. Every other
-- item's condition is written with planet surfaces in mind and simply never
-- mentions this layer, which the generic collision-mask check would
-- otherwise mistake for "no restriction" and allow anywhere.
local platform_layer = "empty_space"

local function usable_on_platform(entry)
  return paving.condition_references(entry.normalized, platform_layer)
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

--- Returns {name, entry} if `candidate_entry` is a viable underlay for
--- `target_entry` on `tile` for `force` (currently obtainable by that force,
--- usable on this surface, placeable on `tile`, and `target_entry` in turn
--- placeable on its result), or nil otherwise.
local function underlay_candidate(name, candidate_entry, tile, target_entry, force, on_platform)
  if on_platform and not usable_on_platform(candidate_entry) then
    return nil
  end

  if not is_available(candidate_entry, force) then
    return nil
  end

  if not is_placeable(tile, candidate_entry) then
    return nil
  end

  local result_tile = prototypes.tile[candidate_entry.result_name]
  if not result_tile then
    return nil
  end

  if not is_placeable_on_tile_prototype(result_tile, target_entry) then
    return nil
  end

  return {name = name, entry = candidate_entry}
end

--- Finds a generic "underlay" item (e.g. landfill) whose place_as_tile is
--- valid on `tile`, and whose result tile `target_entry` would in turn be
--- placeable on. Only considers items `force` can currently obtain --
--- unresearched items are treated as if they didn't exist. Prefers the most
--- specific candidate (narrowest `tile_condition`) so a cheap, purpose-built
--- item like landfill is chosen over a broad, general-purpose one like
--- foundation; ties break alphabetically for determinism.
local function choose_underlay(tile, target_entry, force, on_platform)
  local candidates = {}
  for name, candidate_entry in pairs(get_paving_items()) do
    local candidate = underlay_candidate(name, candidate_entry, tile, target_entry, force, on_platform)
    if candidate then
      candidates[#candidates + 1] = candidate
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

--- Whether `entry`'s result tile could host some other paving item (e.g.
--- landfill's result tile accepts concrete on top), independent of any
--- specific tile, force research state, or platform -- a tile-agnostic
--- classification for display purposes, not the precise per-tile check
--- `choose_underlay` performs when actually placing ghosts.
local function can_serve_as_underlay(name, entry)
  local result_tile = prototypes.tile[entry.result_name]
  if not result_tile then
    return false
  end
  for other_name, other_entry in pairs(get_paving_items()) do
    if other_name ~= name and is_placeable_on_tile_prototype(result_tile, other_entry) then
      return true
    end
  end
  return false
end

--- Shows flying text at `player`'s position naming the paving item `name`,
--- noting when it could also serve as an underlay for other paving items.
local function announce_paving_item(player, name)
  local entry = get_paving_items()[name]
  local message_key = entry and can_serve_as_underlay(name, entry)
    and "select-and-pave-messages.now-paving-underlay"
    or "select-and-pave-messages.now-paving"
  player.create_local_flying_text({
    text = {message_key, prototypes.item[name].localised_name},
    position = player.position,
  })
end

--- Reads the item the player is holding, either for real (cursor_stack) or
--- as a preview (cursor_ghost). Returns nil if neither is set. Quality is
--- tracked only so the exact same stack/preview can be restored afterwards
--- -- it plays no part in paving logic itself, which is quality-blind.
local function get_held_item_name(player)
  local cursor_stack = player.cursor_stack
  if cursor_stack and cursor_stack.valid_for_read then
    return cursor_stack.name, cursor_stack.quality.name, false
  end

  local cursor_ghost = player.cursor_ghost
  if cursor_ghost then
    return cursor_ghost.name.name, cursor_ghost.quality.name, true
  end

  return nil, nil, false
end

--- Finds a stack of `item_name` in the player's main inventory, optionally
--- matching `quality` too (any quality if omitted). Returns the LuaItemStack,
--- or nil if none is found.
local function find_inventory_stack(player, item_name, quality)
  local inventory = player.get_main_inventory()
  if not inventory then
    return nil
  end
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read and stack.name == item_name and (not quality or stack.quality.name == quality) then
      return stack
    end
  end
  return nil
end

--- If the player is holding nothing at all, tries to put the last item they
--- paved with back in their hand -- a real stack from inventory if they
--- still have one, otherwise a cursor_ghost preview -- so activating with
--- empty hands repeats the last paving item instead of just failing.
local function equip_last_used(player)
  local last_used = storage.last_used[player.index]
  if not last_used or not get_paving_items()[last_used] then
    return false
  end

  local cursor_stack = player.cursor_stack
  if not cursor_stack then
    return false
  end

  local stack = find_inventory_stack(player, last_used)
  if stack then
    cursor_stack.swap_stack(stack)
    return true
  end

  player.cursor_ghost = {name = last_used}
  return true
end

local function activate(player)
  local held_name, held_quality, from_ghost = get_held_item_name(player)
  if not held_name and equip_last_used(player) then
    held_name, held_quality, from_ghost = get_held_item_name(player)
  end

  local entry = held_name and get_paving_items()[held_name]
  if not entry then
    player.create_local_flying_text({
      text = {"select-and-pave-messages.no-paving-item"},
      position = player.position,
    })
    return
  end

  -- A real cursor_stack means the player already has the item, regardless of
  -- research; a cursor_ghost is just a preview (e.g. from Factoriopedia) and
  -- can point at an item the force can't actually produce yet.
  if from_ghost and not is_available(entry, player.force) then
    player.create_local_flying_text({
      text = {"select-and-pave-messages.not-yet-researched"},
      position = player.position,
    })
    return
  end

  if not from_ghost and not player.clear_cursor() then
    -- clear_cursor() normally always empties the cursor (dropping on the
    -- ground if the main inventory is full), so a false return means
    -- something more fundamental prevented it; don't swap cursors in that
    -- case rather than risk the held stack.
    return
  end

  storage.pending[player.index] = {from_ghost = from_ghost, quality = held_quality}
  player.cursor_stack.set_stack({name = paving.tool_prefix .. held_name, count = 1})
  announce_paving_item(player, held_name)
end

--- Restores the cursor to whatever it held (or previewed) before `activate`
--- swapped it out for the selection tool. `held_quality` is nil after
--- rotating to a different item mid-selection (see rotate_item), in which
--- case any quality of `held_name` matches.
local function restore_cursor(player, held_name, held_quality, from_ghost)
  player.cursor_stack.clear()

  if from_ghost then
    player.cursor_ghost = held_quality and {name = held_name, quality = held_quality} or {name = held_name}
    return
  end

  local stack = find_inventory_stack(player, held_name, held_quality)
  if stack then
    player.cursor_stack.swap_stack(stack)
  end
end

--- Composite key so two different tile-ghosts stacked at the same position
--- (e.g. a landfill underlay and a concrete target) are tracked separately.
local function ghost_key(position, tile_name)
  return position_key(position) .. "|" .. tile_name
end

--- Existing tile-ghosts belonging to `force` within `area`, keyed by
--- `ghost_key`. Scoped to `force` so another force's ghosts never block our
--- own placement.
local function collect_existing_ghosts(surface, area, force)
  local existing = {}
  local ghosts = surface.find_entities_filtered({area = area, type = "tile-ghost", force = force})
  for _, ghost in pairs(ghosts) do
    existing[ghost_key(ghost.position, ghost.ghost_name)] = true
  end
  return existing
end

--- Extracts the held item's name from a `select-and-pave-tool-<name>`
--- prototype name, or nil if `tool_name` isn't one of ours.
local function held_item_name_from_tool(tool_name)
  if tool_name and tool_name:sub(1, #paving.tool_prefix) == paving.tool_prefix then
    return tool_name:sub(#paving.tool_prefix + 1)
  end
  return nil
end

--- Item names from get_paving_items(), sorted for deterministic rotation.
local function sorted_paving_item_names()
  local names = {}
  for name in pairs(get_paving_items()) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- Item names `player` may rotate to: either they already have a real stack
--- of it, or `force` can currently obtain it. An item with neither (no
--- stack in hand and unresearched) is excluded entirely, matching
--- activate()'s refusal to open on an unresearched cursor_ghost preview.
local function rotation_candidates(player)
  local candidates = {}
  for _, name in pairs(sorted_paving_item_names()) do
    local entry = get_paving_items()[name]
    if find_inventory_stack(player, name) or is_available(entry, player.force) then
      candidates[#candidates + 1] = name
    end
  end
  return candidates
end

--- Cycles the active selection tool to the next/previous paving item
--- (`direction` +1 or -1), while the tool is active. Whether the new item
--- restores as a real stack or a cursor_ghost preview is decided fresh each
--- time, based on whether the player currently has a stack of it -- not on
--- whether the item being rotated away from was real or a preview.
local function rotate_item(player, direction)
  if not storage.pending[player.index] then
    return
  end

  local cursor_stack = player.cursor_stack
  local current_name = cursor_stack and cursor_stack.valid_for_read and held_item_name_from_tool(cursor_stack.name)
  if not current_name then
    return
  end

  local candidates = rotation_candidates(player)
  if #candidates == 0 then
    return
  end

  local current_index
  for i, name in ipairs(candidates) do
    if name == current_name then
      current_index = i
      break
    end
  end

  local next_index = (((current_index or 1) - 1 + direction) % #candidates) + 1
  local next_name = candidates[next_index]
  if next_name == current_name then
    return
  end

  local next_stack = find_inventory_stack(player, next_name)
  storage.pending[player.index] = {from_ghost = not next_stack}
  player.cursor_stack.set_stack({name = paving.tool_prefix .. next_name, count = 1})
  announce_paving_item(player, next_name)
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

--- Places a `tile_name` ghost at `tile.position` unless one is already
--- there, recording it in `existing_ghosts` either way.
local function place_ghost_once(surface, player, tile, tile_name, existing_ghosts)
  local key = ghost_key(tile.position, tile_name)
  if existing_ghosts[key] then
    return
  end
  place_ghost(surface, player, tile.position, tile_name)
  existing_ghosts[key] = true
end

local function process_tile(surface, player, tile, entry, is_alt, existing_ghosts, on_platform)
  if on_platform and not usable_on_platform(entry) then
    return
  end

  if is_placeable(tile, entry) then
    place_ghost_once(surface, player, tile, entry.result_name, existing_ghosts)
    return
  end

  if not is_alt then
    return
  end

  local underlay = choose_underlay(tile, entry, player.force, on_platform)
  if not underlay then
    return
  end

  -- Stack both ghosts at once; robots build the underlay (e.g. landfill)
  -- first and the target tile once the underlay makes the position valid
  -- for it, without this MOD tracking the handoff itself. Each is deduped
  -- independently, so an underlay ghost placed earlier (by this MOD, a
  -- blueprint, or anything else) doesn't block the target ghost from still
  -- being added on top of it.
  place_ghost_once(surface, player, tile, underlay.entry.result_name, existing_ghosts)
  place_ghost_once(surface, player, tile, entry.result_name, existing_ghosts)
end

local function place_ghosts(player, event, entry, is_alt)
  if not entry then
    return
  end

  local surface = event.surface
  local on_platform = surface.platform ~= nil
  local existing_ghosts = collect_existing_ghosts(surface, event.area, player.force)
  for _, tile in pairs(event.tiles) do
    process_tile(surface, player, tile, entry, is_alt, existing_ghosts, on_platform)
  end
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

  place_ghosts(player, event, entry, is_alt)
  if entry then
    storage.last_used[event.player_index] = held_name
  end
  restore_cursor(player, held_name, pending.quality, pending.from_ghost)
end

script.on_init(function()
  storage.pending = {}
  storage.last_used = {}
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

script.on_event(next_item_input_name, function(event)
  local player = game.get_player(event.player_index)
  if player then
    rotate_item(player, 1)
  end
end)

script.on_event(previous_item_input_name, function(event)
  local player = game.get_player(event.player_index)
  if player then
    rotate_item(player, -1)
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
  storage.last_used[event.player_index] = nil
end)

script.on_event(defines.events.on_player_selected_area, function(event)
  process_selection(event, false)
end)

script.on_event(defines.events.on_player_alt_selected_area, function(event)
  process_selection(event, true)
end)
