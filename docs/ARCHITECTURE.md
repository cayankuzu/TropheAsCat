# Trophe As Cat — architecture and shared contracts

Read this before writing any code. It is the contract every module follows.

## 1. The game in five lines

- Third-person open-world destruction sandbox. You are **Trophe, a hairless Sphynx cat** with impossible powers.
- **Everything man-made can be destroyed**: buildings, floors, roads, props, vehicles, the ground itself
  (diggable strata down to magma). Total destruction of the world is the goal.
- **Nature and animals are invulnerable** (trees, bushes, grass, animals, and the cat). They are solid,
  they block, they are never damaged, moved by force, burned or deleted.
- **Humans** are harmable but never gory: they are simulation "mannequins" that ragdoll and glitch/shatter.
- **Nothing vanishes.** Debris settles and stays as rubble you can grab, throw, climb and dig. The old
  prototype deleted debris after 3 s; that is explicitly rejected.
- **No death**, no health bar. Falling off the world drops you back from the sky at a random spot.

Quality bar: it must feel AAA in the moment-to-moment loop: weighty destruction, dust, sound, camera.

## 2. Engine and tooling facts

- Godot **4.7.2 stable**, standard (GDScript) build. Editor GUI: `C:\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe`.
  CLI (prints to the console): `C:\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe`.
