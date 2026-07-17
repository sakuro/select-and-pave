local paving = require("lib.paving")

local shortcut_name = "select-and-pave-activate"
local custom_input_name = "select-and-pave-activate-input"
local next_item_input_name = "select-and-pave-next-item"
local previous_item_input_name = "select-and-pave-previous-item"
local keep_tool_setting = "select-and-pave-keep-tool"

-- Prototypes are immutable after load, so these are computed once per game
-- load rather than kept in `storage`.
local paving_items
local item_recipes
-- item name -> whether it can serve as an underlay (see can_serve_as_underlay)
local underlay_capability = {}

local function tile_prototype_name(tile_prototype)
  return tile_prototype.name
end

local function specificity_of(place_as_tile)
  if place_as_tile.tile_condition and #place_as_tile.tile_condition > 0 then
    return #place_as_tile.tile_condition
  end
  return math.huge
end

--- @return table<string, table<string, boolean>> item name -> set of names
--- of recipes producing that item. Items no recipe produces are absent.
local function get_item_recipes()
  if item_recipes then
    return item_recipes
  end

  item_recipes = {}
  for recipe_name, recipe in pairs(prototypes.recipe) do
    for _, product in pairs(recipe.products) do
      if product.type == "item" then
        item_recipes[product.name] = item_recipes[product.name] or {}
        item_recipes[product.name][recipe_name] = true
      end
    end
  end
  return item_recipes
end

