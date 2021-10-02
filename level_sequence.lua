local custom_levels = require("CustomLevels/custom_levels")
custom_levels.set_directory("LevelSequence/CustomLevels")
local button_prompts = require("ButtonPrompts/button_prompts")

local level_sequence = {}

local sequence_state = {
    levels = {},
    -- Stores the desired levels if changed while not in the camp. Will set levels with
    -- these upon entering camp.
    buffered_levels = {},
    -- Whether each level acts as a checkpoint. If false, the run will reset on the first level
    -- upon each death/reset.
    keep_progress = true,
}

--------------------------------------
---- CALLBACKS
--------------------------------------

local sequence_callbacks = {
    -- Called during level gen just before unloading the previous level.
    on_level_will_unload = nil,
    -- Called during level gen just before loading the current level.
    on_level_will_load = nil,
    -- Called during post level generation, after the level state has been configured.
    on_post_level_generation = nil,
    -- Called when resetting the run if keep progress is not enabled.
    on_reset_run = nil,
    -- Called in the transition after a level has been completed.
    on_completed_level = nil,
    -- Called in the transition after the last level has been completed.
    on_win = nil,
    -- Called in the base camp when the initial level is updated.
    on_prepare_initial_level = nil,
}

-- Set the callback that will be called just before unloading a level.
--
-- Callback signature:
--   level: Level that will be unloaded
level_sequence.set_on_level_will_unload = function(callback)
    sequence_callbacks.on_level_will_unload = callback
end

-- Set the callback that will be called just before loading a level.
--
-- Callback signature:
--   level: Level that will be loaded
level_sequence.set_on_level_will_load = function(callback)
    sequence_callbacks.on_level_will_load = callback
end

-- Set the callback that will be called on POST_LEVEL_GENERATION just after the level and
-- doors have been configured.
--
-- Callback signature:
--   level: Level that is currently loaded.
level_sequence.set_on_post_level_generation = function(on_post_level_generation)
    sequence_callbacks.on_post_level_generation = on_post_level_generation
end

-- Set the callback that will be called when the run is reset back to the first level.
-- This callback will never be called if keep_progress is true.
level_sequence.set_on_reset_run = function(on_reset_run)
    sequence_callbacks.on_reset_run = on_reset_run
end

-- Set the callback that will be called when a level is completed.
--
-- Callback signature:
--   completed_level: The level that was just completed.
--   next_level: The level that will be loaded next.
level_sequence.set_on_completed_level = function(on_completed_level)
    sequence_callbacks.on_completed_level = on_completed_level
end

-- Set the callback that will be called when the final level is completed.
--
-- Callback signature:
--   attempts: Number of attempts that it took to complete the sequence. Each reset/game exit counts
--             towards the attempt counter.
--   time: Total amount of time it took to complete all levels.
level_sequence.set_on_win = function(on_win)
    sequence_callbacks.on_win = on_win
end

-- Set the callback that will be called in the camp to change the initial level when
-- walking near a shortcut door or the continue run door.
--
-- Callback signature:
--   level: Initial level that will be loaded when going through an entrance door.
--   continuing_run: True if going through the continue door. Otherwise, false.
level_sequence.set_on_prepare_initial_level = function(on_prepare_initial_level)
    sequence_callbacks.on_prepare_initial_level = on_prepare_initial_level
end

--------------------------------------
---- /CALLBACKS
--------------------------------------

local internal_callbacks = {
    entrance_tile_code_callback = nil,
}

local run_state = {
    initial_level = nil,
    current_level = nil,
    attempts = 0,
    total_time = 0,
    run_started = false,
}

level_sequence.get_run_state = function()
    return {
        initial_level = run_state.initial_level,
        current_level = run_state.current_level,
        attempts = run_state.attempts,
        total_time = state.time_total,
    }
end

level_sequence.run_in_progress = function()
    return run_state.run_started
end

level_sequence.set_keep_progress = function(keep_progress)
    sequence_state.keep_progress = keep_progress
end
local function equal_levels(level_1, level_2)
    if not level_1 or not level_2 then return end
    return level_1 == level_2 or (level_1.identifier ~= nil and level_1.identifier == level_2.identifier)
end

level_sequence.took_shortcut = function()
    return run_state.initial_level and #sequence_state.levels > 0 and not equal_levels(run_state.initial_level, sequence_state.levels[1])
end