- Renderer **Forward+**, physics **Jolt** (limits raised in project.godot), physics 60 Hz with interpolation.
- Machine: i7-13650HX (14 cores), 24 GB RAM, RTX 5070 Laptop 8 GB, 1080p.
- **No internet.** Do not use WebFetch, WebSearch, curl, pip, browsers or any network access.
  Offline API reference: `C:\Users\Cayan\Desktop\CatAsRophe\docs\godot_api\engine\` (engine class XML)
  and `...\docs\godot_api\voxel\` (Voxel Tools classes). Grep them. You can also introspect at runtime
  with `ClassDB.class_get_method_list("ClassName")`.
- Useful commands (run from any folder; `<P>` is your project folder):
  - Import assets and build the class cache (run once after adding files with `class_name`):
    `Godot_v4.7.2-stable_win64_console.exe --headless --path <P> --import`
  - Run a test script headless: `... --headless --path <P> --script res://tests/your_test.gd`
    (the script `extends SceneTree`, does its work in `_initialize()`/`_process()`, prints results and calls `quit(code)`).
  - Run a scene headless for N frames: `... --headless --path <P> res://path/scene.tscn --quit-after 600`
  - **Screenshots** need a real window: run without `--headless`, e.g.
    `... --path <P> res://tests/shot_scene.tscn --resolution 1280x720` and inside the scene wait some frames,
    then `get_viewport().get_texture().get_image().save_png("res://tests/out/name.png")` and `get_tree().quit()`.
    Look at your PNGs with the Read tool. Keep windowed runs short (they appear on the user's screen).
  - Always add `--log-file <path>` or capture stdout; grep for `ERROR` and `SCRIPT ERROR`.
- Typed GDScript everywhere (`var x: float`, typed arrays, `-> void`). No `@tool` scripts unless needed.
  Prefer PackedArrays and server APIs (PhysicsServer3D, RenderingServer) for anything counted in thousands.
- Benchmark only with the windowed or headless *release-like* run, never in the editor.

## 3. Project layout

```
res://game/core/          shared contracts (owned by the lead; do not change, see section 5)
res://game/destruction/   buildings, fracture, support graph, debris, rubble
res://game/terrain/       voxel ground, strata, digging, magma, world bottom
res://game/player/        the cat: controller, camera, animation, grab/throw, tools
res://game/world/         city layout, nature placement, edge of the world (later)
res://game/npc/           humans and animals (later)
res://game/fx/            shared VFX and audio helpers (later)
res://tests/              headless tests and screenshot scenes; outputs in res://tests/out/
res://assets/textures/<ambientCG id>/   2K PBR maps: <id>_2K-JPG_{Color,NormalGL,Roughness,AmbientOcclusion,...}.jpg
res://assets/models/cat/sphynx_cat.glb  hero cat (CC BY, 12 animations incl. climb, leap, stalk, pounce)
res://assets/models/props/<name>/       Poly Haven glTF props (CC0)
res://assets/models/nature/<tree>/tree_LOD{0,1,2}.glb   EZ-Tree trees and bushes
res://assets/models/humans/             Quaternius UAL animation GLBs + base characters (CC0)
res://assets/sky/*.hdr                  Poly Haven skies (CC0)
res://addons/zylann.voxel/              Voxel Tools GDExtension 1.7 (VoxelLodTerrain, VoxelTool, ...)
```

## 4. Units, scale, coordinates

- 1 unit = 1 m, Y up. The city ground is flat at **y = 0**. Storey height 3.2 m.
- The playable slab is **1024 x 1024 m**, centred on the origin (x, z in [-512, 512]). Its bottom is at
  **y = -48**. Below and beyond it is the void.
- The cat is about 1.3x a real cat (shoulder height ~0.33 m, body ~0.6 m long) but has super powers.

## 5. Shared contracts (game/core)

- `Layers` (class): collision layer bit masks. Use them, never raw numbers.
  TERRAIN, STRUCTURE, DEBRIS, DEBRIS_SMALL, PLAYER, NPC, PROTECTED, PROPS, PROJECTILE, TRIGGER, RUBBLE,
  plus WALKABLE / SOLID / DAMAGEABLE combinations.
- `DamageHit` (class): position, normal, direction, energy (J), impulse (N·s), radius (m), kind
  (BLUNT, EXPLOSION, HEAT, ACID, CUT, SONIC, CRUSH), source, cause_id. Factories `point()` and `blast()`.
- `DamageRouter` (autoload): the only way to deal damage.
  - `apply_hit(hit, collider, rid)` for a ray/contact result; `apply_blast(hit)` for radial damage.
  - Bodies created on PhysicsServer3D (no Node) register with `register_rid(rid, handler, user_id)`;
    the router calls `handler.receive_damage(hit, user_id)`.
  - Node receivers implement `receive_damage(hit: DamageHit, user_id: int) -> void` (on the collider or an ancestor).
  - Nodes in group `"protected"` are never damaged; the router emits `protected_hit` instead.
  - Signals: `damage_applied`, `protected_hit`, `blast`.
- `MaterialDB` (class): density, toughness, brittleness, sound kind per material; cached render materials
  `surface(mat)` and `interior(mat)` (object-space triplanar PBR from ambientCG), and `strata_maps(layer)`.
  Element HP = `MaterialDB.element_hp(mat, volume_m3)`.
- `Game` (autoload): `player`, `terrain`, `structures`, `debris` references; `register_player()`;
  `request_time_scale(key, scale)` / `clear_time_scale(key)` (lowest wins); input actions:
  move_forward/back/left/right, jump, sprint, crouch, interact, grab, rewind, slow_motion, stand_up,
  pause, tool_next, tool_1..tool_9, attack (LMB), aim (RMB), tool_wheel_up/down.

If a module truly needs a core change, keep it minimal, keep backward compatibility, and list it in your
report so the lead can merge it. Never rename or remove anything in core.

## 6. Cross-module rules

- **Object-space triplanar** is the texture rule for man-made geometry. Fracture pieces keep their vertices
  in the *parent element's local frame* and spawn with the element's transform, so their texture matches
  the intact element exactly. Element meshes use real sizes (never scale a unit cube), so a small set of
  quantised element sizes per building style is required.
- **Nothing visible is deleted.** Over-budget debris is frozen into static rubble, never freed.
- Everything that lands, breaks or explodes calls into `DamageRouter`; chain reactions share `cause_id`.
- Performance budget at 60 fps: physics ≤ 6 ms, destruction logic ≤ 2 ms, other scripts ≤ 2 ms.
  Heavy work is time-sliced through a per-frame ms budget queue; never stall a frame.
- Rewind will record transforms of awake bodies and an invertible event log later. Keep state changes
  going through a few central functions and emit signals for them so a recorder can hook in.
- Each module registers itself in `Game` (`Game.structures`, `Game.debris`, `Game.terrain`, `Game.register_player`).

## 7. Current state of the main project (2026-11-17)

Merged and tested: `game/core`, `game/destruction`, `game/terrain`, `game/player` (with the five tools),
`game/fx`, `game/audio`, `game/world/environment`, `game/world/nature`, `game/world/props`, `game/world/city`,
`game/npc`, `game/flow/progress.gd`, `game/ui/mini_hud.gd`, `game/time` (Timeline, the world rewind).
Public names of the autoloads are contracts; only the owning module changes their bodies.
- **Set pieces (2026-11-17):** `Giant` (`game/world/setpieces/giant.gd`, RigidBody3D on Layers.STRUCTURE):
  `build(sections, extra_shapes)` (sections {mesh, shape, xf, mass, material, no_collide, no_piece}),
  `hold_j`, `taken`, `fall` (TIP / ROLL), `base_half`, `roll_hint`, `release()`, `break_up()` (each section a
  DebrisManager piece), signals `let_go`, `broke`; a DamageRouter RID handler; contacts gathered in
  `_integrate_forces` and turned into CRUSH hits in `_physics_process`; a tipping giant turns round the edge
  of its base (velocities set in `_integrate_forces`, gravity x1.4) and falls freely from 60 degrees; out of
  Trophe's reach it waits frozen; `Timeline.rewind_stopped` puts it back. `SetPieces`
  (`game/world/setpieces/set_pieces.gd`, node `SetPieces`, built in `main._build()`): `wheel`, `crane`,
  `tower`, `giants`, `released_count()`; stands are static bodies registered to their giant. Materials
  `lattice_yellow` (railing look) and `clock_face` (FacadeTextures `_clock`). `PropSets.green(..., statue)`.
  Test: `shot_giants.tscn` (GIANTS_*).
- **Interiors (2026-11-17):** `PropSets.interior_house`, `interior_shop`, `interior_mall` (the room is the box
  of the ground-floor verticals of the design, `_room`), called for every lot of style HOUSE, SHOP and MALL
  in `main._build()`; `StreetDressing.add_prop(..., inside)` and `add_on_top(..., inside)` draw a prop only
  within 45 m and without a shadow. Test: `shot_inside.tscn` (INSIDE_*).
- **Cleanup robots (2026-11-17):** `CleanupRobots` (`game/world/cleanup/cleanup_robots.gd`, node
  `CleanupRobots`, made in `main.begin()` after the Police): `robots` (`Robot`: prop, home, mess, job
  OUT/SEEK/GO/SUCK/HOME, target rubble index, carried, skip with expiry, led), `call_out(at, force)`,
  `tape_worst_ruin()`, `send_home()` (on `Timeline.rewind_started`), counters `called`, `vacuumed`, `wrecked`,
  `taped`, `tape_props`. Triggers: `StructureManager.building_toppled` (after `TOPPLE_DELAY`),
  `Progress.chain_ended` (>= `CALL_CHAIN`), `Chaos.stars_changed` (tape at 3). A robot is a BreakableProp made
  with `StreetDressing.add_node_prop(id, model, def, at, yaw, lift)` (cylinder shape, 9 kg, `can_sleep` off),
  steered by setting its velocities; wrecking one calls `Chaos.add(WRECK_HEAT)`. Rubble access:
  `DebrisManager.rubble_near(at, radius, max_up, max_n)`, `rubble_alive`, `rubble_position`, `take_rubble`.
  The tape look is the procedural `tape` (FacadeTextures `_tape`, a 5 x 7 pixel font) as MaterialDB variant
  `tape`. `WorldTerrain.explode` lays the crater lobes and lip only when the surface faces up (`up.y > 0.7`),
  always level. Test: `shot_robots.tscn` (ROBOTS_*). Props made after the world is built (robots, tape,
  road blocks, crashed cars of the traffic) are left out of saved games: `StreetDressing.sealed` is set at
  the end of `main._build()` and `all_names` only grows before that.
- **Chaos stars and the Police (2026-11-17):** `Chaos` (`game/flow/chaos.gd`, node `Chaos`, made in
  `main.begin()`): `heat`, `stars`, `best_stars`, `quiet`, `watched`, `add(amount)`, `reset()`, `cooling()`,
  signal `stars_changed(stars)`; `THRESHOLDS` [10, 35, 80, 150, 250], `CALM_AFTER` 10 s, `COOL_RATE`; heat from
  `Progress.chain_changed`, `DamageRouter.blast`, `People.person_shattered`, `StructureManager.building_toppled`;
  the stars are drawn by its own CanvasLayer (`StarsWidget`); lines through `OwnerVoice.speak(line, force)`.
  `Police` (`game/world/traffic/police.gd`, node `Police`): `Kind` POLICE / FIRE / SWAT, `CARS_PER_STAR`,
  `units` (`Unit`: car, kind, deployed, leaving, lights, siren), `officers` (people ids), `dispatched`,
  `arrived`, `blocks`, `active_units()`, `dismiss_all()` (on `Timeline.rewind_started`); it sets
  `Chaos.watched`. Traffic units: `Traffic.dispatch(vname, paint) -> Car` (unit, pursuit, parked, paint),
  `retire_unit(car)`, signals `unit_arrived`, `unit_crashed`, `PURSUIT` 19 m/s, `_arrive_distance`, the pull-over
  (`Car.pull`, `yield_t`). `People.add_officer(at, yaw, figure, kind)`, `retire(id)`, `Person.officer`,
  `_tick_officer`, `OFFICER_LINES`, `FIRE_LINES`. Test: `shot_police.tscn` (POLICE_*).
- **Far LOD (2026-11-17):** `StructureManager.far_lod_distance` (240 m): every design is merged once
  (`_merge_design`, one surface per material, `FAR_HIDDEN_KINDS` left out; at most one design a frame from
  `_far_queue`) into an ArrayMesh shown as the building's "FarLOD" MeshInstance3D (no shadows,
  `visibility_range_begin` = the distance) while its instance groups end there. The first element a building
  loses (`_lose`, `gone_count`) switches it back to the groups for good; a rewind that makes it whole again
  restores the far mesh (`_far_show`).
- **The outer ring (2026-11-17):** `CityLayout` (`BLOCKS_OUT` 3, `INNER_OUT` 2) lays out `block_order()`: the
  old 4 x 4 blocks first (their seeds unchanged), then the ring. `District` gains STRIP, YARDS, SUBURBS
  (`district_at`: the outer ring is past 256 m); `block_centre(b)`. Open places for the prop sets:
  `car_parks` (Rect2 on the bay grid: `BAY_W` 2.5, `BAY_PERIOD` 16, `BAY_ROWS`), `asphalt`, `paved`,
  `mall_fronts`, `forecourts` ({pos, seed}), `loading_yards`, `container_yards`, `driveways`, `fences`,
  `backyards`, `lawns`. `surface_mask()` writes alpha 0 where bays are painted; `strata.gdshader` draws them
  (`bay_paint`). New generator styles (`D.Style` WAREHOUSE, MALL, CANOPY, SHOP): `_warehouse` (steel frame, one
  hall, corrugated cladding `clad_*`, roller doors, `roof_sheet`), `_mall` (frame + tower look + sign band
  `mallsign_*`), `_canopy` (steel columns, `canopy_white` roof, `fascia_*` all round;
  `BuildingGenerator.canopy_brand(seed)`), `_shop` (one-storey masonry with shop fronts); shared helpers
  `_frame_parapet`, `_parapet`. Procedural looks `corrugated`, `roller`, `fascia` in `FacadeTextures`; variants
  `pump_*`, `pylon_*`. `StreetDressing.add_box(id, size, look, def, at, yaw, lift, parts)` (box props: shipping
  containers, pumps, pump islands, fences, pylons) and `park_in_bay(at, yaw, rng)`; `PropSets.car_park`,
  `forecourt`, `mall_front`, `loading_yard`, `container_yard`, `driveway`, `fence`, `backyard`, `paddock`.
  District tables (street clusters, car fill, walkers) have entries 5..7. Tests: `test_ring.tscn` (designs stand
  on their own, footprints, no overlaps, the old city first; RING_*), `shot_ring.tscn` (views, the pump chain).
