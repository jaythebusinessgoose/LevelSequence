# LevelSequence
Tool to help build out a sequence of custom levels in a Spelunky 2 mod.

This tool uses the CustomLevels tool to load each level in a series of levels, and includes utilities for spawning shortcut doors.

Like the CustomLevels tool, the level loading supports levels of any size up to 8x15, which is the max Spelunky 2 can support.

Each room must be created as a setroom template with the format `setroomy_x`. This is slightly different from the `setroomy-x` that the game uses for setrooms.

### Examples

For some examples of how to use the LevelSequence tool, see:
* [ExampleKaizo](https://github.com/jaythebusinessgoose/ExampleKaizo) \
A simple example of how to format the level files and how to set up the sequence.
* [JumpLunky](https://github.com/jaythebusinessgoose/JumpLunky) \
A full mod that uses more advanced features of LevelSequence.

### Configuration

Due to the way level files are loaded in, some extra configuration is required if the LevelSequence package is relocated. If it is anywhere other than the root directory of the mod, or has a name other than LevelSequence, `set_directory` must be called, passing the path to the directory within the mod folder including the directory name. Eg, for `MyCoolMod/SweetFolder/LevelSequence/level_sequence.lua` call `level_sequence.set_directory('SweetFolder/LevelSequence')`.

* `activate()` \
Call this method to activate the script.
The script is activated by default, so this only must be called if the script was deactivated.

* `deactivate()` \
Call this method to deactivate the script. The levels will not be reset when deactivated, but they will not be loaded until activated again.

## Levels

The sequence of levels that will be loaded in can be set via the `set_levels()` method and the set of levels that are already loaded can be retrieved via the `levels()` method.

```
level_sequence.set_levels(level_1, level_2, level_3)

print(inspect(level_sequence.levels()[2]))
```

Each level is an object that contains several required properties and some optional properties:

* `identifier` string \
Unique identifier to distinguish the level. Two levels should not have the same identifier.

* `title` string \
Title of the level, displayed when reading signs for shortcuts to the level when using the default sign text.

* `file_name` string \
Name of the `.lvl` file in the `Data/Levels` directory that will be loaded for this level.

* `width` int \
Width of the level in number of subrooms. The maximum allowed width is `8`. The level will not generate properly if attempting to use a width greater than 8.

* `height` int \
Height of the level in number of subrooms. The maximum allowed height is `15`. The level will not generate properly if attempting to use a height greater than 15.

* `load_level` function \
Function that will be called when the level loads to be generated. Within this function is where callbacks, custom tile codes, and other level state should be set up. Any callbacks set up here should be stored to be unloaded.

* `unload_level` function \
Called to unload the previous level when the next level is about to be loaded in. Within this function is where callbacks should be cleared. \
Note: Even when resetting the same level, this will be called before the same level is loaded in again.

* `theme` THEME (int) \
Theme that the level will load with. Also used for texturing shortcut doors.

* `co_subtheme` (optional) COSUBTHEME (int) \
Theme that Cosmic Ocean levels will load with if the THEME is THEME.COSMIC_OCEAN. If this is not set, the Cosmic Ocean will load in a random theme.

* `world` (optional) int \
The world that will be displayed in the HUD. If not set, defaults to the index of the level in the levels list.

* `level` (optional) int \
The level that will be displayed in the HUD. If not set, defaults to `1`.

Example:

```
local level_1 = {
    identifier = 'dwelling_puzzles',
    title = 'Dwelling Puzzles',
    file_name = 'dwelling_puzzle1.lvl',
    width = 5,
    height = 4,
    load_level = ...,
    unload_level = ...,
    theme = THEME.DWELLING,
}

level_sequence.set_levels({level_1})
```

Note: The levels that were set will not change while a run is in progress. Instead, they will be remembered and set when going back to the camp.

### Configuration

* `set_keep_progress(keep_progress)` \
Sets the state to either keep progress or reset on each death/restart.
\
If true, the run will reset on the current level at each reset.
If false, the run will reset on the initial level on each reset. This could be the first level, or could be another level if the initial level was changed via going through a shortcut.
    * `keep_progress` Whether progress should be kept when restarting.
Default value: true

    Example:
    ```
    level_sequence.set_keep_progress(false)
    ```

### State inspection

* `get_run_state()` \
Gets the state of the current run that is in progress.
\
Returns an object with:
    - `initial_level`: Level the run started on.
    - `current_level`: Level the player is currently on.
    - `attempts` (int): Number of attempts the player currently has in the run. A new attempt is added when starting or continuing a run from the base camp, or on a reset/instant restart.
    - `total_time` (int): The total amount of time the player has spent in the run, in number of frames.

* `run_in_progress()` \
Whether a run is currently in progress. If false, we are probably in the base camp or main menu.
    * Return: Boolean
Whether a run is in progress.

* `took_shortcut()` \
Whether a shortcut was taken to enter the current run.
    * Return: Boolean
Whether the player went through a shortcut door.
Note: This method returns false if the shortcut was to the first level.

* `index_of_level(level)` \
Attempts to get the index of a level within the current levels. Returns nil if no level is passed in or if the level cannot be found in the current levels.
    * `level`: Level to attempt to index.
    * Return: int
Index of level in the levels list.

## Shortcuts

There are convenience methods to spawn shortcut doors and also to spawn doors to continue a run in progress. The state to handle saving and loading the run is not handled by this script, but the callbacks listed later allow the state to be accessed and saved.

* `SIGN_TYPE` enum \
Enum that the shortcut methods use to decide whether to and where to spawn a sign in relation to the door.
    * `NONE`: Do not spawn any sign.
    * `LEFT`: Spawn a sign to the left of the door.
    * `RIGHT`: Spawn a sign to the right of the door.

* `spawn_shortcut(x, y, layer, level, include_sign, sign_text)` \
Spawns a shortcut door at the desired coordinates. When the player walks in front of the door it is "loaded" into the state and a callback is triggered notifying that the shortcut will be entered. When the player leaves the door, the first level is instead "loaded" into the ste and the callback is triggered again.
    * `x`: x position that the door will spawn at.
    * `y`: y position that the door will spawn at.
    * `layer`: Layer that the door will spawn at.
    * `level`: Level that the door will lead to when entered.
    * `include_sign` (optional): SIGN_TYPE enum that describes how to spawn a sign for this shortcut. The sign describes the shortcut when the interact button is pressed while standing near it. SIGN_TYPE.NONE to not include any sign. SIGN_TYPE.LEFT to include a sign to the left of the door. SIGN_TYPE.RIGHT to include a sign to the right of the door. The sign will pop up a toast with either the `level.title` or `sign_text`, if included.
    Default: SIGN_TYPE.NONE. Does not display a sign if not set.
    * `sign_text` (optional): Text displayed when the interact button is pressed when in front of the sign. If not set, will default to displaying "Shortcut to level.title".
    * Return: A shortcut object with data for the shortcut that was spawned:
        * `level`: The level the shortcut leads to.
        * `door`: The door that was spawned to start the shortcut.
        * `sign`: The sign that was spawned to display information about the shortcut.
        * `sign_text`: The text that will be displayed when interacting with the sign.
        * `destroy()`: Method that can be called to remove the shortcut.

    Example:
    ```
    level_sequence.spawn_shortcut(0, 0, LAYER.FRONT, dwelling_level_1, level_sequence.SIGN_TYPE.RIGHT)
    ```

* `spawn_continue_door(x, y, layer, level, attempts, time, include_sign, sign_text, disabled_sign_text, no_run_sign_text)` \
Spawns a door that can be entered to continue an ongoing run.
    * `x`: x position that the door will spawn at.
    * `y`: y position that the door will spawn at.
    * `layer`: Layer that the door will spawn at.
    * `level`: Level that the door will lead to when entered.
    * `include_sign` (optional): SIGN_TYPE enum that describes how to spawn a sign for this shortcut. The sign describes the shortcut when the interact button is pressed while standing near it. SIGN_TYPE.NONE to not include any sign. SIGN_TYPE.LEFT to include a sign to the left of the door. SIGN_TYPE.RIGHT to include a sign to the right of the door. The sign will pop up a toast with either the `level.title` or `sign_text`, if included.
    Default: SIGN_TYPE.NONE. Does not display a sign if not set.
    * `sign_text` (optional): Text displayed when the interact button is pressed when in front of the sign. If not set, will default to displaying "Continue run from level.title".
    * `disabled_sign_text` (optional): Text displayed when the interact button is pressed when in front of the sign if continuing runs is disabled due to keep_progress being disabled. If not set, will default to displaying "Cannot continue in hardcore mode".
    * `no_run_sign_text` (optional): Text displayed when the interact button is pressed if continuing runs is enabled, but there is no saved run to load from (ie, `level` is `nil`). If not set, will default to displaying "No run to continue".
    * Return: A continue object with the data for the door that was spawned:
        * `level`: The level the door leads to.
        * `attempts`: Number of attemptsw that the run is on if entering the door.
        * `time`: Total time the run will be set to when continuing through the door.
        * `door`: The door that was spawned to continue the run.
        * `sign`: The sign that was spawned to display information about the run.
        * `sign_text`: The text that will be displayed when interacting with the sign.
        * `disabled_sign_text`: The text that will be displayed if continuing is disabled.
        * `no_run_sign_text`: The text that will be displayed if there is no run to continue.
        * `destroy()`: Method that can be called to remove the door.
        * `update_door(level, attempts, time, sign_text, disabled_sign_text, no_run_sign_text): Method taht can be called to update the state of the run that the door will continue to.

    Example:
    ```
    level_sequence.spawn_continue_door(0, 0, LAYER.FRONT, dwelling_level_1, 20, 3600, level_sequence.SIGN_TYPE.RIGHT, nil, "Cannot continue in EXTREME mode.", "Cannot find a run to continue from")
    ```

## Callbacks

There are several callbacks that are called when certain events occur. These are useful to hook into to set local state on these events for displaying custom UI or configuring levels.

* `set_on_level_will_unload(callback)` \
Called during level gen just before unloading the previous level.
\
Callback signature: `function(level)`
    * `level`: Level that will be unloaded

* `set_on_level_will_load(callback)` \
Called during level gen just before loading the current level.
\
Callback signature: `function(level)`
    * `level`: Level that will be loaded

* `set_on_post_level_generation(callback)` \
Called during post level generation, after the level state has been configured.
\
Callback signature: `function(level)`
    * `level`: Level that is currently loaded.

* `set_on_reset_run(callback)` \
Called when the run is reset back to the first level.
This callback will never be called if keep_progress is `true`.

* `set_on_completed_level(callback)` \
Called in the transition after a level has been completed.
\
Callback signature: `function(completed_level, next_level)`
    * `completed_level`: The level that was just completed.
    * `next_level`: The level that will be loaded next.

* `set_on_win(callback)` \
Called in the transition after the final level has been completed.
\
Callback signature: `function(attempts, time)`
    * `attempts`: Number of attempts it took to complete all levels. Each reset/game exit counts towards the number of attempts.
    * `time`: Total amount of time it took to complete all levels.

* `set_on_prepare_initial_level(callback)` \
Called in the base camp when the initial level is updated, ie via walking by a shortcut door.
\
Callback signature: `function(level, continuing_run)`
    * `level`: Initial level that will be loaded when going through an entrance door.
    * `continuing_run`: True if going through a continue door. Otherwise, false.

* `set_on_level_start(callback)` \
Called each time a level starts. This includes both the first time the level is encountered and on every reset that resets to the level.
\
Callback signature: `function(level)`
    * `level`: The level that is being started.

## Known Issues

The game crashes upon entering a Cosmic Ocean level from a non-CO level. Loading Cosmic Ocean levels from the base camp does work, and so does going to non-CO levels from a CO level.


## Procedural Spawns

Random spawns such as crates, rocks, webs, gold, and embedded items, are removed by default so that only
manually spawned items exist. For some of these items, this may mean that tile codes that add the item will not spawn the item.

It should work to create a custom tile code to spawn in the entity and manually spawn it in the script.

To allow these spawns to spawn procedurally anyway, set the allowed spawn bitmask via `allow_spawn_types(allowed_spawn_types)`.

`allowed_spawn_types` parameter is a bitmask  of the `ALLOW_SPAWN_TYPE` enum.
`ALLOW_SPAWN_TYPE`:
- `PROCEDURAL` (Items in the level, such as gold, pots, crates, ghost pot, etc)
- `EMBEDDED_CURRENCY` (Gold and gems embedded in the wall)
- `EMBEDDED_ITEMS` (Items such as backpacks, weapons, and powerups embedded in the wall)

This will allow all spawns except for gold and gems embedded in the wall:
```
    local allowed_spawns = set_flag(0, level_sequence.ALLOW_SPAWN_TYPE.PROCEDURAL)
    allowed_spawns = set_flag(allowed_spawns, level_sequence.ALLOW_SPAWN_TYPE.EMBEDDED_ITEMS)
    level_sequence.allow_spawn_types(allowed_spawns)
```

## Back layers

To set the back layer of a level, mark the template as `\!dual` and include the back layer tiles in line after the front layer tiles.

## Ice Caves

Levels in the Ice Caves themes have some additional restrictions.

The bottom level of rooms will be off-screen, so the level should be one taller than what is expected to be visible to the user.

They must include a `setroomy-x` for some templates. The `setroomy-x` template must have the same content as the `setroomy_x` template for the same room. Otherwise, some rooms will randomly pick one or the other. Following are the rooms that require a `setroomy-x`:
- 4-0, 4-1, and 4-2
- 5-0, 5-1, and 5-2
- 6-0, 6-1, and 6-2
- 7-0, 7-1, and 7-2

They also must include a `setroomy-x` for the _back layer_ of some addional templates. These `setroomy-x` templates must have the same content as the _back layer_ of the `setroomy_x` template for the same room. Following are the rooms that require a back layer `setroomy-x`:
- 10-0, 10-1, and 10-2
- 11-0, 11-1, and 11-2
- 12-0, 12-1, and 12-2
- 13-0, 13-1, and 13-2

Even if the level is smaller than the setroomy-x template, the template must be included or the game will crash. The template can be all 0s if the room isn't actually being used.

## Duat

Not much testing has been done in Duat, but it has similar restrictions to Ice Caves, or it will crash:

Duat must include a `setroomy-x` for some templates. The `setroomy-x` template must have the same content as the `setroomy_x` template for the same room. Otherwise, some rooms will randomly pick one or the other. Following are the rooms that require a `setroomy-x`:
- 0-0, 0-1, and 0-2
- 1-0, 1-1, and 1-2
- 2-0, 2-1, and 2-2
- 3-0, 3-1, and 3-2

In addition, the bosses will spawn at the top of the level.

## Abzu

Not much testing has been done in Abzu, but it has similar restrictions to Ice Caves, or it will crash:

Abzu must include a `setroomy-x` for some templates. The `setroomy-x` template must have the same content as the `setroomy_x` template for the same room. Otherwise, some rooms will randomly pick one or the other. Following are the rooms that require a `setroomy-x`:
- 0-0, 0-1, 0-2, and 0-3
- 1-0, 1-1, 1-2, and 1-3
- 2-0, 2-1, 2-2, and 2-3
- 3-0, 3-1, 3-2, and 3-3
- 4-0, 4-1, 4-2, and 4-3
- 5-0, 5-1, 5-2, and 5-3
- 6-0, 6-1, 6-2, and 6-3
- 7-0, 7-1, 7-2, and 7-3
- 8-0, 8-1, 8-2, and 8-3

In addition, rooms 7 and below will have water physics with fake water, with tentacles at the bottom.

Prefer to use TIDE_POOL theme instead of Abzu unless the water physics are desired.

## Tiamat

Not much testing has been done in Tiamat. It also requires several setrooms:
- 0-0, 0-1, and 0-2
- 1-0, 1-1, and 1-2
- 2-0, 2-1, and 2-2
- 3-0, 3-1, and 3-2
- 4-0, 4-1, and 4-2
- 5-0, 5-1, and 5-2
- 6-0, 6-1, and 6-2
- 7-0, 7-1, and 7-2
- 8-0, 8-1, and 8-2
- 9-0, 9-1, and 9-2
- 10-0, 10-1, and 10-2

Tiamat also spawns water at the bottom with tentacles.

The Tiamat level has a cutscene at the beginning, and will crash during the cutscene if there is no Tiamat spawned (has not been tested with a Tiamat spawn).

## Eggplant World

Eggplant world is crashing, and I haven't done any testing to figure out why.

It does have the following setrooms:
- 0-0, 0-1, 0-2, and 0-3
- 1-0, 1-1, 1-2, and 1-3

## Hundun

Hundun requires the following setrooms:
- 0-0, 0-1, and 0-2
- 1-0, 1-1, and 1-2
- 2-0, 2-1, and 2-2
- 10-0, 10-1, and 10-2
- 11-0, 11-1, and 11-2

## Olmec

Olmec requires the following setrooms:
- 0-0, 0-1, 0-2, and 0-3
- 1-0, 1-1, 1-2, and 1-3
- 2-0, 2-1, 2-2, and 2-3
- 3-0, 3-1, 3-2, and 3-3
- 4-0, 4-1, 4-2, and 4-3
- 5-0, 5-1, 5-2, and 5-3
- 6-0, 6-1, 6-2, and 6-3
- 7-0, 7-1, 7-2, and 7-3
- 8-0, 8-1, 8-2, and 8-3

Olmec is also crashing during the cutscene, you may need to spawn Olmec or disable the cutscene to address the crash.

## Cosmic Ocean

Haven't tested much. Loaded a level in and it seems to load fine in any subtheme. There are some weird things that go on if there isn't empty space along the looping edges.