local custom_levels = require("CustomLevels/custom_levels")
custom_levels.set_directory("LevelSequence/CustomLevels")
local button_prompts = require("ButtonPrompts/button_prompts")

local level_sequence = {}

function level_sequence.set_directory(directory)
    if directory then
        custom_levels.set_directory(directory .. "/CustomLevels")
    else
        custom_levels.set_directory("LevelSequence/CustomLevels")
    end
end

local sequence_state = {
    levels = {},
    -- Stores the desired levels if changed while not in the camp. Will set levels with
    -- these upon entering camp.
    buffered_levels = {},
    -- Whether each level acts as a checkpoint. If false, the run will reset on the first level
    -- upon each death/reset.
    keep_progress = true,
    -- If set, these types of procedural spawns will be allowed to spawn in. See custom_levels.ALLOW_SPAWN_TYPE.
    allowed_spawn_types = nil,
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
    -- Called when a level starts.
    on_level_start = nil,
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

-- Set the callback that will be called each time a level starts. This includes both the first
-- time the level is encountered and on every reset.
--
-- Callback signature:
--   level: The level that is being started.
level_sequence.set_on_level_start = function(on_level_start)
    sequence_callbacks.on_level_start = on_level_start
end

--------------------------------------
---- /CALLBACKS
--------------------------------------

--------------------------------------
---- RUN STATE
--------------------------------------

local run_state = {
    initial_level = nil,
    current_level = nil,
    attempts = 0,
    total_time = 0,
    run_started = false,
}

-- Gets the state of the current run that is in progress.
--
-- Return:
--   initial_level: Level the run started on.
--   current_level: Level the player is currently on.
--   attempts: Number of attempts the player currently has in the run. A new attempt is added
--             when starting or continuing a run from the base camp, or on a reset.
--   total_time: The total amount of time the player has spent in the run.
level_sequence.get_run_state = function()
    return {
        initial_level = run_state.initial_level,
        current_level = run_state.current_level,
        attempts = run_state.attempts,
        total_time = state.time_total,
    }
end

-- Whether a run is currently in progress. If false, we are probably in the base camp or the main
-- menu.
--
-- Return: Whether a run is in progress.
level_sequence.run_in_progress = function()
    return run_state.run_started
end

-- Set whether or not to consider each level as a checkpoint. If set to false, will reset the run
-- from the initial_level on resets.
--
-- keep_progress: Whether or not to keep progress on resets.
level_sequence.set_keep_progress = function(keep_progress)
    sequence_state.keep_progress = keep_progress
end

-- Compares two levels to see if they are the same level. Compares identifiers if the objects are not
-- identical, so that two levels with the same identifier are considered to be equal.
--
-- level_1: First of two levels to compare.
-- level_2: Second of two levels to compare.
-- Return: True if the two levels are considered equal, otherwise false.
local function equal_levels(level_1, level_2)
    if not level_1 or not level_2 then return end
    return level_1 == level_2 or (level_1.identifier ~= nil and level_1.identifier == level_2.identifier)
end

-- Whether a shortcut was taken to get into the current run.
level_sequence.took_shortcut = function()
    return run_state.initial_level and #sequence_state.levels > 0 and not equal_levels(run_state.initial_level, sequence_state.levels[1])
end

-- Attempts to get the index of a level within the current levels. Returns nil if no level is
-- passed in or if the level cannot be found in the current levels.
--
-- level: Level to index.
-- Return: Index of the level in the levels list.
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

-- Attempts to get the next level in the levels list after the input level.
--
-- level: Level to find the next level of. If omitted, uses the current_level in the run_state.
-- Return: Next level in the levels list.
local function next_level(level)
    level = level or run_state.current_level
    local index = index_of_level(level)
    if not index then return nil end

    return sequence_state.levels[index+1]
end

--------------------------------------
---- /RUN STATE
--------------------------------------

--------------------------------------
---- THEMES
--------------------------------------

local function theme_for_level(level)
    if not level or not level.theme then return THEME.DWELLING end
    return level.theme
end

local function subtheme_for_level(level)
    if not level or not level.co_subtheme then return COSUBTHEME.RESET end
    return level.co_subtheme
end

-- Gets the level that doors will lead to for a particular theme.
--
-- theme: Theme that the door leads to.
-- Return: Level number that the door will be set to.
local function level_for_theme(theme)
    -- We return 5 to reduce the chances of conflict with special rooms such as black market,
    -- challenges, Vlad's, and also with setrooms in stages such as 1-4.
	return 5
end

-- Gets the level that doors will lead to for a particular level.
--
-- level: Level that the door leads to.
-- Return: Level number that the door will be set to.
local function level_for_level(level)
	return level_for_theme(theme_for_level(level))
end

-- Gets the world that doors will lead to for a particular theme.
--
-- theme: Theme that the door leads to.
-- Return: World number that the door will be set to.
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

-- Gets the world that doors will lead to for a particular level.
--
-- level: Level that the door leads to.
-- Return: World number that the door will be set to.
local function world_for_level(level)
	return world_for_theme(theme_for_level(level))
end

-- Gets the texture that should be used to texture doors for a particular theme.
--
-- theme: Theme that the door leads to.
-- co_subtheme: Theme that the door leads to within the cosmic ocean.
-- Return: Texture to use for doors leading to the theme.
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

-- Gets the texture that should be used to texture doors for a particular level.
--
-- level: Level that the door leads to.
-- Return: Texture to use for doors leading to the level.
local function texture_for_level(level)
    return texture_for_theme(theme_for_level(level), subtheme_for_level(level))
end

--------------------------------------
---- /THEMES
--------------------------------------

--------------------------------------
---- LEVEL GENERATION
--------------------------------------

local loaded_level = nil
-- Load a level. Loads the tile codes and callbacks of the level, then uses custom_levels to load
-- the level file and replace any existing level files.
--
-- level: Level to load.
-- ctx: Context to load the level into.
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
	custom_levels.load_level(level.file_name, level.width, level.height, ctx, sequence_state.allowed_spawn_types)
end

-- Called just before the level files are loaded. It is here that we load the level files
-- for the current level and activate the callbacks of the level.
--
-- ctx: Context to load levels into.
local function pre_load_level_files_callback(ctx)
    -- Unload any loaded level when entering the base camp or the title screen.
	if state.theme == THEME.BASE_CAMP or state.theme == 0 then
		load_level(nil)
		return
	end
	local level = run_state.current_level
	load_level(level, ctx)
end


--------------------------------------
---- /LEVEL GENERATION
--------------------------------------

--------------------------------------
---- SHORTCUT LOADING
--------------------------------------

-- Force the CO subtheme for a level.
-- If the theme of the level is not THEME.COSMIC_OCEAN, the subtheme will instead be reset to
-- a random subtheme.
--
-- level: A level object that should have a theme and co_subtheme values.
local function load_co_subtheme(level)
    if theme_for_level(level) == THEME.COSMIC_OCEAN and level.co_subtheme then
        force_co_subtheme(level.co_subtheme)
    else
        force_co_subtheme(COSUBTHEME.RESET)
    end
end

-- Load in an on-going run from a continue state.
--
-- level: The level that the player is currently on in the run.
-- attempts: The number of attempts the player has on the run.
-- time: The amount of time the player has spent in the run.
local function load_run(level, attempts, time)
    run_state.initial_level = sequence_state.levels[1]
    run_state.current_level = level
    run_state.attempts = attempts
    run_state.total_time = time
    load_co_subtheme(level)
end

-- Load in a shortcut to a level. Sets the initial_level to that level so that resets in hardcore
-- reset at the level.
--
-- level: The level that the shortcut leads to.
local function load_shortcut(level)
    run_state.current_level = level
    run_state.initial_level = level
    run_state.attempts = 0
    run_state.total_time = 0
    load_co_subtheme(level)
end

--------------------------------------
---- /SHORTCUT LOADING
--------------------------------------

--------------------------------------
---- LEVEL TRANSITIONS
--------------------------------------

-- Load the next level on transitions. If we were on the last level, call the on_win callback.
local function transition_increment_level_callback()
    local previous_level = run_state.current_level
    local current_level = next_level()
    run_state.current_level = current_level
    if sequence_callbacks.on_completed_level then
        sequence_callbacks.on_completed_level(previous_level, current_level)
    end
    if not current_level then
        run_state.run_started = false
        if sequence_callbacks.on_win then
            sequence_callbacks.on_win(run_state.attempts, state.time_total)
        end
    else
        load_co_subtheme(current_level)
    end
end

-- Reset the run state if the game is reset and keep progress is not enabled.
local function reset_run_if_hardcore()
    if not sequence_state.keep_progress then
        run_state.current_level = run_state.initial_level
        run_state.attempts = 0
        if sequence_callbacks.on_reset_run then
            sequence_callbacks.on_reset_run()
        end
    end
end

-- Update the display of the world-level to the desired display instead of using the
-- world-level we set for the theme to load properly.
local function update_state_and_doors()
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
		state.theme_start = theme_for_level(current_level)
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
end

--------------------------------------
---- /LEVEL TRANSITIONS
--------------------------------------

--------------------------------------
---- TIME SYNCHRONIZATION
--------------------------------------

-- Since we are keeping track of time for the entire run even through deaths and resets, we must track
-- what the time was on resets and level transitions.
local function save_time_on_reset_callback()
    if state.theme == THEME.BASE_CAMP or not run_state.run_started then return end
    if sequence_state.keep_progress then
        -- Save the time on reset so we can keep the timer going.
        run_state.total_time = state.time_total
    else
        -- Reset the time when keep progress is disabled; the run is going to be reset.
        run_state.total_time = 0
    end
end

-- Save the time of the run on transitions so that the run state is correct on starting
-- the next level.
local function save_time_on_transition_callback()
    if state.theme == THEME.BASE_CAMP or not run_state.run_started then return end
    run_state.total_time = state.time_total
end

-- Set the time in the state so it shows up in the player's HUD.
local function load_time_after_level_generation_callback()
    if state.theme == THEME.BASE_CAMP then return end
    state.time_total = run_state.total_time
end

-- Increase the attempts on level start, and mark the run as started on the first level start so
-- we can begin keeping track of the time.
local function start_level_callback()
    if state.theme == THEME.BASE_CAMP then return end
    run_state.run_started = true
    run_state.attempts = run_state.attempts + 1
    if sequence_callbacks.on_level_start then
        sequence_callbacks.on_level_start(run_state.current_level)
    end
end

local function reset_on_camp_callback()
    run_state.run_started = false
    run_state.attempts = 0
    run_state.current_level = nil
    run_state.total_time = 0
end

--------------------------------------
---- /TIME SYNCHRONIZATION
--------------------------------------

--------------------------------------
---- CAMP
--------------------------------------

local main_exits = {}
local shortcuts = {}
local continue_doors = {}
-- Replace the main entrance door with a door that leads to the first level to begin the run.
local function replace_main_entrance()
    local entrance_uids = get_entities_by_type(ENT_TYPE.FLOOR_DOOR_MAIN_EXIT)
    main_exits = {}
    if #entrance_uids > 0 then
        local entrance_uid = entrance_uids[1]
		local first_level = sequence_state.levels[1]
        local x, y, layer = get_position(entrance_uid)
        local entrance = get_entity(entrance_uid)
        entrance.flags = clr_flag(entrance.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
        local door = spawn_door(
			x,
			y,
			layer,
			world_for_level(first_level),
			level_for_level(first_level),
			theme_for_level(first_level))
        main_exits[#main_exits+1] = get_entity(door)
    end
end

-- Clear the tracked doors in the camp for different shortcut and main entrances.
local function reset_camp_doors()
    main_exits = {}
    shortcuts = {}
    continue_doors = {}
end

-- Updates the main entrance to lead to the current first level in the state. This is
-- called when the levels are updated.
local function update_main_exits()
    local first_level = sequence_state.levels[1]
    for _, main_exit in pairs(main_exits) do
        main_exit.world = world_for_level(first_level)
        main_exit.level = level_for_level(first_level)
        main_exit.theme = theme_for_level(first_level)
    end
end

-- Where to spawn a sign in relation to shortcut doors.
--
-- NONE: Do not spawn any sign at all.
-- LEFT: Spawn a sign two tiles to the left of the door.
-- RIGHT: Spawn a sign two tiles to the right of the door.
local SIGN_TYPE = {
    NONE = 0,
    LEFT = 1,
    RIGHT = 2,
}
level_sequence.SIGN_TYPE = SIGN_TYPE

-- Spawn a door that will act as a shortcut to a specific level.
--
-- x: x position that the door will spawn at.
-- y: y position that the door will spawn at.
-- layer: Layer that the door will spawn at.
-- level: Level that the door will lead to when entered.
-- include_sign: (optional) SIGN_TYPE enum. SIGN_TYPE.NONE to not include any sign. SIGN_TYPE.LEFT
--               to include a sign to the left of the door. SIGN_TYPE.RIGHT to include a sign to the
--               right of the door. The sign will pop up a toast with either the level name or sign_text.
--               Defaults to SIGN_TYPE.NONE if not set and does not display a sign.
-- sign_text: (optional) Text displayed when the interact button is pressed. If not set, will default
--            to displaying "Shortcut to level.title".
-- Return: A shortcut object with data for the shortcut that was spawned:
--           level: The level the shorcut leads to.
--           door: The door that was spawned to start the shortcut.
--           sign: The sign that was spawned to display information about the shortcut.
--           sign_text: The text that will be displayed when interacting with the sign.
--           destroy(): Method that can be called to remove the shortcut.
level_sequence.spawn_shortcut = function(x, y, layer, level, include_sign, sign_text)
    include_sign = include_sign or SIGN_TYPE.NONE
    local background_uid = spawn_entity(ENT_TYPE.BG_DOOR, x, y+.25, layer, 0, 0)
    local door_uid = spawn_door(x, y, layer, world_for_level(level), level_for_level(level), theme_for_level(level))
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


-- Spawn a door that can be entered to continue an ongoing run.
--
-- x: x position that the door will spawn at.
-- y: y position that the door will spawn at.
-- layer: Layer that the door will spawn at.
-- level: Level that the door will lead to when entered.
-- attempts: Number of attempts in the run that will be continued.
-- time: Total amount of time spent on the continued run.
-- include_sign: (optional) SIGN_TYPE enum. SIGN_TYPE.NONE to not include any sign. SIGN_TYPE.LEFT
--               to include a sign to the left of the door. SIGN_TYPE.RIGHT to include a sign to the
--               right of the door. The sign will pop up a toast with either the level name or sign_text.
--               Defaults to SIGN_TYPE.NONE if not set and does not display a sign.
-- sign_text: (optional) Text displayed when the interact button is pressed. If not set, will default
--            to displaying "Continue run from level.title".
-- disabled_sign_text: (optional) Text displayed when the interact button is pressed if continuing runs
--                     is disbled due to keep_progress being disabled. If not set, will default to
--                     displaying "Cannot continue in hardcore mode".
-- no_run_sign_text: (optional) Text displayed when the interact button is pressed if continuing runs
--                   is enabled, but there is no saved run to load from. If not set, will default to
--                   displaying "No run to continue"
-- Return: A shortcut object with data for the shortcut that was spawned:
--           level: The level the shorcut leads to.
--           attempts: Number of attempts that the run is on if entering the door.
--           time: Total time the run will be set to when continuing through the door.
--           door: The door that was spawned to continue the run.
--           sign: The sign that was spawned to display information about the run.
--           sign_text: The text that will be displayed when interacting with the sign.
--           disabled_sign_text: The text that will be displayed if continuing is disabled.
--           no_run_sign_text: The text that will be displayed if there is no run to continue.
--           destroy(): Method that can be called to remove the door.
--           update_door(level, attempts, time, sign_text, disabled_sign_text, no_run_sign_text): Method
--               that can be called to update the state of the run that the door will continue to.
level_sequence.spawn_continue_door = function(
        x,
        y,
        layer,
        level,
        attempts,
        time,
        include_sign,
        sign_text,
        disabled_sign_text,
        no_run_sign_text)
    include_sign = include_sign or SIGN_TYPE.NONE
    local background_uid = spawn_entity(ENT_TYPE.BG_DOOR, x, y+.25, layer, 0, 0)
    local door_uid = spawn_door(x, y, layer, world_for_level(level), level_for_level(level), theme_for_level(level))
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
        door.theme = theme_for_level(level)
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
    local continue_door = {
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

        local new_doors = {}
        for _, new_door in pairs(continue_doors) do
            if new_door ~= continue_door then
                new_doors[#new_doors+1] = new_door
            end
        end
        continue_doors = new_doors
    end
    continue_doors[#continue_doors+1] = continue_door
    return continue_door
end

-- Updates the current level that will be loaded upon entering a door. Updates the level when within
-- a 1-block radius of either the door or the sign.
local function update_current_entry()
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
    for _, continue_door in pairs(continue_doors) do
        if continue_door.level ~= nil and
                sequence_state.keep_progress and
                ((continue_door.door and distance(player.uid, continue_door.door.uid) <= 1) or
                 (continue_door.sign and distance(player.uid, continue_door.sign.uid) <= 1)) then
            load_run(continue_door.level, continue_door.attempts, continue_door.time)
            if sequence_callbacks.on_prepare_initial_level then
                sequence_callbacks.on_prepare_initial_level(continue_door.level, true)
            end
            return
        end
    end
    -- If not next to any door, just set the state to the initial level. 
    load_shortcut(sequence_state.levels[1])
    if sequence_callbacks.on_prepare_initial_level then
        sequence_callbacks.on_prepare_initial_level(sequence_state.levels[1], false)
    end
end

-- Called on every GAMEFRAME, displays a toast if the player presses the door button while standing
-- next to a shortcut sign.
local function handle_sign_toasts()
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
        for _, continue_door in pairs(continue_doors) do
            if continue_door.sign and
                    player.layer == continue_door.sign.layer and
                    distance(player.uid, continue_door.sign.uid) <= 0.5 then
                if not sequence_state.keep_progress then
                    toast(continue_door.disabled_sign_text or "Cannot continue in hardcore mode")
                elseif continue_door.level then
                    toast(continue_door.sign_text or f'Continue run from {continue_door.level.title}')
                else
                    toast(continue_door.no_run_sign_text or "No run to continue")
                end
            elseif continue_door.door and
                    not continue_door.level and
                    player.layer == continue_door.door.layer and
                    distance(player.uid, continue_door.door.uid) <= 0.5 then
                toast(continue_door.no_run_sign_text or "No run to continue")
            elseif continue_door.door and
                    not sequence_state.keep_progress and
                    player.layer == continue_door.door.layer and
                    distance(player.uid, continue_door.door.uid) <= 0.5 then
                toast(continue_door.disabled_sign_text or "Cannot continue in hardcore mode")
            end
        end
    end
end

--------------------------------------
---- /CAMP
--------------------------------------

--------------------------------------
---- LEVEL STATE
--------------------------------------

-- Allow clients to interact with copies of the level list so that they cannot rearrange, add,
-- or remove levels without going through these methods.
--
-- Return: Copy of the current loaded levels.
level_sequence.levels = function()
    local levels = {}
    for index, level in pairs(sequence_state.levels) do
        levels[index] = level
    end
    return levels
end

-- Set the levels that will be loaded. If currently in a run, the actual level state will not
-- be updated until back in the camp.
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
local function convert_buffered_levels()
    if sequence_state.buffered_levels then
        sequence_state.levels = sequence_state.buffered_levels
        sequence_state.buffered_levels = nil
        update_main_exits()
    end
end

--------------------------------------
---- /LEVEL STATE
--------------------------------------

--------------------------------------
---- CUSTOM LEVEL SPAWNS
--------------------------------------

level_sequence.ALLOW_SPAWN_TYPE = custom_levels.ALLOW_SPAWN_TYPE

function level_sequence.allow_spawn_types(allowed_spawn_types)
    sequence_state.allowed_spawn_types = allowed_spawn_types
end

--------------------------------------
---- /CUSTOM LEVEL SPAWNS
--------------------------------------

--------------------------------------
---- STATE CALLBACKS
--------------------------------------

local active = false
local internal_callbacks = {}
local function add_callback(callback)
    internal_callbacks[#internal_callbacks+1] = callback
end
level_sequence.activate = function()
    if active then return end
    active = true
    button_prompts.activate()
    add_callback(set_callback(pre_load_level_files_callback, ON.PRE_LOAD_LEVEL_FILES))
    add_callback(set_callback(transition_increment_level_callback, ON.TRANSITION))
    add_callback(set_callback(save_time_on_reset_callback, ON.RESET))
    add_callback(set_callback(save_time_on_transition_callback, ON.TRANSITION))
    add_callback(set_callback(load_time_after_level_generation_callback, ON.POST_LEVEL_GENERATION))
    add_callback(set_callback(start_level_callback, ON.START))
    add_callback(set_callback(reset_on_camp_callback, ON.CAMP))
    add_callback(set_callback(reset_run_if_hardcore, ON.RESET))
    add_callback(set_callback(update_state_and_doors, ON.POST_LEVEL_GENERATION))
    add_callback(set_callback(reset_camp_doors, ON.PRE_LOAD_LEVEL_FILES))
    add_callback(set_callback(replace_main_entrance, ON.CAMP))
    add_callback(set_callback(handle_sign_toasts, ON.GAMEFRAME))
    add_callback(set_callback(update_current_entry, ON.GAMEFRAME))
    add_callback(set_callback(convert_buffered_levels, ON.CAMP))
end

level_sequence.deactivate = function()
    if not active then return end
    active = false
    for _, callback in pairs(internal_callbacks) do
        clear_callback(callback)
    end
    button_prompts.deactivate()
    load_level(nil)

    reset_camp_doors()
end

set_callback(function(ctx)
    -- Initialize in the active state.
    level_sequence.activate()
end, ON.LOAD)

--------------------------------------
---- /STATE CALLBACKS
--------------------------------------

return level_sequence