- **The living city (2026-11-17):** `People` uses `CAST` (Quaternius modular figures in
  `assets/models/humans/city/`, districts, weights, rude) with `LOOPS`, `SKINS`, `HAIRS`, `HUE_TURNS`
  (glaze variants), `_add_figure` (loop flags, a `Sit` clip from `Idle` via `_make_sit`, glazed material
  overrides), `Person.look/tint/after`, `_play_once`. `Wildlife` (`game/npc/wildlife.gd`, node `Wildlife`
  under main): `SPECIES` (Quaternius animals in `assets/models/animals/wild/`), `populate(city)`,
  `add_animal(kind, at, area)`, `paddock_rect()`, acts IDLE/GRAZE/WALK/RUN/REACT, natures flee/shy/chase,
  bodies on Layers.PROTECTED (meta "beast"), `flights`, `chases`. `Traffic` (`game/world/traffic/traffic.gd`,
  node `Traffic`): `setup(dressing, lines, count, closed)`, `Car` (axis, line, dir, s, turning on a quadratic
  curve through a crossing, `_owner` per crossing), `_follow_distances`, `_look_ahead` (rays for near cars,
  the cat, run-over hits), `receive_damage` (DamageRouter RID handler) -> `_crash` (a car prop via
  `StreetDressing.add_vehicle`, respawn out of sight), `_honk` (a synthesized horn), `driving()`, `crashed`,
  `honks`, `run_over`. Tests: `shot_npc.tscn` (NPC_*), `shot_traffic.tscn` (TRAFFIC_*).
- **The edge of the Table (2026-11-17):** `TableEdge` (`game/world/edge/table_edge.gd`, node `TableEdge`
  under main, made with the terrain): four unshaded additive curtains 1.5 m outside the slab's sides
  (`HALF` 512, from `WALL_BOTTOM` -1400 to `WALL_TOP` 260, brightest at `RIM_Y` 30, faded near the camera)
  with the Owner's code (`CODE`, set once in a SubViewport and kept as a mipmapped texture) and a grid,
  and a grid floor at y = -1500. The terrain shader (`strata.gdshader`) draws the rim: `u_world_half`,
  `u_rim_width` (28 m), `u_rim_grid`, `u_rim_color`, on top-facing ground only (the cut side keeps its
  strata under a faint grid). `Underneath` (`game/world/edge/underneath.gd`, node `Underneath`, made in
  `main.begin()`): starts when the cat is past the slab edge and below the rim, or when the cat's own void
  rule fires (`CatPlayer.void_handler`, a Callable called instead of the plain re-drop when set);
  `FALL_SECONDS` 5, `TERMINAL` 22 m/s, drifts her out by position, turns the camera to the slab, streaks
  through `WorldFX.sparks`, the Owner's lines through `MiniHud.say`, skippable after `SKIP_AFTER` 0.8 s by
  any key or click, then `drop_from_sky()`; `falling`, `falls`, `t`. `SaveGame.write` keeps the cat at
  the crossing when she is outside the Table.
- **World rewind (2026-11-17):** autoload `Timeline` (`game/time/timeline.gd`): `begin_rewind()` /
  `end_rewind()` (bound to the `rewind` action, R, held), `is_rewinding()`, `available()` (the `rewind` tool
  is unlocked and a world with a cat exists), `max_depth()`, `depth`, `now` (game seconds since the world
  was made; `reset()` at every new world), signals `rewind_started`, `rewind_stopped`,
  `time_mode_changed(mode)`. `WINDOW_SECONDS` 15, `SPEED` 1.6, `TIME_SCALE` 0.05 (requested from `Game`
  while rewinding). Everything is driven by one number, the depth: seconds of game time back from the
  start of the rewind; each part converts it to its own clock. `StructureManager`: `_log_gone` at the
  three places an element leaves INTACT, `rewind_begin()` (drops fracture jobs, cluster builds, sags,
  topples, crushes), `rewind_to(depth)` (brings elements back newest first: `_revive` puts the instance,
  the body and `SupportSolver.revive(e)` back), `rewind_end(depth)` (the clock goes back with it),
  `rewinding` (the frame logic stands still), `revived`. `DebrisManager`: `_spawn_xf` (where each record was
  born), `_rb_born` / `_rb_born_xf` for rubble (a frozen piece keeps the birth it had as debris, a woken
  rubble piece too), `rewind_begin()`, `rewind_to(depth)` (flies pieces born after the cursor back over
  `REWIND_FLY` 1.1 s and removes them `REWIND_LAG` 0.12 s past their birth), `rewind_end(depth)`,
  `_remove_rubble(idx)`. Props: `Timeline.record_prop(prop, &"break" | &"wreck", xf)`,
  `Timeline.retire_prop(prop)` (a broken prop is hidden and kept until it leaves the window, then freed),
  `Timeline.prop_awake(prop)` (moving props leave a trail sampled every 0.1 s, played back while
  rewinding), `BreakableProp.unbreak(xf)`, `unwreck()`. People: `Timeline.record_person(people, id,
  before)`, `People.unshatter(id, before)`, `rewind_heads(t)`; `Timeline.people` is set by People.
  `Progress.remove_destroyed_mass(kg)`. `RewindFX` (`game/time/rewind_fx.gd`, a CanvasLayer under the
  HUD): the screen shader, the label and bar, the procedural tape warble; drawn for three frames at start
  so its shader is compiled before the first rewind. `DominoRun` recounts fallen tiles after a rewind.

- **Composition root:** `res://game/main.tscn` + `game/main.gd`. It first asks worker threads for the big
  models (`VehicleLibrary.model_paths()`, `WorldNature.model_paths()`, `StreetDressing.model_paths()` through
  `ResourceLoader.load_threaded_request`), then adds `WorldLook`
  (`game/world/environment/world_look.tscn`), `WorldFX`, `WorldTerrain`, `StructureManager.create_world(self)`,
  the city (`CityLayout.build`, every building dormant), `WorldNature` (an avenue on every street, the Park),
  `StreetDressing` (props between the street trees and parked cars on every street), the composed places
  (`PropSets`), the opening domino run (`DominoRun`), `People`, `Animals`, the cat, which enters with
  `cat.drop_from_sky(SPAWN)` (the fall gives the terrain time to stream collision in) and `cat.face(...)`
  down the domino run, and `MiniHud`. It calls `Progress.reset()` first; the game starts with the paw and
  the pee (F1 or `-- --sandbox` unlocks everything). It also owns slow motion: the `slow_motion` action (Q)
  held requests time scale 0.25 from `Game` and sets `AudioServer.playback_speed_scale` to 0.6.
  The world is built over many frames (every stage yields a frame, the buildings every 90 ms through
  `CityLayout.build_async`): signals `stage_done(what, fraction)` and `world_ready`, `built`, `build_ms()`.
  `begin(at)` starts play (the cat, the HUD, the Owner, the pause menu); with `auto_start` (the default)
  that happens as soon as the world stands, so tests and the editor run main.tscn as before. `playing`,
  `save_game(slot)`, `spawn_point()`; the build parts are fields (`look`, `terrain`, `city`, `dressing`,
  `dominoes`, `people`, `animals`, `cat`, `hud`, `owner_voice`, `pause_menu`). An autosave runs every two
  minutes of play and when the window is closed. On leaving the tree it clears `Game.structures`,
  `Game.debris` and `Game.terrain`; `Game.player` clears itself when the cat leaves.
