extends Node3D
## Composition root of the Table: look, effects, terrain, the city with its nature and street dressing,
## the people and the animals, then Trophe with the HUD, the Owner and the pause menu. Keep this file as
## the single place that wires the world together.
##
## The world is built over several frames: every stage yields one frame, the buildings yield every 90 ms,
## so a loading screen stays alive (`stage_done` reports the share done, `world_ready` the end). Run on its
## own (tests, the editor) the scene starts play as soon as the world stands; the boot scene
## (game/boot.tscn) clears `auto_start`, shows the title and calls begin() itself.

signal stage_done(what: String, fraction: float)
signal world_ready

const WORLD_LOOK := preload("res://game/world/environment/world_look.tscn")
const CAT_SCENE := preload("res://game/player/cat.tscn")

## Trophe always enters the Table from the sky; the fall gives the terrain time to stream in under her.
const SPAWN := Vector3(0.0, 0.0, 14.0)

## The Owner's dominoes start a few steps in front of the landing spot and follow the avenue between
## the Park and Downtown; Trophe lands looking down the run.
const DOMINO_START := Vector3(0.0, 0.0, 23.0)
const DOMINO_HEADING := Vector3(0.0, 0.0, 1.0)
const DOMINO_COUNT := 44
const DOMINO_SWAY := 2.2

## Share of the curb slots that hold a parked car (before the district factor).
const CAR_FILL := 0.32
## Cars driving on the roads (Traffic); the domino run's stretch of road stays closed to them.
const TRAFFIC_CARS := 110
const TRAFFIC_CARS_LITE := 14

## Seconds of play between autosaves.
const AUTOSAVE_SECONDS := 120.0

## False when someone else starts play (the boot scene, after the title).
@export var auto_start := true

var look: WorldLook
var terrain: Node3D   ## WorldTerrain, or FlatTerrain in the lite build (see make_terrain)
var city: CityLayout
var dressing: StreetDressing
var dominoes: DominoRun
var people: People
var animals: Animals
var wildlife: Wildlife
var traffic: Traffic
var chaos: Chaos
var police: Police
var robots: CleanupRobots
var set_pieces: SetPieces
var driving: CatDriving
var game_hud: GameHud
var jobs: Jobs
var achievements: Achievements
var cat: CharacterBody3D
var hud: MiniHud
var owner_voice: OwnerVoice
var pause_menu: PauseMenu
var underneath: Underneath
## True once the world stands; `playing` once Trophe is in it.
var built := false
var playing := false
## Milliseconds each part of the world took to build, in order (the loading screen shows the stages).
var load_report: Array[String] = []

var _stage_usec := 0
var _build_usec := 0
var _autosave_left := AUTOSAVE_SECONDS


## The voxel ground where Voxel Tools exists and the build is not lite; else FlatTerrain (the browser demo:
## the extension has no build for the web).
static func make_terrain() -> Node3D:
	if ClassDB.class_exists(&"VoxelLodTerrain") and not Game.lite:
		return (load("res://game/terrain/world_terrain.gd") as GDScript).new() as Node3D
	return FlatTerrain.new()


func _ready() -> void:
	_build()


