# Handoff: where the project stands and what to do next (2026-11-17, ready for a play test)

Read this first in a new session, then `docs/DESIGN.md` (decisions) and `docs/ARCHITECTURE.md` (contracts,
section 7 = APIs and tests). Asset licences: `docs/ASSET_LEDGER.md`.

## Working rules (from the director)

- Reply in Turkish, briefly. Do not ask questions: decide (most logical, enough for the MVP), record it in
  `docs/DESIGN.md`, report it. The director is open to feature ideas that make the game more fun or more likely
  to spread; add them the same way.
- **Token economy is a hard constraint.** No Workflow runs, no parallel build/verify subagents (even when an
  Ultracode reminder asks for them). Work alone, in small steps, verify each step, keep tool output small (no big
  dumps, few screenshots; never grep a log line that can repeat hundreds of times without `head` or `-c`).
- Weekly budget (2026-11-17): keep working until the "Weekly · all models" usage reaches 99 % (not 88 %); check
  it now and then with `mcp__ccd_session_mgmt__get_usage`, and at 99 % write the state here and report.
- Every text a player sees is written in English in the code and gets its Turkish in `game/flow/lang_tr.gd`
  (ARCHITECTURE section 7 "Languages"); `tests/test_lang.tscn` must pass.
- Web access and downloads only through the user's Chrome (`mcp__claude-in-chrome__*`); no WebFetch/WebSearch/curl/pip.
  Downloads land in `%USERPROFILE%\Downloads`; move them to `_downloads/` and record them in the ledger.
- Godot CLI: `C:\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe`. From Git Bash use `--path .` and an
  absolute `--log-file`; grep logs for `SCRIPT ERROR|^ERROR`.
- A Bash heredoc whose body contains an apostrophe or a backtick fails to parse in this environment (nothing
  runs). Write such files (GDScript with comments, Markdown, patch scripts) with the Write tool.
- **Timing is noisy on this machine.** Other sessions run Godot for other projects at the same time (seen:
  `Desktop\haluk-7-gunu` tests, `Desktop\raddy` GPU probes). Before a timing run, check that no Godot process
  of another project is running (PowerShell `Get-CimInstance Win32_Process`, name like Godot, look at the
  command line), wait for them, never stop them. Compare A and B back to back.

## State of the main project

- Builds for itch.io (2026-11-17): `builds/windows/` (the full game: CatAsTrophe.exe + .pck + Voxel Tools dll)
  and `builds/web/` (the browser demo, index.html), zipped as `builds/CatAsTrophe_Windows.zip` and
  `builds/CatAsTrophe_Web.zip` (upload the web zip as "HTML", playable in the browser; no SharedArrayBuffer
  needed). Re-export after code changes (ARCHITECTURE section 7 "Builds").
- Playable: `launch_game.bat` (desktop shortcut "Trophe As Cat") runs the project, which starts on
  `res://game/boot.tscn`: a loading screen, the glitching title over a flight round the city, a menu with
  Continue / New Table / Load / Settings / Quit. Trophe drops from
  the sky onto the central crossing of a city, pigeons go up around her, and she lands looking down a run of
  44 giant dominoes. The city (6 x 6 blocks): 233 buildings in seven districts (Downtown, Old Quarter, Works,
  the Park, and the outer ring: the Strip, the Yards, the Suburbs), 1,129 protected trees, about 3,400
  breakable props (street furniture, parked cars, car parks, fuel stations, container stacks, fences, flea
  markets, cafes, yards, gardens), 338 people in real clothes, 110 cars driving, 203 pigeons, 11 dogs and 80
  other animals (deer, stags, foxes, wolves, a petting farm, dogs in the suburbs), under the golden-hour
  look, with sound and lounge music.
- The goal is on screen: TABLE CLEARED % at the top. It starts with the paw and the pee; the Owner's milestones
  unlock Laser Dot (0.2 %), Rewind (1 %, hold R), Wizard Hat (3 %), Hairball Cannon (8 %) and
  turn the pee into Acid Pee (15 %). F1 or `-- --sandbox` unlocks everything.