- **Boot and the frame around play (2026-11-17):** the project's main scene is `res://game/boot.tscn`
  (`Boot`, `game/flow/boot.gd`): `LoadingScreen` at once, main.tscn read on a worker thread and built with
  `auto_start` off, a title camera orbiting the crossing (the terrain streams around the camera while
  there is no cat), `TitleScreen` (glitch title and menu), then `start(slot)`: `SaveGame.apply` for a
  slot, `main.begin(at)`, `OwnerVoice.intro(continued)`. `Boot.pending_slot` (static) makes the next boot
  load a slot straight away; the pause menu sets it and changes scene to load or to quit to the title.
  `SaveGame` (`game/flow/save_game.gd`, static): slots 0 (autosave) to 3 under `user://saves/slot_<n>/`
  (`save.json` and the terrain's `terrain.sqlite`), `write(main, slot)`, `apply(main, slot)`, `exists`,
  `info`, `latest`, `describe`. The parts it uses: `StructureManager.removed_elements(bid)` and
  `restore_removed(bid, elems)` (silent: no fracture, debris or effects; unsupported leftovers fall as
  usual), `StreetDressing.save_state() / restore_state()` (by prop name; `all_names`),
  `BreakableProp.restore_broken() / restore_wreck()`, `DominoRun.save_state() / restore_state()`,
  `People.save_state() / restore_state()`, `WorldTerrain.save_edits / load_edits`,
  `Progress.save_state()`, `begin_restore()`, `end_restore(state)` (`restoring` unlocks milestones
  without their toast). `Settings` (`game/flow/settings.gd`, static, `user://settings.cfg`):
  `load_and_apply()`, `apply_audio()`, `apply_window()`, `apply_world(look)`, `apply_cat(cat)`.
  `SettingsPanel`, `PauseMenu` (Esc, `PROCESS_MODE_ALWAYS`, pauses the tree; `save_to(slot)`,
  `load_from(slot)`), `OwnerVoice` (`intro(continued)`, `moment(key)`, `lines_said`),
  `MiniHud.say(line, seconds, interrupt)`, `is_speaking()`, `flash(text)`. `UiKit` holds the fonts,
  colours and the button style of every menu. Lambdas must not be connected to autoload signals from
  objects that can be freed (they outlive them and fail when the next world starts); use bound methods
  or disconnect in `tree_exiting`.
- **Progress** (autoload, `game/flow/progress.gd`): TABLE CLEARED % = destroyed / total man-made mass.
  Buildings are read from `StructureManager.built_mass` / `gone_mass` every frame; props, vehicles and
  people call `add_total_mass(kg)` when they appear and `add_destroyed_mass(kg)` when they break.
  `cleared_percent()`, `MILESTONES` (0.2 / 1 / 3 / 8 / 15 %, each with the tool id, its name and the Owner's
  line), `is_tool_unlocked(id)` (paw and pee always), `next_milestone()`, `reset()`, `sandbox_all_tools`;
  signals `cleared_changed(percent)`, `milestone_reached(index, tool_id)`, `tool_unlocked(tool_id)`,
  `sandbox_changed(on)`. The chain: `report_break(count := 1)` from whatever breaks (props, wrecks, people
  and falling dominoes call it; building elements and toppled buildings are counted from the structure
  signals), `chain`, `best_chain`, `breaks_total`, `CHAIN_WINDOW` (2.4 s), `CHAIN_RANKS`,
  `chain_title(count)`, signals `chain_changed(count, title)`, `chain_ended(count)`.
- **HUD** (`game/ui/mini_hud.gd`, stand-in until the flow module): crosshair, TABLE CLEARED % with a bar,
  the Owner's line and the new tool for 7 s on a milestone, the chain count and rank beside the crosshair,
  the tool strip, a controls hint that fades.
- **People** (`game/npc/people.gd`, node `People` under main): `populate(dressing)`, `add_walkers(block, n)`,
  `add_sitter(bench)`, `add_stander(at, yaw)`, `scare(at, radius)`, `receive_damage(hit, user_id)` (600 J
  or more shatters; at most `WET_J` = 60 J is pee: one line, then they run), `count()`, `alive_count()`,
  `active_count()`, counters `shattered`, `panics`, `soaked`, signal `person_shattered(at)`. A person near
  the player has a kinematic capsule on `Layers.NPC` registered with `DamageRouter`; the others only keep
  their place in time (`ACTIVE_RADIUS` 95 m, `MAX_ACTIVE` 44).
- **Ground by district:** `CityLayout.surface_mask()` (call after `build`) returns the image for
  `WorldTerrain.set_surface_mask(image, true)`: the default road grid plus paving (G) under Downtown and in
  the courts, asphalt (R) in the blocks of the Works and the park paths (`CityLayout.PARK_PATHS`, block
  coordinates). The mask changes the surface material and the top stratum only, never the height.
- **Composed places** (`game/world/props/prop_sets.gd`, static): `market`, `cafe`, `green`, `yard`,
  `fuel_depot`, `picnic` (each returns where its people stand, `{pos, yaw}`), `garden` and `park_path`. They are placed
  at `CityLayout.courts`, `plazas`, `greens`, `yards`, `gardens` and in the park blocks.
  `StreetDressing.add_on_top(id, under, offset, yaw)` stands a prop on another one; a def with
  `fragile: true` breaks when it falls, and a BLUNT hit only knocks props lighter than
  `BreakableProp.KNOCK_MASS` (6 kg) away instead of hurting them.
- **Domino run** (`game/world/props/domino_run.gd`, node `Dominoes`): `lay(from, heading, count, sway)`
  returns where the last tile stands, `add_finale(dressing, last_tile, heading)`, `tiles`, `fallen`. Tiles
  are ordinary `BreakableProp`s with `prop_id` `domino` and a slick physics material (friction 0.25; with
  ordinary friction the run crawls at a third of the speed). The node keeps all tiles unparked together
  while the player is within 80 m of the run, and a tile that goes over reports a chain step and delivers
  5 kJ to whatever stands where its top lands.
- **Animals** (`game/npc/animals.gd`, node `Animals`): `populate(city, landing)`, `add_flock(home, count)`,
  `add_dog(at, yaw)`, `scare(at, radius)`, `flocks`, `dogs`, `pigeon_count()`, `dog_count()`, counters
  `takeoffs`, `landings`, `tricks`. Birds and dogs have a `StaticBody3D` on `Layers.PROTECTED` in group
  `protected` (meta `flock` or `dog`), so `DamageRouter.protected_hit` answers for them; a bird in the air
  has no collider. Flight is drawn in `_process` (rings around the home of the flock), nothing is simulated.
  Flocks and dogs farther than 75 m from the player are hidden and still.
- **Look:** `WorldLook` (Node3D): `set_quality(WorldLook.Quality.LOW|MEDIUM|HIGH)`, `detail_scale()`,
  `set_time_of_day(&"golden_hour" | &"dusk")`, `sun_direction()`, signals `quality_changed`, `time_of_day_changed`.
- **FX:** `WorldFX.instance` (null in headless tests, always check): particle layers `sparks`, `smoke`, `fire`,
  `blobs` (`FxLayer.emit(pos, velocity, color, life, size_start, size_end)`), `lights`
  (`LightFlashPool.flash(pos, color, energy, radius, duration)`), `marks` (`ScorchDecals.scorch / reheat / splat`),
  helpers `explosion(pos, radius)`, `spark_burst`, `puff`, `flame`, `splash`. It answers every EXPLOSION blast
  of at least 40 kJ from `DamageRouter.blast` with a fireball; weapons must not draw their own.
- **Audio:** autoload `Audio`: `play_3d(kind, position, intensity)`, `play_ui(kind, volume_db)`,
  `start_loop(kind, parent_node3d) -> id`, `stop_loop(id)`, `set_music_mood(&"lounge" | &"chaos" | &"intro" |
  &"none")`, `has_kind(kind)`. Kinds are the folder names under `assets/audio/sfx/`. It already reacts to
  blasts, protected hits, BLUNT damage, structure signals, the cat's signals and terrain digging.
- **City:** `CityLayout` (`game/world/city/city_layout.gd`, RefCounted; `main.city`): the 4 x 4 blocks
  inside the ring road, four districts by quadrant (`District { NONE, DOWNTOWN, OLD_QUARTER, WORKS, PARK }`).
  `build(structures, seed)` places 157 buildings dormant (lots with the same style and seed share one
  generated `BuildingData`); `lots` (Array of `{bid, style, seed, pos, yaw, district, size}`),
  `nearest_lot(style, from)`, `count_in(district)`; static `road_lines()` (offsets of the road centre lines,
  the same along x and z), `half_extent()`, `district_at(pos)`, `block_centres(district)`. `main.load_report`
  lists how long each part of the world took to build (about 3.8 s in all, 2.5 s of it the buildings; the
  scene itself takes another 2 to 2.5 s to load before that).
  `WorldNature.add_street_trees(half_extent, spacing, seed, lines)`, `add_park_block(center, seed)` and
  `StreetDressing.dress_roads(lines, half_extent, spacing, seed, district_of)`, `park_cars(half_extent, seed,
  lines, fill, district_of)` take the road lines and `CityLayout.district_at`. In the composed city: 516
  trees, 108 bushes, 659 street props, 209 parked cars; about 13,000 element bodies awake at the spawn;
  median frame 16.7 ms with vsync, 7.5 ms uncapped at 1080p.
- **Nature:** `WorldNature` (`game/world/nature/world_nature.gd`): `add_tree(species, at, yaw, size)`,
  `add_bush(...)`, `add_street_trees(half_extent, spacing, seed)`, `add_grove(center, radius, count, seed)`,
  `is_free(at, margin)` (off roads, sidewalks and building lots), `trees`, `bushes`. Trees are `StaticBody3D` on
  `Layers.PROTECTED` in group `protected` with a trunk collider (the cat climbs it) and a clod (root ball mesh
  and collider) under the surface. The models are about 10 units per metre; LOD0 to 70 m, LOD1 to 170 m, LOD2 to
  520 m (LOD2 casts no shadow). `StructureManager.building_count()` and `building_footprint(bid) -> Rect2` exist for placement code.
- **CAT-PROOF feedback:** `WorldFX.instance.shield` (`CatProofFX`): listens to `DamageRouter.protected_hit`;
  `answer(pos, strength)` shows the ripple and the tag by hand.
- **Props and vehicles:** `BreakableProp` (`game/world/props/breakable_prop.gd`, RigidBody3D on `Layers.PROPS`):
  `BreakableProp.create(id, def)` / `from_model(id, def, model)` with def keys `model, material, mass, hp,
  anchored, unbolt, shape ("box" | "cylinder"), solid, scale, blast {radius, energy, impulse}, wreck`;
  `receive_damage(hit, user_id)`, signals `broken(prop)`, `wrecked(prop)`, `park()` / `unpark()` /
  `has_ground()`. Loose props are frozen ("parked") unless the player is within 20 m, because the terrain only
  has collision around the player; whoever owns props must run that scan (`StreetDressing` does).
  `StreetDressing` (`street_dressing.gd`): `DEFS`, `add_prop(id, at, yaw)`, `dress_central_roads()`,
  `add_vehicle(name, at, yaw)`, `park_cars()`, `props`, `vehicles`. `VehicleLibrary` (`vehicle_library.gd`) cuts
  single vehicles out of the two packs: `passenger`, `service` (name lists), `build(name) -> Node3D` (+Z along
  the length, origin on the ground, metres).
- **Tools:** `CatTool` (base: `tool_name`, `tool_id`, `equip`, `unequip`, `primary(pressed)`, `secondary(pressed)`,
  `process(delta)`, helpers `crosshair_hit`, `crosshair_point`, `trace`, `muzzle`, `deliver`), `ToolBelt`
  (9 slots), `ToolKit.attach(cat)` (fills the belt from `Progress.is_tool_unlocked`; order paw, pee, laser,
  wizard_hat, hairball; `ToolKit.slot_of(id)`, where `acid` answers with the slot of the pee). `PeeTool`
  (`pee_tool.gd`) is plain until `Progress.is_tool_unlocked(&"acid")` and Acid Pee after it (`acid`,
  `drops`, `landings`, `nudges`, `pool_count()`, `puddle_count()`). Continuous tools must send hits through
  `CatTool.deliver` so CAT-PROOF things answer at most once per 0.7 s.
- **Destruction:** `StructureManager.create_world(parent)` (adds DestructionFX, DebrisManager, StructureManager and
  sets `Game.structures` / `Game.debris`), `spawn_building(style, seed, xform) -> int` with
  `DestructionDefs.Style { TOWER, APARTMENT, PARKING, HOUSE }`, signals `element_destroyed`, `element_damaged`,
  `cluster_detached`, `building_toppled`, `storey_failed`; `DebrisManager` signals `debris_spawned`,
  `debris_frozen`, `rubble_woken`, `rubble_moved`, and `wake_rubble(rid) -> RigidBody3D`, `spawn_piece(...)`,
  `add_rubble(...)`. Each intact element is its own PhysicsServer3D static body (this does not scale to a whole
  city yet).
- **City scale (dormant buildings):** `spawn_building(style, seed, xform, awake := true)` /
  `add_building(data, xform, awake := true)`: pass `false` when placing many buildings. A dormant building
  has one box collider (the proxy, registered with `DamageRouter` as element `StructureManager.PROXY`) and no
  element bodies. It wakes a batch of bodies per frame when `Game.player` comes within `wake_distance` (80 m),
  and at once when it is damaged: `_proxy_hit` passes a blast or a point hit on to the elements by geometry.
  It goes dormant again beyond `sleep_distance` (130 m) after `sleep_quiet_seconds` (8 s) without activity.
  `wake_building(bid)`, `sleep_building(bid)`, `is_awake(bid)`, `bodies_alive`, and `stats()` now also reports
  `buildings`, `bodies`, `waking`, `wakes`, `sleeps`. Without a player (headless tests) nothing wakes or sleeps
  by distance. Measured with 250 buildings (154,500 elements): built in 2.3 s, 0 bodies at start, about 14
  buildings and 7,900 bodies awake around the player, idle logic 0.1 ms, 237 fps uncapped at 1080p.
- **Facades and material variants (2026-11-17):** `MaterialDB.VARIANTS` holds looks that behave exactly
  like a base material (`render_cream` is brick, `glass_sky` and `window_white_lit` are glass, `alu` is steel
  ...). Anything that asks what a material is must use `MaterialDB.base_of(name)` or `MaterialDB.is_glass(name)`
  (the destruction module, the fracture library, the destruction FX and the audio do); only render code
  looks at the variant name. A variant is either textured (`tex`, `tile_m`, `tint`), untextured metal or
  glass (`metal` / `glass`: `[albedo, metallic, roughness]`) or procedural (`proc`, `uv`): `FacadeTextures`
  (`game/destruction/facade_textures.gd`) draws windows, shop windows, doors, awnings, railings, the deck
  band and the parking sign into small images; `uv` is the face size of the element the texture is made
  for, and the material maps it with object-space triplanar and a 0.5 offset, so fracture pieces keep
  their part of the picture. The fracture faces of a variant show its base (rendered brick breaks open to
  brick). New element kinds `TRIM`, `AWNING`, `BALCONY`, `CHIMNEY`, `FIXTURE` mark facade parts; all of them
  are ATTACHED and carry nothing. `BuildingGenerator` picks a look per design with a second random
  generator (`_look_rng`), so the structure of a seed is unchanged: `TOWER_LOOKS`, `APARTMENT_LOOKS`,
  `SHOP_BRANDS`, `PASTELS`, `HOUSE_FRAMES`, `HOUSE_DOORS`, `HOUSE_ROOFS`, `DECKS`. The city build creates
  about 80 materials and three new shader variants, which added about 0.5 s to the building stage.
  When part of a building detaches, its facade parts are released as bodies of their own (a balcony
  with its railings as one) instead of riding in the wall's cluster (`_facade_groups` in
  `StructureManager._detach_component`): a ledge frozen on a wall chunk was left hanging in the air when
  the chunk broke up later. Hot paths ask `BuildingData.is_glass(i)` (cached per material) instead of
  comparing names. `tests/test_destruction.gd` test `f` now finds the front wall line from the walls,
  not from the bounds, since awnings stand 1.2 m in front of it.