local function build_paving_entry(name, place_as_tile)
  return {
    result_name = place_as_tile.result.name,
    normalized = paving.normalize(place_as_tile, tile_prototype_name),
    specificity = specificity_of(place_as_tile),
    recipes = get_item_recipes()[name],
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

--- Whether `force` can currently obtain `entry`'s item: some recipe
--- producing it is enabled for the force (whether via research or enabled by
--- script). Items no recipe produces are assumed obtainable some other way
--- (mining, scripts) rather than locked out forever.
local function is_available(entry, force)
  if not entry.recipes then
    return true
  end
  for recipe_name in pairs(entry.recipes) do
    local recipe = force.recipes[recipe_name]
    if recipe and recipe.enabled then
      return true
    end
  end
  return false
end

-- Space platform surfaces expose this collision layer on their bare tiles;
-- only items whose place_as_tile condition specifically references it (e.g.
-- Space Age's space-platform-foundation) may be paved on platforms at all.
-- can_place_tile_ghost does NOT make this guard redundant: the underlay
-- search's "would the target fit on the underlay's result tile?" question
-- is positionless and answered by paving.matches, which cannot see the
-- platform rule. Without the guard it stacks concrete on a foundation
-- underlay -- a placement the game refuses to make manually (even as a
-- ghost from remote view) yet robots happily revive, so the forbidden
-- state would be reachable only through this MOD.
local platform_layer = "empty_space"

-- The layer water and lava tiles carry (see base's tile-collision-masks.lua),
-- and the one plain paving items are universally blocked by. It's what
-- specifically makes landfill/foundation "underlays": they reclaim terrain
-- nothing else can touch. Other collision layers (e.g. Aquilo's "meltable",
-- which blocks stone brick but not concrete) are gameplay-balance distinctions
-- between plain paving items, not underlay-worthy terrain access.
local water_layer = "water_tile"

local function usable_on_platform(entry)
  return paving.condition_references(entry.normalized, platform_layer)
end

--- Asks the engine whether a `tile_name` ghost could be manually placed at
--- `position` -- the authoritative build check, honoring every placement
--- rule lib/paving.lua's prototype-level `matches` only approximates
--- (condition_size neighborhoods, foundation rules on space platforms, ...).
--- Only answerable where an actual position exists; prototype-vs-prototype
--- questions (underlay result tiles, data-stage filters) still go through
--- `matches`.
local function can_place_tile_ghost(surface, position, tile_name, force)
  return surface.can_place_entity({
    name = "tile-ghost",
    inner_name = tile_name,
    position = position,
    force = force,
    build_check_type = defines.build_check_type.manual_ghost,
  })
end

--- Whether `tile` already is (or, frozen, thaws back into) `entry`'s result.
--- The engine check can't express "nothing to do": it approves re-placing a
--- tile over its own frozen variant (a thaw no heat source would hold), and
--- its refusal over the identical tile would read as "blocked, needs an
--- underlay" -- paving concrete over concrete would sneak a hazard concrete
--- "underlay" in, since concrete is placeable on top of it.
local function is_already_paved(tile, entry)
  local thawed = tile.prototype.thawed_variant
  return tile.name == entry.result_name or (thawed and thawed.name == entry.result_name) or false
end

local function is_placeable_on_tile_prototype(entry, tile_prototype)
  return paving.matches(entry.normalized, paving.normalize_tile(tile_prototype, tile_prototype_name))
end

local function position_key(position)
  return math.floor(position.x) .. "_" .. math.floor(position.y)
end

--- Returns {name, entry} if `candidate_entry` is a viable underlay for
--- the selection's target entry on `tile` (currently obtainable by the
--- selecting force, usable on this surface, placeable on `tile`, and the
--- target in turn placeable on its result), or nil otherwise. `context` is
--- a selection_context.
local function underlay_candidate(context, tile, name, candidate_entry)
  if context.on_platform and not usable_on_platform(candidate_entry) then
    return nil
  end

  if not is_available(candidate_entry, context.force) then
    return nil
  end

  -- is_already_paved keeps the engine check from treating a frozen variant
  -- of the candidate's own result as coverable terrain (thawing it is not
  -- underlaying).
  if is_already_paved(tile, candidate_entry)
    or not can_place_tile_ghost(context.surface, tile.position, candidate_entry.result_name, context.force) then
    return nil
  end

  local result_tile = prototypes.tile[candidate_entry.result_name]
  if not result_tile then
    return nil
  end

  if not is_placeable_on_tile_prototype(context.entry, result_tile) then
    return nil
  end

  return {name = name, entry = candidate_entry}
end

--- Finds a generic "underlay" item (e.g. landfill) whose place_as_tile is
--- valid on `tile`, and whose result tile the selection's target entry
--- would in turn be placeable on. Only considers items the selecting force
--- can currently obtain -- unresearched items are treated as if they didn't
--- exist. Prefers the most specific candidate (narrowest `tile_condition`)
--- so a cheap, purpose-built item like landfill is chosen over a broad,
--- general-purpose one like foundation; ties break alphabetically for
--- determinism.
local function choose_underlay(context, tile)
  local candidates = {}
  for name, candidate_entry in pairs(get_paving_items()) do
    local candidate = underlay_candidate(context, tile, name, candidate_entry)
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

--- Whether `entry` can reclaim some water/lava tile (see `water_layer`) for
--- another paving item that couldn't go there directly -- e.g. landfill's
--- result tile accepts concrete, and unlike concrete, landfill also covers
--- water. Restricted to that one layer rather than any collision-mask
--- difference: plain paving items can differ from each other too (e.g.
--- Aquilo's meltable ice blocks stone brick but not concrete), and that's a
--- gameplay-balance distinction between paving items, not the "opens up
--- otherwise off-limits terrain" trait that makes something an underlay.
--- Independent of any specific tile, force research state, or platform -- a
--- tile-agnostic classification for display purposes, not the precise
--- per-tile check `choose_underlay` performs when actually placing ghosts.
local function compute_underlay_capability(name, entry)
  local result_tile = prototypes.tile[entry.result_name]
  if not result_tile then
    return false
  end
  for other_name, other_entry in pairs(get_paving_items()) do
    if other_name ~= name and is_placeable_on_tile_prototype(other_entry, result_tile) then
      for _, tile_prototype in pairs(prototypes.tile) do
        local mask = tile_prototype.collision_mask
        if mask and mask.layers and mask.layers[water_layer]
          and is_placeable_on_tile_prototype(entry, tile_prototype)
          and not is_placeable_on_tile_prototype(other_entry, tile_prototype) then
          return true
        end
      end
    end
  end
  return false
end

--- Memoized front of compute_underlay_capability: O(items^2 x tile
--- prototypes) over immutable prototypes only, so each item is classified at
--- most once per game load instead of on every announcement.
local function can_serve_as_underlay(name, entry)
  if underlay_capability[name] == nil then
    underlay_capability[name] = compute_underlay_capability(name, entry)
  end
  return underlay_capability[name]
end

--- Shows flying text at `player`'s position naming the paving item `name`,
--- noting when it could also serve as an underlay for other paving items.
--- Does nothing if `name` no longer exists (an announcement queued in
--- `storage` can outlive its item's mod across a save/load).
local function announce_paving_item(player, name)
  local entry = get_paving_items()[name]
  if not entry then
    return
  end
  local message_key = can_serve_as_underlay(name, entry)
    and "select-and-pave-messages.now-paving-underlay"
    or "select-and-pave-messages.now-paving"
  player.create_local_flying_text({
    text = {message_key, "[item=" .. name .. "]", prototypes.item[name].localised_name},
    position = player.position,
  })
end

-- Scrolling to rotate items can fire rotate_item() several times a second,
-- and each call's flying text is independent -- the engine has no way to
-- replace or cancel one already on screen, so back-to-back calls stack up
-- illegibly. Queuing the announcement and re-timing it on every call instead
-- of showing it immediately means only the item scrolling settles on, after
-- ANNOUNCE_DELAY_TICKS of no further calls, actually gets announced.
local ANNOUNCE_DELAY_TICKS = 20

--- Replaces any not-yet-shown announcement for `player` with one for `name`,
--- due ANNOUNCE_DELAY_TICKS from now.
local function queue_paving_announcement(player, name)
  storage.pending_announce = storage.pending_announce or {}
  storage.pending_announce[player.index] = {name = name, at_tick = game.tick + ANNOUNCE_DELAY_TICKS}
end

--- Extracts the held item's name from a `select-and-pave-tool-<name>`
--- prototype name, or nil if `tool_name` isn't one of ours.
local function held_item_name_from_tool(tool_name)
  if tool_name and tool_name:sub(1, #paving.tool_prefix) == paving.tool_prefix then
    return tool_name:sub(#paving.tool_prefix + 1)
  end
  return nil
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

--- What activating with empty hands should fall back to: the last item the
--- player paved with, treated like a real stack if they still have one in
--- inventory (its quality is returned so that exact stack is restored
--- afterwards) or like a cursor_ghost preview otherwise. Returns the same
--- name, quality, from_ghost triple as get_held_item_name, or nil if they
--- never paved, the item no longer exists, or there is no cursor to equip.
local function last_used_item(player)
  local last_used = storage.last_used[player.index]
  if not last_used or not get_paving_items()[last_used] or not player.cursor_stack then
    return nil
  end

  local stack = find_inventory_stack(player, last_used)
  if stack then
    return last_used, stack.quality.name, false
  end
  return last_used, nil, true
end

local function activate(player)
  -- Already holding our selection tool (common with keep-tool on): there is
  -- nothing to swap, so just re-announce what it paves with -- without this
  -- the tool itself would be read as the held item and, not being a paving
  -- item, trip the "hold a paving item" message.
  local cursor_stack = player.cursor_stack
  local tool_item_name = cursor_stack and cursor_stack.valid_for_read
    and held_item_name_from_tool(cursor_stack.name)
  if tool_item_name then
    queue_paving_announcement(player, tool_item_name)
    return
  end

  local held_name, held_quality, from_ghost = get_held_item_name(player)
  if not held_name then
    held_name, held_quality, from_ghost = last_used_item(player)
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

  storage.pending[player.index] = {name = held_name, from_ghost = from_ghost, quality = held_quality}
  player.cursor_stack.set_stack({name = paving.tool_prefix .. held_name, count = 1})
  queue_paving_announcement(player, held_name)
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

--- Item names from get_paving_items(), sorted for deterministic rotation.
local function sorted_paving_item_names()
  local names = {}
  for name in pairs(get_paving_items()) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- Set of item names present in the player's main inventory, built from a
--- single get_contents() pass -- for possession checks that don't need the
--- LuaItemStack itself (unlike find_inventory_stack's per-slot scan).
local function inventory_item_names(player)
  local names = {}
  local inventory = player.get_main_inventory()
  if inventory then
    for _, item in pairs(inventory.get_contents()) do
      names[item.name] = true
    end
  end
  return names
end

--- Item names `player` may rotate to: either they already have a real stack
--- of it, or `force` can currently obtain it. An item with neither (no
--- stack in hand and unresearched) is excluded entirely, matching
--- activate()'s refusal to open on an unresearched cursor_ghost preview.
local function rotation_candidates(player)
  local owned = inventory_item_names(player)
  local candidates = {}
  for _, name in pairs(sorted_paving_item_names()) do
    local entry = get_paving_items()[name]
    if owned[name] or is_available(entry, player.force) then
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
  storage.pending[player.index] = {name = next_name, from_ghost = not next_stack}
  player.cursor_stack.set_stack({name = paving.tool_prefix .. next_name, count = 1})
  queue_paving_announcement(player, next_name)
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
--- there, recording it in the context's `existing_ghosts` either way.
local function place_ghost_once(context, tile, tile_name)
  local key = ghost_key(tile.position, tile_name)
  if context.existing_ghosts[key] then
    return
  end
  place_ghost(context.surface, context.player, tile.position, tile_name)
  context.existing_ghosts[key] = true
end

local function process_tile(context, tile)
  local entry = context.entry
  if context.on_platform and not usable_on_platform(entry) then
    return
  end

  -- Decided here rather than left to the engine check: the engine happily
  -- re-places a tile over its own frozen variant (that's how thawing works),
  -- and this also stops the underlay search below from treating a tile that
  -- needs nothing as blocked (see is_already_paved).
  if is_already_paved(tile, entry) then
    return
  end

  if can_place_tile_ghost(context.surface, tile.position, entry.result_name, context.force) then
    place_ghost_once(context, tile, entry.result_name)
    return
  end

  if not context.is_alt then
    return
  end

  -- choose_underlay scans every paving item against every tile in the
  -- selection, but its result depends only on the tile's name (everything
  -- else it reads is fixed in the context), so large drags over uniform
  -- terrain would repeat the same scan tens of thousands of times. `false`
  -- records "no underlay" so misses are cached too. The engine check inside
  -- is positional, so for an item with condition_size > 1 the cached answer
  -- could differ between same-named tiles; vanilla items are all size 1.
  local underlay = context.underlay_cache[tile.name]
  if underlay == nil then
    underlay = choose_underlay(context, tile) or false
    context.underlay_cache[tile.name] = underlay
  end
  if not underlay then
    return
  end

  -- Stack both ghosts at once; robots build the underlay (e.g. landfill)
  -- first and the target tile once the underlay makes the position valid
  -- for it, without this MOD tracking the handoff itself. Each is deduped
  -- independently, so an underlay ghost placed earlier (by this MOD, a
  -- blueprint, or anything else) doesn't block the target ghost from still
  -- being added on top of it.
  place_ghost_once(context, tile, underlay.entry.result_name)
  place_ghost_once(context, tile, entry.result_name)
end

--- Everything about one selection that is fixed across its tiles -- who is
--- paving what, where -- plus the two caches scoped to it. Threaded through
--- process_tile and the underlay search instead of a long parameter list.
local function selection_context(player, event, entry, is_alt)
  local surface = event.surface
  return {
    surface = surface,
    player = player,
    force = player.force,
    entry = entry,
    is_alt = is_alt,
    on_platform = surface.platform ~= nil,
    existing_ghosts = collect_existing_ghosts(surface, event.area, player.force),
    underlay_cache = {},
  }
end

local function place_ghosts(player, event, entry, is_alt)
  if not entry then
    return
  end

  local context = selection_context(player, event, entry, is_alt)
  for _, tile in pairs(event.tiles) do
    process_tile(context, tile)
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

  local player = game.get_player(event.player_index)
  local entry = get_paving_items()[held_name]

  place_ghosts(player, event, entry, is_alt)
  if entry then
    storage.last_used[event.player_index] = held_name
  end

  -- With keep-tool on, the tool session just continues: `pending` stays so
  -- rotation and the cursor-changed handler keep working, and the latter is
  -- what eventually restores the held item once the player clears the tool.
  if settings.get_player_settings(player)[keep_tool_setting].value then
    return
  end
  storage.pending[event.player_index] = nil
  restore_cursor(player, held_name, pending.quality, pending.from_ghost)
end

-- Every storage field this MOD uses, initialized both on first install
-- (on_init) and when a save made with an older version that lacks some of
-- them is loaded (on_configuration_changed). New fields only need a line
-- here.
local function init_storage()
  storage.pending = storage.pending or {}
  storage.last_used = storage.last_used or {}
  storage.pending_announce = storage.pending_announce or {}
end

script.on_init(init_storage)
script.on_configuration_changed(init_storage)

script.on_nth_tick(6, function()
  for player_index, announcement in pairs(storage.pending_announce) do
    if game.tick >= announcement.at_tick then
      local player = game.get_player(player_index)
      if player then
        announce_paving_item(player, announcement.name)
      end
      storage.pending_announce[player_index] = nil
    end
  end
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
  local pending = storage.pending[event.player_index]
  if not pending then
    return
  end
  local player = game.get_player(event.player_index)
  local cursor_stack = player.cursor_stack
  local holding_tool = cursor_stack and cursor_stack.valid_for_read
    and held_item_name_from_tool(cursor_stack.name) ~= nil
  if holding_tool then
    return
  end
  storage.pending[event.player_index] = nil

  -- Cancelling the selection (Q) destroys the only-in-cursor tool and leaves
  -- the hand empty; give back what activate() swapped out, same as selection
  -- completion does. If the cursor instead holds something else now (the
  -- player switched to another item themselves), leave their choice alone.
  -- pending.name can be nil in a save from before it was recorded, or name
  -- an item whose mod is gone (same staleness as equip_last_used guards).
  local hand_empty = not (cursor_stack and cursor_stack.valid_for_read) and not player.cursor_ghost
  if hand_empty and pending.name and get_paving_items()[pending.name] then
    restore_cursor(player, pending.name, pending.quality, pending.from_ghost)
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