func _build() -> void:
	_build_usec = Time.get_ticks_usec()
	_stage_usec = _build_usec
	Progress.reset()
	Timeline.reset()
	# The big models (vehicle packs, trees, props) are read on worker threads while this thread builds
	# the terrain and the buildings; a later load() of the same file joins the read that is under way.
	for path in VehicleLibrary.model_paths() + WorldNature.model_paths() + StreetDressing.model_paths() + People.model_paths() + Animals.model_paths() + Wildlife.model_paths():
		ResourceLoader.load_threaded_request(path)
	look = WORLD_LOOK.instantiate() as WorldLook
	add_child(look)
	var fx := WorldFX.new()
	fx.name = "WorldFX"
	add_child(fx)
	await _stage("look and effects", 0.04)

	terrain = make_terrain()
	terrain.name = "Terrain"
	add_child(terrain)
	# Where the Table ends: the Owner's code over the rim and a grid far down in the void.
	var edge := TableEdge.new()
	edge.name = "TableEdge"
	add_child(edge)
	await _stage("terrain", 0.12)

	StructureManager.create_world(self)
	var structures := Game.structures as StructureManager

	# The city: 6 x 6 blocks, four districts around the crossing where Trophe lands and an outer ring of
	# malls, fuel stations, warehouses and suburbs. Every building is placed dormant; the structure
	# manager wakes what she comes near.
	city = CityLayout.new()
	await city.build_async(structures, get_tree(), func(f: float) -> void: stage_done.emit("buildings", lerpf(0.12, 0.7, f)))
	terrain.call(&"set_surface_mask", city.surface_mask(), true)
	await _stage(tr("%d buildings") % city.lots.size(), 0.7)
	var lines := CityLayout.road_lines()
	var reach := CityLayout.half_extent()
	var district_of := CityLayout.district_at

	# Protected nature: an avenue on every street and groves in the four blocks of the Park.
	var nature := WorldNature.new()
	nature.name = "Nature"
	add_child(nature)
	nature.add_street_trees(reach, 24.0, 7, lines)
	var park_seed := 31
	for block in CityLayout.block_centres(CityLayout.District.PARK):
		nature.add_park_block(block, park_seed)
		park_seed += 10
	var lawn_seed := 301
	for lawn in city.lawns:
		for sx: float in [-26.0, 26.0]:
			nature.add_grove(lawn + Vector3(sx, 0.0, 0.0), 9.0, 5, lawn_seed, false)
			lawn_seed += 1
	await _stage(tr("%d trees") % nature.tree_count(), 0.75)

	# Street furniture, loose things and parked cars on every street; all of it breaks.
	dressing = StreetDressing.new()
	dressing.name = "StreetDressing"
	add_child(dressing)
	dressing.dress_roads(lines, reach, 24.0, 11, district_of)
	await _stage(tr("%d street props") % dressing.prop_count(), 0.79)
	var props_before := dressing.prop_count()
	dressing.park_cars(reach, 23, lines, CAR_FILL, district_of)
	await _stage(tr("%d parked cars") % (dressing.prop_count() - props_before), 0.84)

	# Composed places in the open spots of the layout: flea markets, cafe terraces, village greens,
	# works yards with one fuel depot, gardens, picnic spots. Each returns where its people stand.
	var set_rng := RandomNumberGenerator.new()
	set_rng.seed = 97
	var standers: Array[Dictionary] = []
	var props_before_sets := dressing.prop_count()
	for court in city.courts:
		standers.append_array(PropSets.market(dressing, court, set_rng))
	for plaza in city.plazas:
		standers.append_array(PropSets.cafe(dressing, plaza, set_rng))
	for i in city.greens.size():
		standers.append_array(PropSets.green(dressing, city.greens[i], set_rng, i != 0))
	for i in city.yards.size():
		if i == 0:
			standers.append_array(PropSets.fuel_depot(dressing, city.yards[i], set_rng))
		else:
			standers.append_array(PropSets.yard(dressing, city.yards[i], set_rng))
	for g: Dictionary in city.gardens:
		PropSets.garden(dressing, g["pos"], g["yaw"], set_rng)
	for block in CityLayout.block_centres(CityLayout.District.PARK):
		standers.append_array(PropSets.picnic(dressing, block + Vector3(22.0, 0.0, 32.0), set_rng))
		PropSets.park_path(dressing, block)
	# The outer ring: car parks, forecourts, the fronts of the malls, loading yards, container stacks, and
	# the drives, fences and back gardens of the Suburbs.
	for r in city.car_parks:
		standers.append_array(PropSets.car_park(dressing, r, set_rng))
	for f: Dictionary in city.forecourts:
		standers.append_array(PropSets.forecourt(dressing, f, set_rng))
	for m in city.mall_fronts:
		standers.append_array(PropSets.mall_front(dressing, m, set_rng))
	for y in city.loading_yards:
		standers.append_array(PropSets.loading_yard(dressing, y, set_rng))
	for y in city.container_yards:
		PropSets.container_yard(dressing, y, set_rng)
	for dw: Dictionary in city.driveways:
		PropSets.driveway(dressing, dw, set_rng)
	for run: Dictionary in city.fences:
		PropSets.fence(dressing, run)
	for b: Dictionary in city.backyards:
		PropSets.backyard(dressing, b, set_rng)
	# Inside: the ground floors of the houses, the shops and the malls.
	var props_before_inside := dressing.prop_count()
	var inside_rng := RandomNumberGenerator.new()
	inside_rng.seed = 313
	for lot in city.lots if not Game.lite else []:   # no furniture inside in the lite build
		var data: BuildingData = structures.buildings[int(lot["bid"])].data
		var lot_xf := Transform3D(Basis(Vector3.UP, float(lot["yaw"])), lot["pos"])
		match int(lot["style"]):
			DestructionDefs.Style.HOUSE:
				PropSets.interior_house(dressing, data, lot_xf, inside_rng)
			DestructionDefs.Style.SHOP:
				PropSets.interior_shop(dressing, data, lot_xf, inside_rng)
			DestructionDefs.Style.MALL:
				PropSets.interior_mall(dressing, data, lot_xf, inside_rng)
			DestructionDefs.Style.TOWER:
				if not Game.lite:
					PropSets.interior_office(dressing, data, lot_xf, inside_rng)
			DestructionDefs.Style.APARTMENT:
				if not Game.lite:
					PropSets.interior_flats(dressing, data, lot_xf, inside_rng)
	await _stage(tr("%d props in markets, cafes, car parks, yards and gardens, %d inside") % [props_before_inside - props_before_sets, dressing.prop_count() - props_before_inside], 0.88)

	# The giants of the districts: the Ferris wheel of the fair, the tower crane of the building site, the
	# clock tower of the first green.
	set_pieces = SetPieces.new()
	set_pieces.name = "SetPieces"
	add_child(set_pieces)
	set_pieces.build(self, city)
	# The opening set piece: one swat at the first tile starts the first chain reaction of the game,
	# and it ends in fuel drums, a truck and whatever is parked beside it.
	dominoes = DominoRun.new()
	dominoes.name = "Dominoes"
	add_child(dominoes)
	var last_tile := dominoes.lay(DOMINO_START, DOMINO_HEADING, DOMINO_COUNT, DOMINO_SWAY)
	dominoes.add_finale(dressing, last_tile, DOMINO_HEADING)
	await _stage(tr("%d dominoes") % dominoes.tiles.size(), 0.9)

	# The little people: porcelain mannequins on every sidewalk, on some of the benches and at the
	# stalls and tables of the composed places.
	people = People.new()
	people.name = "People"
	add_child(people)
	people.populate(dressing)
	for spot in standers:
		people.add_stander(spot["pos"], spot["yaw"])
	await _stage(tr("%d people") % people.count(), 0.94)

	# Pigeons on the squares and in the Park (one flock right where she lands), dogs at the picnic
	# spots and on the greens. CAT-PROOF, all of them.
	animals = Animals.new()
	animals.name = "Animals"
	add_child(animals)
	animals.populate(city, SPAWN + Vector3(-4.5, 0.0, 5.5))
	# Traffic: cars on the move on every road, a puppet each until something hits it.
	traffic = Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	var closed: Array[Vector4] = [Vector4(1.0, 0.0, 0.0, CityLayout.BLOCK)]
	traffic.setup(dressing, lines, TRAFFIC_CARS_LITE if Game.lite else TRAFFIC_CARS, closed)
	# The wild and the farm animals: herds of deer in the outer Park and on the hills, foxes, wolves far
	# out, the petting farm's paddock and the dogs of the Suburbs. CAT-PROOF as well.
	wildlife = Wildlife.new()
	wildlife.name = "Wildlife"
	add_child(wildlife)
	wildlife.populate(city)
	PropSets.paddock(dressing, Wildlife.paddock_rect())
	Settings.apply_world(look)
	await _stage(tr("%d pigeons, %d dogs and %d other animals") % [animals.pigeon_count(), animals.dog_count(), wildlife.count()], 1.0)
	dressing.sealed = true   # props made from now on are not saved by name
	built = true
	world_ready.emit()
	if auto_start:
		begin()