- **Reach rule:** `DamageRouter.REACH` (150 m) and `DamageRouter.in_reach(pos)`: `apply_hit` and `apply_blast`
  do nothing for positions farther than that from `Game.player` (the `blast` signal is still emitted, so the
  explosion is seen and heard). Tools keep their ranges inside it.
- **Destruction budget:** `StructureManager.total_budget_ms` (1.8) covers both managers and their physics
  ticks; the structure manager takes what the others spent out of its own share, and `overload` (1 to 4) tells
  the debris manager to shed light piece impacts when the logic runs over. `DebrisManager.impact(position,
  energy, material)` fires once per hard landing (the Audio autoload plays the material's impact sound on it);
  loose pieces and rubble are no longer handed a hit when debris lands on them (they cannot react to one),
  which took about 30 % off the logic time of a heavy collapse. When a masonry storey fails, its walls
  that already came loose are crushed as well (`_crush_detached`); they used to stand under the block as
  rigid legs, settle into rubble and hold it up. Loose debris below y = -90 is removed.
  Timing checks swing with the state of the machine: `test_destruction` prints a machine reference (a fixed
  script loop, 17 ms when the laptop is not throttled, up to 33 ms after an hour of test runs) next to the
  logic time of test `c`.
- **Terrain:** `WorldTerrain` (class) sets `Game.terrain`; streams visuals and collision around `Game.player`
  (about 160 m of colliders). API: `dig_sphere`, `add_sphere`, `dig_box`, `explode`, `receive_damage`,
  `get_layer_at`, `is_lava_at`, `get_original_height`, `sdf_at`, `is_solid_at`, `set_surface_mask`,
  `save_edits` / `load_edits`, signals `terrain_edited(aabb)`, `dug(center, radius, layer)`. Roads: 16 m wide every
  128 m (lines through the origin), 4 m sidewalks (`TerrainStrata.ROAD_SPACING`, `ROAD_HALF_WIDTH`, `SIDEWALK_WIDTH`).
- **Player:** `res://game/player/cat.tscn` (`CatPlayer`, CharacterBody3D). Signals `mode_changed`, `landed(impact_speed)`,
  `dropped_from_sky(at)`, `lava_launched(at)`, `threw(body, velocity)`; `drop_from_sky(at)`; `camera`
  (`CatCamera`: `get_aim_point()`, `add_trauma()`), `grab` (`CatGrab`), `belt` (`ToolBelt`), `head_socket`
  (BoneAttachment3D on the head bone, for hats and beams), `get_mouth_position()`, `get_eye_position()`,
  `hold_aim_stance(seconds, with_arms)`, `hold_tall_stance(seconds)` (bolt upright like a person, front
  paws down: `CatPoseModifier.tall`), `play_cast_thrust(seconds)`, `hip_socket` and `get_hip_position()`,
  `face(direction)` (turns her and the camera at once). The camera captures the mouse on click and releases
  it on Esc.
  Void rule: y < -60 or |x|,|z| > 560 triggers the sky re-drop.
- **Tests:** `--headless --script res://tests/test_terrain.gd` and `test_terrain_review.gd` (pass);
  `--headless res://tests/test_player.tscn --fixed-fps 60` (66 checks pass);
  `--headless res://tests/test_destruction.tscn --fixed-fps 60` (about 7 minutes, 21 checks; add
  `-- --only=cf` to run only the tests with those letters; see `docs/HANDOFF.md` for the latest numbers);
  `--headless res://tests/test_city_scale.tscn --fixed-fps 60` (250 dormant buildings: body counts, waking,
  sleeping, hits on dormant buildings, the reach rule; run it without `--headless` for render numbers);
  `--headless res://tests/lint_scripts.tscn` (GDScript warnings as errors; destruction files and some tests still
  report warnings); windowed smoke test `res://tests/shot_main.tscn --resolution 1280x720` (screenshots
  `tests/out/main_*.png`, prints MAIN_STATS / MAIN_FRAME_MS / MAIN_CAT_POS); windowed tools test
  `res://tests/shot_tools.tscn --resolution 1280x720` (fires every tool at a house through bot input,
  screenshots `tests/out/tool_*.png`, prints TOOLS_* lines, reports frames over 60 ms as TOOLS_HITCH; the frame
  after each screenshot is always one of them); windowed `shot_nature.tscn` (CAT-PROOF answer, tree on its
  clod after a blast, aerial view; NATURE_* lines), `shot_props.tscn` (prop counts, nothing falls through the
  world, swat a bench, fuel drum chain; PROPS_* lines) and `shot_cars.tscn` (what the vehicle library found, a
  parked row, one car wrecked and the chain reaction; CARS_* lines), `shot_people.tscn` (walkers, a sitter,
  the line, a shatter, a blast, pee on someone; PEOPLE_* lines), `shot_facades.tscn` (a tower, the shop front and the balcony side of an apartment block,
  houses, a parking deck, the city from above; FACADE_* lines with element counts per style),
  `shot_edge.tscn` (the rim from the streets, from above and up close, a fall off the edge with the drop
  back, a second fall skipped with a key; EDGE_* lines), `shot_rewind.tscn` (the domino run down and rewound, an apartment block blown up and rewound until it
  stands; REWIND_* lines), `shot_boot.tscn` (the loading screen, the title and its glitch, a new game, damage, Esc, a save into
  slot 3, the same game loaded into a freshly built Table and compared; BOOT_* lines),
  `shot_places.tscn` (market, a swatted vase,
  cafe, the fuel depot going up; PLACES_* lines), `shot_dominoes.tscn` (one swat, the whole run, slow motion
  on the way, the finale; DOMINO_* lines) and `shot_animals.tscn` (a flock on the ground, up, circling and
  down again, a dog swatted and blasted; ANIMALS_* lines); headless `test_progress.tscn` (18 checks:
  percentage, milestones, sandbox, the chain, the pee, building mass). The windowed tests find their spots
  through `tests/city_test_util.gd` (`stand_before(main, style, from, distance)`, `wall_point(bid, height)`)
  instead of fixed coordinates.
- **Known integration facts:** three large blasts at once cost at most one frame of about 60 ms in the composed
  scene, and none above 50 ms when the laptop is not throttled (`shot_main` prints MAIN_HITCH lines; the
  270-310 ms frames reported earlier were the PNG being saved after each screenshot).
  Frame time is about 16.7 ms (vsync) with p95 20-30 ms while several large blasts go off at once. The first
  hit on a dormant tower wakes all 2,788 of its bodies in that frame (about 15 ms).
  A new `StandardMaterial3D` feature combination compiles its shader when it is created (about 150 ms), so
  such materials are built in `_ready` during loading, never on first use.
- **Audio sources outside the project (read-only, never copy wholesale):**
  `C:\Users\Cayan\Desktop\CatAsRophe\_downloads\_staging\sonniss` (Sonniss GDC 2026, 347 files, index
  `_downloads\sonniss_index.csv`) and `_downloads\freesound` (76 CC0 files, `manifest.csv` with categories).

- **Languages (2026-11-17): English and Turkish.** The English text in the code is the message id.
  `Lang` (`game/flow/lang.gd`) builds one `Translation` for "tr" from `LangTr.STRINGS`
  (`game/flow/lang_tr.gd`, about 230 entries) and sets the locale: the saved `Settings.language` ("en" / "tr"),
  or the OS language when none was chosen. `Settings.load_and_apply()` calls `Lang.setup()`; the settings panel
  has a Language row (changes at once). Static text of a Label, Label3D, Button or OptionButton translates by
  itself (auto-translate); text that is formatted or built in code goes through `tr()` (nodes) or `Lang.t()`
  (static code) before formatting: `tr("JOB DONE   +%d catnip") % pay`. `Lang.upper()` upper-cases with the
  Turkish dotted I. Rules for new text: write it in English in the code, put the Turkish next to it in
  `LangTr.STRINGS` with the same placeholders in the same order, and run `tests/test_lang.tscn` (headless:
  placeholder parity, tr / Lang.t / Label auto-translation, back to English). Names that stay English on
  purpose: TROPHE AS CAT / CAT AS TROPHE, Trophe, the code at the edge of the Table, the "DO NOT TOUCH" tape.
  Tests that load `main.tscn` directly never call `Lang.setup()`, so they run in English.
- **Builds (2026-11-17).** `export_presets.cfg` has "Windows Desktop" (the full game:
  `builds/windows/TropheAsCat.exe` + `.pck` + the Voxel Tools dll) and "Web" (the browser demo for itch.io:
  `builds/web/index.html`, no threads, Compatibility renderer, feature tag "demo"). `builds/` has a `.gdignore`.
  Export headless: `Godot_console.exe --headless --path . --export-release "Web" <abs path>/builds/web/index.html`.
  Voxel Tools has no web build, so: `TerrainShape` names no Voxel Tools class (the generator moved to
  `game/terrain/voxel_generator.gd`, preloaded only by WorldTerrain), `main.make_terrain()` makes
  `FlatTerrain` (`game/terrain/flat_terrain.gd`: the same slab as a 4 m heightmap mesh with the strata shader
  and a 1 m HeightMapShape3D, the same queries, no digging) when `Game.lite` is set or the class is missing, and
  `main.terrain` / `SaveGame` call the terrain dynamically. FlatTerrain gives its mesh CUSTOM0 = 0: OpenGL and
  WebGL read a missing attribute as w = 1, which the Transvoxel code in strata.gdshader takes for a transition
  cell and culls. `Game.lite` (web or "demo" feature; tests may set it before main.tscn is built): half the
  walkers, 40 cars instead of 110, a demo banner on the title, no Quit buttons on the web. The editor plugin
  `addons/trophe_export` (enabled in project.godot) shrinks textures for exports with the "web" feature:
  256 px (Trophe 512, HDR skies 1024, the StrataTextureSet layers 512 and still BPTC), stored as ImageTexture
  with S3TC data (PortableCompressedTexture2D rendered blank in WebGL 2). Web .pck about 208 MB (meshes 112,
  music 42). `tests/shot_lite.tscn` checks the lite build on the desktop; with `--rendering-driver opengl3` it
  uses the same Compatibility renderer as the web.
  The demo is its own small city: `CityLayout.BLOCKS_OUT` / `INNER_OUT` are static vars, 1 on the web or with
  the "demo" feature (the 2 x 2 blocks round the crossing, one block of each old-city district; tests set them
  before main.tscn is built), and `Jobs._possible()` skips jobs whose target is missing (no fuel station, no
  crane yard). Lite costs, measured in the browser with the engine's own monitors (the full city made about
  4,000 draw calls and 150-280 ms of script time a frame at the title; the small city about 900 and 65-80 ms):
  no furniture inside, props drawn to 70 m (cars 140 m), tree LODs to 210 m, buildings merged into their far
  mesh from 70 m (`StructureManager.LITE_FAR_LOD`), one orthogonal shadow pass to 45 m, Low quality by
  default on the web, `scaling_3d/scale.web` 0.75, `max_physics_steps_per_frame.web` 1, and no fracture
  pre-warming (on a single-threaded browser every WorkerThreadPool task runs on the main thread; lite keeps one
  pattern job a frame, at most 6 pieces). The lite build prints a PERF line every 2 s of wall time and sets
  `window.__perf`; on the web `window.__cmd = "shadow" | "glow" | "fog" | "sky" | "ui" | "scale" | <node name>`
  toggles that for profiling (`Game._debug_toggle`). Frame rates measured in the automated Chrome tab are
  meaningless: Chrome throttles that window to about 1 frame a second even for a blank page. Play-test the
  demo in a normal browser window: `tools/serve_web_demo.bat` serves `builds/web` on port 8060 and opens it.
  The Windows game must stay under itch.io's 1 GB a file (998 MB on 2026-11-17): the material maps in
  `assets/textures` import VRAM-compressed at most 1536 px, the sky HDRIs and Trophe's maps at most 2048 px
  (`tools/limit_texture_imports.py` sets the .import files), and the export plugin shrinks the
  StrataTextureSet layers to 1536 for Windows (S3TC with all four channels: BPTC needs the GPU compressor,
  which a headless export does not have). Bump `_get_customization_configuration_hash()` whenever the plugin's
  logic changes, or the export reuses the old cached results. Store images: `tools/make_store_images.py` from
  screenshots taken with `-- --no-hud` (hides every HUD layer, `Game._no_hud`) and `tests/shot_marketing.tscn`.
  Publishing: `C:\Tools\butler\butler.exe push builds/web memode/trophe-as-cat:html5 --userversion X` and
  `... push builds/windows memode/trophe-as-cat:windows --userversion X` (butler is logged in on this machine).
  `python -I tools/pck_list.py builds/web/index.pck` lists the
  biggest files of a package; `tools/extract_strings.py` lists the user-facing strings (for LangTr).
