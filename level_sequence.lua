local custom_levels = require("CustomLevels/custom_levels")
custom_levels.set_directory("LevelSequence/CustomLevels")

local level_sequence = {
}

local sequence_state = {
    levels = {},
    buffered_levels = {},
    keep_progress = true,

    level_will_unload_callback = nil,
    level_will_load_callback = nil,
    post_level_generation_callback = nil,
    reset_run_callback = nil,
    on_completed_level = nil,
    on_win = nil,
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

level_sequence.set_reset_run_callback = function(reset_run_callback)
    sequence_state.reset_run_callback = reset_run_callback
end

local function equal_levels(level_1, level_2)
    return level_1 == level_2 or (level_1.identifier ~= nil and level_1.identifier == level_2.identifier)
end

local function took_shortcut()
    return not equal_levels(run_state.initial_level, levels[1])
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

local function next_level(level)
    level = level or run_state.current_level
    local index = index_of_level(level)
    if not index then return nil end

    return sequence_state.levels[level+1]
end

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
    if state.screen == SCREEN.CAMP then
        sequence_state.levels = new_levels
        sequence_state.buffered_levels = nil
    else
        sequence_state.buffered_levels  = new_levels
    end
end

-- If the levels were updated while on a run, apply the changes when entering the camp.
set_callback(function()
    if sequence_state.buffered_levels then
        sequence_state.levels = sequence_state.buffered_levels
        sequence_state.buffered_levels = nil
    end
end, ON.CAMP)

level_sequence.index_of_level = function(level)
    return index_of_level(level)
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

-- Set the callback that will be called just before unloading a level. The callback signature
-- takes one parameter -- the level that will be unloaded.
level_sequence.set_level_will_unload_callback = function(callback)
    sequence_state.level_will_unload_callback = callback
end

-- Set the callback that will be called just before loading a level. The callback signature
-- takes one parameter -- the level that will be loaded.
level_sequence.set_level_will_load_callback = function(callback)
    sequence_state.level_will_load_callback = callback
end

local loaded_level = nil
local function load_level(level)
	if loaded_level then
        if sequence_state.level_will_unload_callback then
            sequence_state.level_will_unload_callback(loaded_level)
        end
		loaded_level.unload_level()
		custom_levels.unload_level()
	end

    loaded_level = level
	if not loaded_level then return end

    if sequence_state.level_will_load_callback then
        sequence_state.level_will_load_callback(loaded_level)
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
	load_level(level)
end, ON.PRE_LOAD_LEVEL_FILES)

---------------------------
---- /LEVEL GENERATION ----
---------------------------

----------------------
---- CONTINUE RUN ----
----------------------

level_sequence.load_run = function(level, attempts)
    run_state.current_level = level
    run_state.attempts = attempts
end

-----------------------
---- /CONTINUE RUN ----
-----------------------

---------------------------
---- LEVEL TRANSITIONS ----
---------------------------

level_sequence.set_on_completed_level = function(on_completed_level)
    sequence_state.on_completed_level = on_completed_level
end

level_sequence.set_on_win = function(on_win)
    sequence_state.on_win = on_win
end

set_callback(function()
    local previous_level = run_state.current_level
    run_state.current_level = next_level()
    if sequence_state.on_completed_level then
        sequence_state.on_completed_level(previous_level, run_state.current_level, run_state.initial_level)
    end
    if not run_state.current_level then
        if sequence_state.on_win then
            run_state.run_started = false
            sequence.state.on_win(run_state.attempts, state.time_total, run_state.initial_level)
        end
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
    if state.screen == SCREEN.CAMP or not run_state.run_started then return end
    if sequence_state.keep_progress then
        -- Save the time on reset so we can keep the timer going.
        run_state.total_time = state.time_total
    else
        -- Reset the time when keep progress is disabled; the run is going to be reset.
        run_state.total_time = 0
    end
end, ON.RESET)

set_callback(function()
    if state.screen == SCREEN.CAMP or not run_state.run_started then return end
    run_state.total_time = state.time_total
end, ON.TRANSITION)

set_callback(function()
    if state.screen == SCREEN.CAMP then return end
    state.time_total = run_state.total_time
end, ON.POST_LEVEL_GENERATION)

set_callback(function()
    if state.screen == SCREEN.CAMP then return end
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
        if sequence_state.reset_run_callback then
            sequence_state.reset_run_callback()
        end
        run_state.current_level = run_state.initial_level
        run_state.attempts = 0
    end
end, ON.RESET)

level_sequence.set_post_level_generation_callback = function(post_level_generation_callback)
    sequence_state.post_level_generation_callback = post_level_generation_callback
end

set_callback(function()
    local current_level = run_state.current_level
    local next_level_file = next_level()

    if sequence_state.post_level_generation_callback then
        sequence_state.post_level_generation_callback(current_level)
    end
    
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
	for _, exit_uid in exit_uids do
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
end, ON.POST_LEVEL_GENERATION)

return level_sequence