## Play starts: Trophe drops from the sky at `at` (the landing spot by default, only x and z count),
## looking down the domino run, and the HUD, the Owner and the pause menu come in.
## Trophe starts with her paw and her pee; the other tools unlock as the Table is cleared (Progress). F1,
## the sandbox switch of the settings, or the command line argument "-- --sandbox", puts every tool on
## the belt.
func begin(at: Vector3 = SPAWN) -> void:
	if playing or not built:
		return
	playing = true
	var t0 := Time.get_ticks_usec()
	cat = CAT_SCENE.instantiate() as CharacterBody3D
	cat.name = "Trophe"
	add_child(cat)
	cat.call(&"drop_from_sky", at)
	var player := cat as CatPlayer
	player.face(DOMINO_HEADING)
	player.camera.get_camera().make_current()
	Settings.apply_cat(player)

	hud = MiniHud.new()
	hud.name = "MiniHud"
	add_child(hud)
	hud.setup(player)
	owner_voice = OwnerVoice.new()
	owner_voice.name = "Owner"
	add_child(owner_voice)
	owner_voice.setup(self)
	# The chaos stars and the Owner's response to them.
	chaos = Chaos.new()
	chaos.name = "Chaos"
	add_child(chaos)
	chaos.setup(self)
	police = Police.new()
	police.name = "Police"
	add_child(police)
	police.setup(self, chaos)
	robots = CleanupRobots.new()
	robots.name = "CleanupRobots"
	add_child(robots)
	robots.setup(self, chaos)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.setup(self)
	underneath = Underneath.new()
	underneath.name = "Underneath"
	add_child(underneath)
	underneath.setup(self, player)
	driving = CatDriving.new()
	driving.name = "Driving"
	add_child(driving)
	driving.setup(self, player)
	game_hud = GameHud.new()
	game_hud.name = "GameHud"
	add_child(game_hud)
	game_hud.setup(self)
	jobs = Jobs.new()
	jobs.name = "Jobs"
	add_child(jobs)
	jobs.setup(self, player)
	achievements = Achievements.new()
	achievements.name = "Achievements"
	add_child(achievements)
	achievements.setup(self)
	load_report.append("cat and HUD %d ms" % int((Time.get_ticks_usec() - t0) / 1000.0))