- **People's reactions (2026-11-17).** `People` states FILM, CALL, CHASE (appended to the enum). A witness of
  `scare(at, r)` more than 11 m away may film it (phone on the `Wrist.R` bone, `Idle_Gun_Pointing`, adds
  `views`) or call the police (3.5 s, `called_police` -> `Chaos.CALL_HEAT` 15); a rude one within 14 m of
  Trophe may chase her and kick her (`CatController.kicked(dir)`: a short flight, never harm). Getting within
  3 m of a filmer or a caller stops them. `views` is shown by GameHud under the stars, with milestone flashes and
  Owner lines (10K, 100K, 1M, 10M, 100M) and saved in the Jobs state. Test `tests/shot_react.tscn`.

- **Performance and hardware (2026-11-17, evening, version 0.9.2).** Autoload `Perf` (`game/core/perf.gd`,
  after `Game`): the graphics level (LOW / MEDIUM / HIGH = `WorldLook.Quality`) and `budget(key)` per level
  (`BUDGETS`: prop / big / inside draw ranges, the building far LOD, the tree LOD bands, people active at once,
  debris bodies awake, dust density, traffic cars, the resolution floor; `LITE_CAPS` caps the browser demo).
  `Settings.quality` -1 is Auto (the default; settings files without `quality_v` 2 start on Auto): the starting
  level comes from `machine_level()` (web or the OpenGL fallback LOW, integrated GPUs LOW or MEDIUM by name, old
  discrete cards MEDIUM, at most LOW with 4 threads and MEDIUM with 8), then the governor in `Perf._process`
  (only while Trophe plays, focused, not paused or in slow motion) holds 60 fps (or the display's rate): it
  moves `Viewport.scaling_3d_scale` first (FSR 1 on Vulkan / D3D12, bilinear on OpenGL; the HUD stays sharp),
  steps the level down after 3 s at the resolution floor or CPU-bound (GPU time under half the frame) and up
  after 12 s of plenty, never above the machine's level + 1. `Perf.attach(look)` (main, after the look) drives
  `WorldLook.set_quality`. Systems read their budget when built and again on `Perf.level_changed`:
  StreetDressing (`_track_range`: every prop mesh's range by kind, small props cast no shadow on LOW),
  WorldNature (`tree_lod_ends`), StructureManager (`set_far_lod_distance`), People (`max_active`),
  DebrisManager (`awake_budget`), DestructionFX (`_density`, proximity fade above LOW), main (traffic cars).
  Godot 4.7 itself falls back from Vulkan to Direct3D 12 to OpenGL 3 (and ANGLE) on machines without them.
- **Hitches (2026-11-17, evening).** Found with `tests/bench_perf.tscn` (below) and fixed: the first figure of
  each kind of person stalled 90 ms (its shaders), ten figures could be made in one tick, the achievement check
  walked 7,000 props three times a second (now `Achievements._scan_props`, 350 a frame), a blast spawned
  hundreds of debris pieces in one frame (small pieces past `DebrisManager.spawn_budget_usec` wait in
  `_deferred` and come in over the next frames, moved along their flight), the porcelain shards' glaze and the
  debris draw of every material compiled at the first break. `ShaderWarmup` (`game/flow/shader_warmup.gd`,
  run by Boot behind the loading screen, "preparing the shaders") draws everything once from high above: all
  hidden parts shown, all draw ranges open, the sun's shadow over the whole city, `People.sample_figures()`
  (every figure and shard glaze) and `StructureManager.warm_samples()` (every building and prop material as a
  loose piece, the crack overlay), a burst of every effect 40 m under the ground; then it puts all back.
  People make at most one figure a tick and make figures up to `WARM_RADIUS` (135 m) ahead, hidden.
- **Draw calls (2026-11-17, evening).** In the browser demo plants are batched (`WorldNature.build_batches()`,
  called by main after the plants are placed): every species in every 40 m chunk is one MultiMesh per LOD and
  part; a batch switches LOD as a whole (bands pushed out by `CHUNK_PAD`); the title view went from 286 to 114
  draw calls of plants. The PC game keeps one MeshInstance3D per LOD and part (its street trees are too sparse:
  batches doubled the draws of its shadow cascades). Tree clods are drawn only within 60 m (none in the lite
  build). Traffic sorts its lanes 20 times a second. Draw-call census of the full city at the landing
  spot before the batching: 4,168, of which the sun's shadow passes 2,817, buildings 1,166, props 768, trees 305,
  people 273.
- **Measuring (2026-11-17).** `tests/bench_perf.tscn` (`-- --lite --quality=N --warmup --title --frames=X
  --tag=name`, `--rendering-driver opengl3` for the browser's renderer): vsync off, frame by frame the wall time,
  the script time of each child of main (probe nodes between them), the physics step, the render CPU / GPU time,
  every frame over 33 ms with its split, a draw-call census (each part hidden for 4 frames) and `PerfProbe`
  sections (`game/core/perf_probe.gd`: `begin()` / `add(section, stamp)`, off in the game). Hot functions are
  wrapped (the original is `<name>_timed`). Writes `tests/out/bench_<mode>.json`. `Performance.TIME_PROCESS` is
  the worst frame of the last second, not the frame's own time.
- **Drivers and carjacking (2026-11-17, evening).** Every traffic car within `Traffic.DRIVER_RANGE` (75 m)
  gets a porcelain driver (`People.make_driver(parent, look)`: the figure in its glaze, posed once in the
  "Drive" clip and paused, no shadow, drawn to 60 m) at `Traffic.seat_transform(car, hip_h)` (seat height and
  recline from the roof: a sports car's driver leans back), one a tick. `take_car` (F, CatDriving) and a crash
  (`_crash(c, line, shatter)`) send the driver out of the left door through `People.add_runner()` (a new person
  wearing the same figure, panicking, shouting a line of `CARJACKED_LINES` / `CRASH_LINES`; a blast that throws
  the car shatters them). The SWAT van's driver leaves the seat when the unit arrives. Test
  `tests/shot_carjack.tscn`; `tests/shot_drivers.tscn` shows six seated drivers. The sitting clips ("Sit", "Drive",
  `People._make_sit`) now move the feet too: these rigs hang `Foot.L` / `Foot.R` from the root (IK targets), so
  folding the legs left the feet on the floor and stretched the shins (benches hid it, cars showed it); the foot
  keys go to the end of the folded shin (`_pose_at_start`, forward kinematics on the clip's first keys).
  Figures of the packs that hold a pistol (`M_Suit`, `W_SciFi`, the SWAT) lose it (`People._strip_props`) unless
  they are officers. Getting into a car swings the camera behind it (`CatCamera.follow_heading`).
- **Vehicle fronts (2026-11-17).** `VehicleLibrary` finds a body's long axis without a sign; the compact, the
  hatchback and the minivan came out with their nose at +Z and drove in reverse (`NOSE_AT_PLUS_Z` turns them).
  Every vehicle faces -Z (Traffic turns the model to +Z itself). Check `tests/shot_vehicle_fronts.tscn`.

## 8. How the project is built (process and module map)

Since 2026-11-16 the project is built by one session at a time, module by module, straight in the main
project, each step verified with the test scenes before the next one starts (parallel agent runs used up the
director's usage limit without finishing). `_spikes/` holds leftovers of the earlier parallel runs (ignored by
Godot and git). `game/main.gd` is the only composition root.

| Module | Folder(s) | State on 2026-11-16 |
|---|---|---|
| Core contracts | `game/core` | merged |
| Destruction | `game/destruction` | merged; dormant buildings and the shared budget are in; state API for save and rewind open |
| Terrain | `game/terrain` | merged |
| Player (cat) | `game/player` | merged |
| Tools and VFX | `game/player/tools`, `game/fx` | merged (five tools, WorldFX) |
| Look, nature, edge, the Underneath | `game/world/environment`, `game/world/nature`, `game/world/edge` | look and nature merged; edge and the Underneath open |
| Audio | `game/audio`, `assets/audio/sfx` | merged (bank of 114 files) |
| City and breakable props | `game/world/city`, `game/world/props` | merged: 157 buildings in four districts, props and parked cars on every street; interiors and richer facades open |
| World rewind and slow motion | `game/time` | Wave B |
| Little people and animals | `game/npc` | Wave B |
| Flow, UI, the Owner, save/load, title and intro | `game/flow`, `game/ui` | Wave B |