local function index_of_level(level)
    if not level then return nil end
    for index, level_at in pairs(sequence_state.levels) do
        if equal_levels(level, level_at) then
            return index
        end
    end
    return nil
end
level_sequence.index_of_level = index_of_level

local function next_level(level)
    level = level or run_state.current_level
    local index = index_of_level(level)
    if not index then return nil end

    return sequence_state.levels[index+1]
end

----------------
---- THEMES ----
----------------

local function level_for_theme(theme)
	return 5
end

local function level_for_level(level)
	return level_for_theme(level.theme)
end

local function world_for_theme(theme)
	if theme == THEME.DWELLING then
		return 1
	elseif theme == THEME.VOLCANA then
		return 2
	elseif theme == THEME.JUNGLE then
		return 2
	elseif theme == THEME.OLMEC then
		return 3
	elseif theme == THEME.TIDE_POOL then
		return 4
	elseif theme == THEME.TEMPLE then
		return 4
	elseif theme == THEME.ICE_CAVES then
		return 5
	elseif theme == THEME.NEO_BABYLON then
		return 6
	elseif theme == THEME.SUNKEN_CITY then
		return 7
	elseif theme == THEME.CITY_OF_GOLD then
		return 4
	elseif theme == THEME.DUAT then
		return 4
	elseif theme == THEME.ABZU then
		return 4
	elseif theme == THEME.TIAMAT then
		return 6
	elseif theme == THEME.EGGPLANT_WORLD then
		return 7
	elseif theme == THEME.HUNDUN then
		return 7
	elseif theme == THEME.BASE_CAMP then
		return 1
	elseif theme == THEME.ARENA then
		return 1
	elseif theme == THEME.COSMIC_OCEAN then
		return 7
	end
	return 1
end

local function world_for_level(level)
	return world_for_theme(level.theme)
end

-----------------
---- /THEMES ----
-----------------

--------------------------
---- LEVEL GENERATION ----
--------------------------

local loaded_level = nil
local function load_level(level, ctx)
	if loaded_level then
        if sequence_callbacks.on_level_will_unload then
            sequence_callbacks.on_level_will_unload(loaded_level)
        end
		loaded_level.unload_level()
		custom_levels.unload_level()
	end

    loaded_level = level
	if not loaded_level then return end

    if sequence_callbacks.on_level_will_load then
        sequence_callbacks.on_level_will_load(loaded_level)
    end
	loaded_level.load_level()
	custom_levels.load_level(level.file_name, level.width, level.height, ctx)
end

set_callback(function(ctx)
    -- Unload any loaded level when entering the base camp or the title screen.
	if state.theme == THEME.BASE_CAMP or state.theme == 0 then
		load_level(nil)
		return
	end
	local level = run_state.current_level
	load_level(level, ctx)
end, ON.PRE_LOAD_LEVEL_FILES)

---------------------------
---- /LEVEL GENERATION ----
---------------------------

----------------------
---- CONTINUE RUN ----
----------------------

local function load_co_subtheme(level)
    if level.theme == THEME.COSMIC_OCEAN and level.co_subtheme then
        force_co_subtheme(level.co_subtheme)
    else
        force_co_subtheme(COSUBTHEME.RESET)
    end
end

local function load_run(level, attempts, time)
    run_state.initial_level = sequence_state.levels[1]
    run_state.current_level = level
    run_state.attempts = attempts
    run_state.total_time = time
    load_co_subtheme(level)
end

local function load_shortcut(level)
    run_state.current_level = level
    run_state.initial_level = level
    run_state.attempts = 0
    run_state.total_time = 0
    load_co_subtheme(level)
end

-----------------------
---- /CONTINUE RUN ----
-----------------------

---------------------------
---- LEVEL TRANSITIONS ----
---------------------------

set_callback(function()
    local previous_level = run_state.current_level
    local current_level = next_level()
    run_state.current_level = current_level
    if sequence_callbacks.on_completed_level then
        sequence_callbacks.on_completed_level(previous_level, current_level)
    end
    if not current_level then
        if sequence_callbacks.on_win then
            run_state.run_started = false
            sequence.state.on_win(run_state.attempts, state.time_total)
        end
    else
        load_co_subtheme(current_level)
    end
end, ON.TRANSITION)

----------------------------
---- /LEVEL TRANSITIONS ----
----------------------------

------------------------------
---- TIME SYNCHRONIZATION ----
------------------------------