## Where a new game drops Trophe.
func spawn_point() -> Vector3:
	return SPAWN


## Writes the game into a slot (SaveGame.AUTOSAVE or 1 to 3) and says so on the HUD.
func save_game(slot: int) -> bool:
	if not playing:
		return false
	var ok := SaveGame.write(self, slot)
	if ok and hud != null:
		hud.flash("AUTOSAVED" if slot == SaveGame.AUTOSAVE else tr("SAVED  -  %s") % SaveGame.slot_name(slot))
	return ok


func _process(delta: float) -> void:
	if not playing:
		return
	_autosave_left -= delta / maxf(Engine.time_scale, 0.05)
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_SECONDS
		save_game(SaveGame.AUTOSAVE)


## Closing the window keeps the game.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and playing:
		SaveGame.write(self, SaveGame.AUTOSAVE)


## Q held: slow motion (the best collapses deserve a second look). Sound drops in pitch with it.
func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event.is_action_pressed(&"slow_motion"):
		Game.request_time_scale(&"slow_motion", 0.25)
		AudioServer.playback_speed_scale = 0.6
	elif event.is_action_released(&"slow_motion"):
		Game.clear_time_scale(&"slow_motion")
		AudioServer.playback_speed_scale = 1.0


## The world goes with this node: nothing may keep pointing into it (quitting to the title frees it).
func _exit_tree() -> void:
	Game.clear_time_scale(&"slow_motion")
	AudioServer.playback_speed_scale = 1.0
	Game.structures = null
	Game.debris = null
	Game.terrain = null
	Timeline.reset()


func _stage(what: String, fraction: float) -> void:
	var now := Time.get_ticks_usec()
	load_report.append("%s %d ms" % [what, int((now - _stage_usec) / 1000.0)])
	stage_done.emit(what, fraction)
	await get_tree().process_frame
	_stage_usec = Time.get_ticks_usec()


## Milliseconds from the first stage to the end of the build (the frames it yielded included).
func build_ms() -> int:
	return int((_stage_usec - _build_usec) / 1000.0)