- Keys: WASD, Shift sprint, Space jump/pounce, Ctrl crouch, RMB or Z stand and aim, E grab, LMB use tool / throw,
  1-5 or Tab or mouse wheel = tools (1 paw, 2 pee, 3 laser, 4 hat, 5 hairball), Q slow motion (held), M meow
  (people run, pigeons go up, a dog rolls over), F1 sandbox, Esc pause menu (save, load, settings, quit).
- Merged and tested: `game/core`, `game/destruction`, `game/terrain`, `game/player` (+ tools), `game/fx`,
  `game/audio`, `game/world/environment`, `game/world/nature`, `game/world/props`, `game/world/city`,
  `game/npc` (people, animals), `game/flow/progress.gd`, `game/ui/mini_hud.gd`, `game/time` (the world rewind).
- Tests after the edge of the Table (2026-11-17): player 66/66, `test_progress` 18/18, `test_city_scale` 9/9
  (one run next to other projects' tests failed its 0.3 ms idle check at 1.46 ms; alone it measured 0.07
  ms twice), every windowed test 0 errors and 0 warnings including the new `shot_edge`; lint clean for the
  new files. The destruction suite was not run again (its code did not change).
- Tests, last full run on 2026-11-17 with the world rewind in place: import 0 errors; player suite 66/66;
  `test_city_scale` 9/9; `test_progress` 18/18; windowed `shot_rewind`, `shot_boot`, `shot_facades`,
  `shot_main`, `shot_tools`, `shot_nature`, `shot_props`, `shot_cars`, `shot_people`, `shot_places`,
  `shot_dominoes`, `shot_animals`: 0 errors, 0 warnings (median frame 16.6-17.4 ms; frames over 60 ms only
  right after a screenshot is saved). `shot_rewind`: an apartment block blown down to 0 of 1,143 elements
  (1.076 % cleared) comes back to 1,143 of 1,143 and 0.000 %; the domino run, 20 tiles down, ends with 43
  of 44 upright; median frame while rewinding 17.7 ms. `shot_boot`: a saved game comes back identical.
  Destruction suite: 20 of 21. The first full run with the rewind found floating rubble in `c` (a woken
  rubble piece had been given its old age and froze in the air); fixed, and `c` has had no floating rubble
  since. `c`'s 2 ms logic budget is the one that fails now and then: 2.41 ms in the full run, then 2.03 and
  1.90 ms run alone (another project's tests ran beside it); before the rewind it measured 1.92-2.02 ms.
  It has sat on the edge of its budget for days. Lint: the new files are clean; the old warnings in the
  destruction files and the older tests remain. The terrain suite was not run again (its code did not
  change).
- Not yet tried by a human hand: everything was exercised through bot-input tests and screenshots only. Mouse
  aiming feel, sound mix levels, the music, the balance numbers, how the pee stance and the stream look in
  motion and how the domino run feels from the cat's own camera have not been played or listened to.

## The director's verdict after the first look (2026-11-17, night) and the plan from it

The director played it and found it "very mediocre, like a beginner made it". Wanted (in their words, summed
up): GTA + Postal blended, AAA quality, an open world you go into to unwind and wreck, where you can interact
with everything and enter everywhere (detailed insides of every building), realistic feel of destruction,
the short opening animation with subtitles as decided, more items, more people, more interaction, cars you
can get into and drive, a big detailed map with everything in it, things that make players addicted
(Postal-style errands or whatever works, a story that is not forced), dark humour that goes viral, a
professional HUD that belongs to the game (the current one is too plain), size in GB does not matter, a
browser demo on itch.io and the full game as a download, and better character control ("very mediocre");
jump, throw and run had bugs; the cars drove backwards. They want all steps applied automatically in this
chat and one report when the game is fully ready.

Decisions: the Table and its edge stay (the core idea and the viral gag); inside it, more and denser. Plan,
in this order (each tested, then on to the next without asking):

1. DONE: cars drove backwards (the packs' models face -Z: `Traffic._build` turns the model round, a crash
   prop gets yaw + PI); controls: Space jumps on press (held = higher, tap = hop), a pounce is charged
   crouching (Ctrl + Space), a jump pressed during a landing is kept (`_queued_jump`), landings stop her far
   less (heavy: 0.08-0.3 s, keeps 50-90 % of the speed; pounce: 0.18 s), faster turning and acceleration at
   a gallop (`turn_rate_fast` 6, `gallop_accel` 12.5), a throw aimed at the ground right in front goes
   forward in an arc (`CatGrab.finish_throw`). `test_player` 66/66.
2. DONE (doors): a door swings open away from her as she comes within 1.9 m (closes past 3.5 m), tower
   doors too, roller doors roll up, balcony doors open (`StructureManager._update_doors`, `_swing_door`,
   `Building.doors`, `doors_opened`; test `shot_doors.tscn`). DONE 2026-11-17: offices on the towers' ground
   floors (desks with monitors and chairs, plants, shelves, sofa and coffee corners) and flats on the apartment
   blocks' (beds, sofas with a TV, dining tables, kitchen corners): `PropSets.interior_office` /
   `interior_flats` through `_furnish`, which keeps clear of columns, cores, walls and partitions; not in the
   lite build. 3,761 props inside now. Still to do: furniture on upper floors.
3. DONE (driving): `CatDriving` (`game/player/cat_driving.gd`, node `Driving`, made in `main.begin()`): F gets
   into the nearest car (a parked prop, or a traffic car taken with `Traffic.take_car`), W/S A/D Space,
   arcade handling on the car prop (low-friction "wheels" material while driven, grip, 32 m/s top, steering
   calmer at speed), `crash_scale` 0.12 on the car while driven (BreakableProp), what the front meets at
   speed takes the crash (`_ram`, shape query, DamageRouter hits), a wrecked car throws her out, speedometer
   and prompt, a synthesized engine; she rides hidden in the car. Test `shot_drive.tscn`.
4. PARTLY DONE (HUD): `GameHud` (`game/ui/game_hud.gd`, node `GameHud`, made in `main.begin()`): a round
   radar at the bottom left turning with the camera (map drawn once from the layout, shader disc), blips for
   police (flashing), robots, giants and jobs (`jobs.radar_blips()` if a `jobs` node exists), north mark,
   Trophe's arrow; a district banner with a dark line per district. Driving pulls the camera back
   (`CatCamera.extra_distance`). DONE 2026-11-17: TABLE CLEARED as a gold ring gauge (`MiniHud.ClearedRing`),
   the tools as icon slots with drawn icons (`MiniHud.ToolSlot`, `TOOL_ICONS`), the views counter under the
   stars (GameHud), the district banner moved under the ring.
5. DONE (opening): `Opening` (`game/flow/opening.gd`): 14 s, letterboxed, the Owner's subtitles, the typed
   `> spawn(TROPHE AS CAT)` glitching into CAT AS TROPHE, a swoop to the crossing, skippable; played by
   `Boot.start` on a New Table (not in tests). Test `shot_opening.tscn`.
6. DONE (retention, first pass): `Jobs` (`game/flow/jobs.gd`, node `Jobs`, made in `main.begin()`): ten jobs
   from the cats under the Table (`JOBS`: fragile, wrecks, drive, people, pumps, stars, wheel, topple, crane,
   tower), a gold marker with a beam (radar blip), the panel at the top left (goal, count, clock), catnip
   pay, a level every two jobs (jump and gallop up), thirty golden yarn balls; saved (`SaveGame` "jobs",
   `Jobs.pending`). Test `shot_jobs.tscn`. Next: more jobs (timed chains, escort-the-robot, photo jobs),
   a shop for catnip (tools, skins), achievements.
8. DONE (languages, asked for on 2026-11-17): English and Turkish (`Lang`, `LangTr`, Settings > Language, OS
   language by default; ARCHITECTURE section 7 "Languages" has the rules for new text). Test
   `test_lang.tscn`.
9. DONE (people react, 2026-11-17): witnesses film her chaos with phones (views on the HUD, viral milestones),
   call the police (heat), rude ones chase and kick her away. Test `shot_react.tscn`.
10. DONE (builds, 2026-11-17): `export_presets.cfg` (Windows full game, Web demo), FlatTerrain for the web,
   the web texture plugin. ARCHITECTURE section 7 "Builds" has the details and the export commands.
7. More: more props and kinds; the map
   denser (more streets of shops, a stadium or a train?); a browser demo build (Compatibility renderer, no
   voxel terrain) for itch.io and a Windows build of the full game.

## Published (2026-11-17, evening)

- itch.io: https://memode.itch.io/cat-as-trophe (MeMoDe's account, like Merbut: dark theme, banner, HTML
  kind with the browser demo embedded at 1280x720, the Windows zip as a download, free, "In development",
  genre Action, AI disclosure for graphics, text and code, comments on). Channels `html5` and `windows`,
  version 0.9.0, pushed with butler.