-- Since we are keeping track of time for the entire run even through deaths and resets, we must track
-- what the time was on resets and level transitions.
set_callback(function()
    if state.theme == THEME.BASE_CAMP or not run_state.run_started then return end
    if sequence_state.keep_progress then
        -- Save the time on reset so we can keep the timer going.
        run_state.total_time = state.time_total
    else
        -- Reset the time when keep progress is disabled; the run is going to be reset.
        run_state.total_time = 0
    end
end, ON.RESET)

set_callback(function()
    if state.theme == THEME.BASE_CAMP or not run_state.run_started then return end
    run_state.total_time = state.time_total
end, ON.TRANSITION)

set_callback(function()
    if state.theme == THEME.BASE_CAMP then return end
    state.time_total = run_state.total_time
end, ON.POST_LEVEL_GENERATION)

set_callback(function()
    if state.theme == THEME.BASE_CAMP then return end
    run_state.run_started = true
    run_state.attempts = run_state.attempts + 1
end, ON.START)

set_callback(function()
    run_state.run_started = false
    run_state.attempts = 0
    run_state.current_level = nil
    run_state.total_time = 0
end, ON.CAMP)

-------------------------------
---- /TIME SYNCHRONIZATION ----
-------------------------------

-- Reset the run state if the game is reset and keep progress is not enabled.
set_callback(function()
    if not sequence_state.keep_progress then
        run_state.current_level = run_state.initial_level
        run_state.attempts = 0
        if sequence_callbacks.on_reset_run then
            sequence_callbacks.on_reset_run()
        end
    end
end, ON.RESET)

set_callback(function()
    if state.theme == THEME.BASE_CAMP then return end
    local current_level = run_state.current_level
    local next_level_file = next_level()
    if not current_level then return end
    
    -- This doesn't affect anything except what is displayed in the UI.
	state.world = current_level.world or index_of_level(current_level)
    state.level = current_level.level or 1

    if sequence_state.keep_progress then
		-- Setting the _start properties of the state will ensure that Instant Restarts will take
        -- the player back to the current level, instead of going to the starting level.
		state.world_start = world_for_level(current_level)
		state.level_start = level_for_level(current_level)
		state.theme_start = current_level.theme
    end

	local exit_uids = get_entities_by_type(ENT_TYPE.FLOOR_DOOR_EXIT)
	for _, exit_uid in pairs(exit_uids) do
		local exit_ent = get_entity(exit_uid)
		if exit_ent then
			exit_ent.entered = false
			exit_ent.special_door = true
			if not next_level_file then
				-- The door in the final level will take the player back to the camp.
				exit_ent.world = 1
				exit_ent.level = 1
				exit_ent.theme = THEME.BASE_CAMP
			else
				-- Sets the theme of the door to the theme of the next level we will load.
				exit_ent.world = world_for_level(next_level_file)
				exit_ent.level = level_for_level(next_level_file)
				exit_ent.theme = next_level_file.theme
			end
		end
	end

    if sequence_callbacks.on_post_level_generation then
        sequence_callbacks.on_post_level_generation(current_level)
    end
end, ON.POST_LEVEL_GENERATION)

--------------
---- CAMP ----
--------------

local function texture_for_theme(theme, co_subtheme)
    if theme == THEME.DWELLING then
        return TEXTURE.DATA_TEXTURES_FLOOR_CAVE_2
    elseif theme == THEME.VOLCANA then
        return TEXTURE.DATA_TEXTURES_FLOOR_VOLCANO_2
    elseif theme == THEME.JUNGLE then
        return TEXTURE.DATA_TEXTURES_FLOOR_JUNGLE_1
    elseif theme == THEME.OLMEC then
        return TEXTURE.DATA_TEXTURES_DECO_JUNGLE_2
    elseif theme == THEME.TIDE_POOL then
        return TEXTURE.DATA_TEXTURES_FLOOR_TIDEPOOL_3
    elseif theme == THEME.TEMPLE then
        return TEXTURE.DATA_TEXTURES_FLOOR_TEMPLE_1
    elseif theme == THEME.ICE_CAVES then
        return TEXTURE.DATA_TEXTURES_FLOOR_ICE_1
    elseif theme == THEME.NEO_BABYLON then
        return TEXTURE.DATA_TEXTURES_FLOOR_BABYLON_1
    elseif theme == THEME.SUNKEN_CITY then
        return TEXTURE.DATA_TEXTURES_FLOOR_SUNKEN_3
    elseif theme == THEME.CITY_OF_GOLD then
        return TEXTURE.DATA_TEXTURES_FLOOR_TEMPLE_4
    elseif theme == THEME.DUAT then
        return TEXTURE.DATA_TEXTURES_FLOOR_TEMPLE_1
    elseif theme == THEME.ABZU then
        return TEXTURE.DATA_TEXTURES_FLOOR_TIDEPOOL_3
    elseif theme == THEME.TIAMAT then
        return TEXTURE.DATA_TEXTURES_FLOOR_TIDEPOOL_3
    elseif theme == THEME.EGGPLANT_WORLD then
        return TEXTURE.DATA_TEXTURES_FLOOR_EGGPLANT_2
    elseif theme == THEME.HUNDUN then
        return TEXTURE.DATA_TEXTURES_FLOOR_SUNKEN_3
    elseif theme == THEME.BASE_CAMP then
        return TEXTURE.DATA_TEXTURES_FLOOR_CAVE_2
    elseif theme == THEME.ARENA then
        return TEXTURE.DATA_TEXTURES_FLOOR_CAVE_2
    elseif theme == THEME.COSMIC_OCEAN then
        if co_subtheme == COSUBTHEME.DWELLING then
            return TEXTURE.DATA_TEXTURES_FLOOR_CAVE_2
        elseif co_subtheme == COSUBTHEME.JUNGLE then
            return TEXTURE.DATA_TEXTURES_FLOOR_JUNGLE_1
        elseif co_subtheme == COSUBTHEME.VOLCANA then
            return TEXTURE.DATA_TEXTURES_FLOOR_VOLCANO_2
        elseif co_subtheme == COSUBTHEME.TIDE_POOL then
            return TEXTURE.DATA_TEXTURES_FLOOR_TIDEPOOL_3
        elseif co_subtheme == COSUBTHEME.TEMPLE then
            return TEXTURE.DATA_TEXTURES_FLOOR_TEMPLE_1
        elseif co_subtheme == COSUBTHEME.ICE_CAVES then
            return TEXTURE.DATA_TEXTURES_FLOOR_ICE_1
        elseif co_subtheme == COSUBTHEME.NEO_BABYLON then
            return TEXTURE.DATA_TEXTURES_FLOOR_BABYLON_1
        elseif co_subtheme == COSUBTHEME.SUNKEN_CITY then
            return TEXTURE.DATA_TEXTURES_FLOOR_SUNKEN_3
        end
    end
    return TEXTURE.DATA_TEXTURES_FLOOR_CAVE_2
end

local function texture_for_level(level)
    return texture_for_theme(level.theme, level.co_subtheme)
end