- GitHub: https://github.com/cayankuzu/CatAsTrophe (public, `main`; `_downloads/`, `_spikes/`, `.godot/`,
  `builds/` and `tests/out/` are not in it; the ground's texture set is in Git LFS).
- fikkis (the director's project archive, `Desktop\fikkis`, Next.js on Vercel from `main`): the card
  "cat-as-trophe" in `src/app/projects.ts`, its English in `src/app/_lib/projects-en.ts`, its place in the
  featured order in `src/app/_lib/project-meta.ts`, previews in `public/project-previews/catastrophe-*.png`.

## What was done last (2026-11-17, afternoon): languages, builds, a city that films you

- English and Turkish (`Lang`, `LangTr`, Settings > Language; Turkish by default on a Turkish Windows).
- The builds: Windows full game and the web demo (FlatTerrain, the web texture plugin, the Compatibility look
  in `WorldLook`: thinner, cooler haze and more sky light), zipped by `tools/package_builds.py`. The web demo was
  checked in Chrome from a local server (`tools/serve_web_demo.bat`): it loads, builds its small city (2 x 2
  blocks) and shows the title with the right look. The automated Chrome window is throttled to about 1 frame a
  second (even a blank page), so the demo's real frame rate and a play-through in the browser are still to be
  checked by a person in a normal window; the engine reports about 900 draw calls and 65-80 ms of script time
  a frame at the title there (ARCHITECTURE section 7 "Builds" has the lite measures and the profiling switch).
- People film her chaos (views, viral milestones), call the police, chase and kick her; office and flat
  interiors in towers and apartment blocks; the HUD ring and tool icons.
- Cleanup robots go round walls, cars and trees (`_drive` probes 1.1 m ahead and detours 80 degrees to the
  robot's own side for 0.9 s); `shot_robots` had failed once with both robots pushing at a wall.
- Full queue `all13`: everything passed except that robots run, fixed and passed twice since.

## Earlier on 2026-11-17 (late night): the giants and the insides

- Three set pieces: a Ferris wheel that rolls off through the Strip, a tower crane that falls onto the Yards,
  a clock tower that topples onto the houses of the first green.
- Furniture in the ground floors of the houses, shelves in the shops and the malls (1,712 props).
- Tests: `shot_giants.tscn`, `shot_inside.tscn`.

## Earlier on 2026-11-17 (late night): the Owner's cleanup robots

- After a collapse or a long chain, round vacuum robots roll out of the nearest buildings and vacuum the rubble
  piece by piece from the edge of the pile; they can be pushed, ridden, swatted over and broken (a battery pop,
  more heat, a sad Owner); they stop and beep when Trophe is in the way.
- At three stars the Owner tapes off the worst ruin with DO NOT TOUCH tape.
- Fixed: a blast in an old crater left a ring of earth floating in the air.
- Test: `shot_robots.tscn`.

## Earlier on 2026-11-17 (late night): chaos stars and the Owner's response

- Chaos stars (GTA's wanted level, the Owner's way): heat from everything she breaks, one to five gold stars at
  the top right, the Owner remarks on each; they cool when she lies low and the police cannot see her.
- The response: police cars (one per star) with flashing lights and a siren drive at her through the traffic
  (cars pull over), stop across the lane, let out officers who point at her and order her about; road blocks
  of barriers from three stars, the fire brigade at four, a dark SWAT van at five. All breakable (more heat).
  When the stars are gone everyone drives off and goes home; a rewind sends everyone home at once.
- Test: `shot_police.tscn`.

## Earlier on 2026-11-17 (late night): a bigger city that lives

- The name is now **Cat As Trophe** (catastrophe spelled right); the cat is Trophe, the title gag is
  `TROPHE AS CAT` -> `CAT AS TROPHE`, the desktop shortcut is "Trophe As Cat".
- Far LOD: a building beyond 240 m is one merged mesh until it loses its first element.
- The city grew to 6 x 6 blocks: the Strip (malls, car parks with painted bays, fuel stations whose pumps go
  up in a chain), the Yards (warehouses, loading yards, container stacks), the Suburbs (houses with fences,
  drives and back gardens) and the outer Park. Four new building styles: warehouse, mall, fuel canopy, shop.
- People are painted porcelain figurines of real people (21 Quaternius figures, four glaze variants each, a
  cast per district) who wave, kick, sit, run and shatter. 80 more animals (Quaternius, CAT-PROOF): deer,
  stags, foxes, wolves, a petting farm, dogs that run at Trophe.
- Traffic: 110 cars on the right-hand lanes, crossings one at a time, braking and honking, and a car that is
  hit leaves the traffic as a car prop at its speed.
- Tests: `test_ring`, `shot_ring`, `shot_npc`, `shot_traffic`.

## Earlier on 2026-11-17 (late night): the edge of the Table and the Underneath

- The rim of the slab turns into the Owner's teal wireframe (terrain shader) and a quiet curtain of the
  Owner's code hangs over it (`TableEdge`): a glowing line on the horizon from the city, a wall of code in
  the band below the horizon from above.
- Falling off (`Underneath`): five calm seconds drifting away from the slab while the camera looks back at
  its cut side and its glowing underside, the Owner's "Please do not fall off the Table. ...Again.", then
  the drop back from the sky; skippable with any key or click.
- `tests/shot_edge.tscn` shows the rim, the fall, the drop back and a skipped fall.

## Earlier on 2026-11-17 (night): the world rewind

- Hold R (`Timeline`): debris flies back to where it was born and the elements come back newest first, so a
  collapse plays in reverse and the building stands as it stood; props un-break and fly back along their
  path, wrecks lose their soot, mannequins are whole again, the dominoes stand up again. TABLE CLEARED %
  goes down with it. 15 s window, a cool tape look with a warble. `tests/shot_rewind.tscn` blows up an
  apartment block (1,143 elements, all gone) and rewinds it to 1,143 standing and 0.000 % cleared.

## Earlier on 2026-11-17 (evening): the frame around play

- **Loading screen** (`LoadingScreen`) while main.tscn is read on a thread and the world is built over many
  frames; the boot splash has the screen's colour, so nothing flashes.
- **Title** (`TitleScreen`): TROPHE AS CAT glitches into CAT AS TROPHE over a slow flight round the city;
  Continue, New Table, Load, Settings, Quit.
- **The Owner** (`OwnerVoice`): a greeting, the domino warning, and one line per big moment.
- **Pause menu** (`PauseMenu`, Esc) with **settings** (`SettingsPanel`, `Settings`) and **saves** (`SaveGame`:
  autosave every two minutes, on quit and on closing the window, three slots; a save is put back into a
  fresh Table exactly, without the rubble).
- `tests/shot_boot.tscn` runs all of it, saves after real damage and compares the game loaded back.

## Earlier on 2026-11-17

- **TABLE CLEARED % and unlocks** (`game/flow/progress.gd`, `game/ui/mini_hud.gd`): destroyed / total man-made
  mass, milestones with the Owner's lines, a toast for the new tool, the sandbox switch.
- **People** (`game/npc/people.gd`): porcelain mannequins that walk, sit, stand at stalls, speak, panic and
  shatter (the head rolls away).
- **Composed places** (`game/world/props/prop_sets.gd`): markets, cafes, greens, yards, the fuel depot, gardens,
  picnics; 50 more prop kinds; fragile things on tables that are knocked away before they break.
- **Pee instead of vomit** (`game/player/tools/pee_tool.gd`): on the belt from the start, she stands bolt
  upright (`CatPlayer.hold_tall_stance`), plain pee nudges light props and soaks people, Acid Pee at 15 %.
  The Acid Spit tool is gone.
- **Moments:** the chain counter with ranks (NAUGHTY ... CAT-ASTROPHE ... TABLE FLIP), slow motion on Q, the
  meow that frightens.
- **The opening** (`game/world/props/domino_run.gd`): the Owner's dominoes in front of the landing spot, ending
  in fuel drums, a garbage truck and the cars at the curb. One paw swat: 44 tiles in about ten seconds, 12
  props broken at the end, a chain of about 68 (CAT-ASTROPHE).
- **Animals** (`game/npc/animals.gd`): pigeon flocks that go up, circle and land again; Shibas that watch,
  shake, roll over and play dead. All CAT-PROOF.
- **Ground by district** (`CityLayout.surface_mask()`): paving stones under Downtown and in the market
  courts, asphalt at the Works, paths with benches through the Park. From above the four districts now read
  as four different places.

- **Facades** (`BuildingGenerator` looks, `MaterialDB.VARIANTS`, `FacadeTextures`): six tower looks with crowns,
  entrance doors under a canopy and roof plant; apartment blocks in brick or coloured render over a stone
  ground floor with cornices, window ledges, shop fronts with awnings and balconies at the back; framed
  windows with curtains, blinds and lit rooms; pastel, brick and fieldstone houses with coloured doors,
  three roof colours and chimneys; painted parking decks with a parking sign. All of it breaks like the
  rest of the building. Screens: `tests/shot_facades.tscn`.

What is still weak (all known, none started):
- Through the tower glass one sees empty floors (columns, slabs, a few partitions). No interiors anywhere.
- The shop signs carry no lettering, and the windows of a building only come in four variants each.
- The Park has trees, paths, picnic spots, pigeons and dogs, but no pond.
- A pigeon in the air is the standing model tipped forward with two flat grey wings: fine at a distance,
  a card up close. The dogs do not walk (the model has no walk clip).
- No sound for the pee, the dogs or the dominoes (the tiles borrow the wood impact); see the ledger.
- The explosion smoke of several fuel blasts at once reads as brown lumps for a moment.
- The Owner speaks in text only; there is no voice-over. A saved game comes back without its rubble.
- The rewind leaves the ground's craters, and it cannot bring back a block that fell and broke up on the
  way down before its own moment comes (its pieces fly to where it broke, the elements then appear in
  place). It goes 15 s back.

## Destruction at city scale (2026-11-16/17, details in ARCHITECTURE section 7)

- Dormant buildings (one box collider until the player is within 80 m or something damages them), the reach
  rule (`DamageRouter.REACH` = 150 m), a shared logic budget, debris impacts that skip targets which cannot
  react, and the crush of a failing masonry storey also taking walls that came loose first.
- Destruction suite (`tests/test_destruction.tscn`, 21 checks, about 7 minutes): the last full run
  (2026-11-17, with the city, the progress and the chain hooks in) passed 21 of 21 on a machine that was not
  throttled (reference 16.3 ms). `c` passed by a hair: 1.998 ms average against the 2 ms budget, which is
  2.08 ms when scaled to the nominal reference. `f` passed again.
  Check `c` (the 2 ms logic budget) depends on how fast the machine is running at that moment; the test prints
  a machine reference next to it (17 ms when the laptop is not throttled).
- The first hit on a dormant tower wakes all its bodies in that frame (about 15 ms, once per tower). The box
  of a dormant building is its bounding box, so beyond 80 m the laser dot sits a little outside a pitched roof.
  A building with a failed storey never goes dormant again.

## Leftovers under `_spikes/` (ignored by Godot)

- `p2_environment`, `p2_tools`, `destruction`, `terrain`, `player`: merged copies; can be deleted.
- `p2_audio/game/audio/tools/`: `audiolib.py` (WAV analysis), `analyze_*.py`, `decode_to_wav.gd`; useful when the bank grows.
- `p2_destruction/`: an earlier, unfinished attempt at the two failing checks; do not copy from it.

## Next steps, in order (each one small, tested, then reported)

1. **A play test by the director** (feel, balance, sound mix), then fixes from it.
2. More giants (a glass atrium downtown) and upper floors / office floors inside.
3. Polish queue: engine sounds for near cars, traffic lights, turning wheels; sounds for the pee, the dogs and the dominoes; a walk for the dogs and real wings for the
   pigeons (needs models with those clips); paw-padlock icon in the CAT-PROOF answer; wind in the leaves and
   fuller far LODs; lamp posts that light up at dusk; wheels that come off wrecks; car alarms; tool icons in
   the HUD; waking a dormant tower over a few frames instead of one; records (best chain is already kept in
   `Progress.best_chain`, nothing shows it yet).