local main_exits = {}
local shortcuts = {}
local continue_door = nil
set_callback(function()	-- Replace the main entrance door with a door that leads to the first level (Dwelling).
    local entrance_uids = get_entities_by_type(ENT_TYPE.FLOOR_DOOR_MAIN_EXIT)
    main_exits = {}
    if #entrance_uids > 0 then
        local entrance_uid = entrance_uids[1]
		local first_level = sequence_state.levels[1]
        -- kill_entity(entrance_uid)
        local x, y, layer = get_position(entrance_uid)
        local entrance = get_entity(entrance_uid)
        entrance.flags = clr_flag(entrance.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
        local door = spawn_door(
			x,
			y,
			layer,
			world_for_level(first_level),
			level_for_level(first_level),
			first_level.theme)
        main_exits[#main_exits+1] = get_entity(door)
    end
end, ON.CAMP)

set_callback(function()
    main_exits = {}
    shortcuts = {}
    continue_door = nil
end, ON.LEVEL)

local function update_main_exits()
    local first_level = sequence_state.levels[1]
    for _, main_exit in pairs(main_exits) do
        main_exit.world = world_for_level(first_level)
        main_exit.level = level_for_level(first_level)
        main_exit.theme = first_level.theme
    end
end
level_sequence.update_main_exits = update_main_exits

local SIGN_TYPE = {
    NONE = 0,
    LEFT = 1,
    RIGHT = 2,
}
level_sequence.SIGN_TYPE = SIGN_TYPE

level_sequence.spawn_shortcut = function(x, y, layer, level, include_sign, sign_text)
    include_sign = include_sign or SIGN_TYPE.NONE
    local background_uid = spawn_entity(ENT_TYPE.BG_DOOR, x, y+.25, layer, 0, 0)
    local door_uid = spawn_door(x, y, layer, world_for_level(level), level_for_level(level), level.theme)
    local door = get_entity(door_uid)
    local background = get_entity(background_uid)
    background:set_texture(texture_for_level(level))
    background.animation_frame = set_flag(background.animation_frame, 1)

    local sign
    local tv
    if include_sign ~= SIGN_TYPE.NONE then
        local sign_position_x = x
        if include_sign == SIGN_TYPE.LEFT then
            sign_position_x = x - 2
        elseif include_sign == SIGN_TYPE.RIGHT then
            sign_position_x = x + 2
        end
        local sign_uid = spawn_entity(ENT_TYPE.ITEM_SPEEDRUN_SIGN, sign_position_x, y, layer, 0, 0)
        sign = get_entity(sign_uid)
        -- This stops the sign from displaying its default toast text when pressing the door button.
        sign.flags = clr_flag(sign.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
        local tv_uid = button_prompts.spawn_button_prompt(button_prompts.PROMPT_TYPE.VIEW, sign_position_x, y, layer)
        tv = get_entity(tv_uid)
    end
    local shortcut = {
        level = level,
        door = door,
        sign = sign,
        sign_text = sign_text or f'Shortcut to {level.title}',
    }
    local destroyed = false
    shortcut.destroy = function()
        if destroyed then return end
        destroyed = true
        door:destroy()
        background:destroy()
        if sign then
            sign:destroy()
        end
        if tv then
            tv:destroy()
        end

        local new_shortcuts = {}
        for _, new_shortcut in pairs(shortcuts) do
            if new_shortcut ~= shortcut then
                new_shortcuts[#new_shortcuts+1] = new_shortcut
            end
        end
        shortcuts = new_shortcuts
    end
    shortcuts[#shortcuts+1] = shortcut
    return shortcut
end

level_sequence.spawn_continue_door = function(x, y, layer, level, attempts, time, include_sign, sign_text, disabled_sign_text, no_run_sign_text)
    include_sign = include_sign or SIGN_TYPE.NONE
    local background_uid = spawn_entity(ENT_TYPE.BG_DOOR, x, y+.25, layer, 0, 0)
    local door_uid = spawn_door(x, y, layer, world_for_level(level), level_for_level(level), level.theme)
    local door = get_entity(door_uid)
    local background = get_entity(background_uid)
    background.animation_frame = set_flag(background.animation_frame, 1)
    
    local function update_door_for_level(level)
        background:set_texture(texture_for_level(level))
        if not level or not sequence_state.keep_progress then
            door.flags = clr_flag(door.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
        else
            door.flags = set_flag(door.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
        end
        door.world = world_for_level(level)
        door.level = level_for_level(level)
        door.theme = level.theme
    end

    update_door_for_level(level)

    local sign
    local tv
    if include_sign ~= SIGN_TYPE.NONE then
        local sign_position_x = x
        if include_sign == SIGN_TYPE.LEFT then
            sign_position_x = x - 2
        elseif include_sign == SIGN_TYPE.RIGHT then
            sign_position_x = x + 2
        end
        local sign_uid = spawn_entity(ENT_TYPE.ITEM_SPEEDRUN_SIGN, sign_position_x, y, layer, 0, 0)
        sign = get_entity(sign_uid)
        -- This stops the sign from displaying its default toast text when pressing the door button.
        sign.flags = clr_flag(sign.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
        local tv_uid = button_prompts.spawn_button_prompt(button_prompts.PROMPT_TYPE.VIEW, sign_position_x, y, layer)
        tv = get_entity(tv_uid)
    end
    continue_door = {
        level = level,
        attempts = attempts,
        time = time,
        door = door,
        sign = sign,
        sign_text = sign_text,
        disabled_sign_text = disabled_sign_text,
        no_run_sign_text = no_run_sign_text,
    }
    continue_door.update_door = function(level, attempts, time, sign_text, disabled_sign_text, no_run_sign_text)
        continue_door.level = level
        continue_door.attempts = attempts
        continue_door.time = time
        continue_door.sign_text = sign_text
        continue_door.disabled_sign_text = disabled_sign_text
        continue_door.no_run_sign_text = no_run_sign_text
        update_door_for_level(level)
    end
    local destroyed = false
    continue_door.destroy = function()
        if destroyed then return end
        destroyed = true
        door:destroy()
        background:destroy()
        if sign then
            sign:destroy()
        end
        if tv then
            tv:destroy()
        end
        continue_door = nil
    end
    return continue_door
end


set_callback(function()
    if #players < 1 then return end
    if state.theme ~= THEME.BASE_CAMP then return end
    local player = players[1]
    for _, shortcut in pairs(shortcuts) do
        if (shortcut.door and distance(player.uid, shortcut.door.uid) <= 1) or 
                (shortcut.sign and distance(player.uid, shortcut.sign.uid) <= 1) then
            load_shortcut(shortcut.level)
            if sequence_callbacks.on_prepare_initial_level then
                sequence_callbacks.on_prepare_initial_level(shortcut.level, false)
            end
            return
        end
    end
    if continue_door ~= nil and
            continue_door.level ~= nil and
            sequence_state.keep_progress and
            ((continue_door.door and distance(player.uid, continue_door.door.uid) <= 1) or
             (continue_door.sign and distance(player.uid, continue_door.sign.uid) <= 1)) then
        load_run(continue_door.level, continue_door.attempts, continue_door.time)
        if sequence_callbacks.on_prepare_initial_level then
            sequence_callbacks.on_prepare_initial_level(continue_door.level, true)
        end
        return
    end
    -- If not next to any door, just set the state to the initial level. 
    load_shortcut(sequence_state.levels[1])
    if sequence_callbacks.on_prepare_initial_level then
        sequence_callbacks.on_prepare_initial_level(sequence_state.levels[1], false)
    end
end, ON.GAMEFRAME)

set_callback(function()
    if state.theme ~= THEME.BASE_CAMP then return end
    if #players < 1 then return end
    local player = players[1]

	-- Show a toast when pressing the door button on the signs near shortcut doors and continue door.
    if player:is_button_pressed(BUTTON.DOOR) then
        for _, shortcut in pairs(shortcuts) do
            if shortcut.sign and
                    player.layer == shortcut.sign.layer and
                    distance(player.uid, shortcut.sign.uid) <= 0.5 then
                toast(shortcut.sign_text)
            end
        end
        if continue_door and
                continue_door.sign and
                player.layer == continue_door.sign.layer and
                distance(player.uid, continue_door.sign.uid) <= 0.5 then
            if not sequence_state.keep_progress then
                toast(continue_door.disabled_sign_text or "Cannot continue in hardcore mode")
            elseif continue_door.level then
                toast(continue_door.sign_text or f'Continue run from {continue_door.level.title}')
            else
                toast(continue_door.no_run_sign_text or "No run to continue")
            end
        elseif continue_door and
                continue_door.door and
                not continue_door.level and
                player.layer == continue_door.door.layer and
                distance(player.uid, continue_door.door.uid) <= 0.5 then
            toast(continue_door.no_run_sign_text or "No run to continue")
        elseif continue_door and
                continue_door.door and
                not sequence_state.keep_progress and
                player.layer == continue_door.door.layer and
                distance(player.uid, continue_door.door.uid) <= 0.5 then
            toast(continue_door.disabled_sign_text or "Cannot continue in hardcore mode")
        end
    end
end, ON.GAMEFRAME)

---------------
---- /CAMP ----
---------------

-- Allow clients to interact with copies of the level list so that they cannot rearrange, add,
-- or remove levels without going through these methods.
level_sequence.levels = function()
    local levels = {}
    for index, level in pairs(sequence_state.levels) do
        levels[index] = level
    end
    return levels
end

level_sequence.set_levels = function(levels)
    local new_levels = {}
    for index, level in pairs(levels) do
        new_levels[index] = level
    end

    -- Make sure to only update the levels while not in a run.
    if state.theme == THEME.BASE_CAMP or state.theme == 0 then
        sequence_state.levels = new_levels
        sequence_state.buffered_levels = nil
        update_main_exits()
    else
        sequence_state.buffered_levels  = new_levels
    end
end

-- If the levels were updated while on a run, apply the changes when entering the camp.
set_callback(function()
    if sequence_state.buffered_levels then
        sequence_state.levels = sequence_state.buffered_levels
        sequence_state.buffered_levels = nil
        update_main_exits()
    end
end, ON.CAMP)

return level_sequence
