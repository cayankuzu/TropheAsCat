class_name FractureLibrary
extends RefCounted
## Runtime Voronoi fracture patterns for convex elements, cached per (size, shape, material, variant).
##
## Cells are the convex intersection of the element planes and the bisector planes between seeds.
## The variant is the 3 x 3 bin of the hit point on the element's two largest axes; seeds cluster
## around that point, so pieces are smaller where the element was hit. Glass uses radial seed rings
## (shards), thin elements use seeds on their mid plane (cells span the full thickness), wood is
## computed in a space squashed along the grain (long splinters).
##
## Geometry runs on WorkerThreadPool (pure math). ArrayMesh / ConvexPolygonShape3D creation happens on
## the main thread in poll() under a microsecond budget, cell by cell.

const MAX_RUNNING_JOBS := 4
const LITE_CELLS := 6           ## at most this many pieces per pattern in the lite build

class Cell:
	var mesh: ArrayMesh
	var shape: ConvexPolygonShape3D
	var centroid: Vector3
	var volume: float
	var min_extent: float
	var max_extent: float


class Pattern:
	var key: String
	var material: StringName
	var cells: Array[Cell] = []
	var volume: float = 0.0


class Job:
	var key: String
	var size: Vector3
	var shape_type: int
	var material: StringName
	var variant: int
	var seed_value: int
	var cell_count: int
	var mode: int = 0          # 0 volume, 1 planar, 2 glass shards
	var thin_axis: int = 2
	var squash := Vector3.ONE  # Voronoi metric scale per axis (wood grain)
	var bias := Vector3.ZERO
	var planes: Array[Plane] = []
	var task_id: int = -1
	var priority: bool = false
	var results: Array[Dictionary] = []
	var finish_index: int = 0
	var pattern: Pattern = null

	func run() -> void:
		var shape_volume := DestructionDefs.shape_volume(size, shape_type)
		for attempt in 3:
			results.clear()
			var seeds := _make_seeds(seed_value + attempt * 7919)
			var total := 0.0
			for i in seeds.size():
				var cell := _cell(seeds, i)
				if cell.is_empty():
					continue
				total += cell["volume"]
				results.append(cell)
			if results.size() >= 2 and absf(total - shape_volume) <= shape_volume * 0.01:
				return
		# Fallback that cannot fail: slice along the longest axis.
		results.clear()
		var axis := _major_axes()[0]
		var n := clampi(cell_count >> 1, 2, 4)
		var h := size[axis] * 0.5
		for i in n:
			var pl := planes.duplicate()
			var nrm := Vector3.ZERO
			nrm[axis] = 1.0
			var lo := -h + size[axis] * float(i) / n
			var hi := -h + size[axis] * float(i + 1) / n
			if i < n - 1:
				pl.append(Plane(nrm, hi))
			if i > 0:
				pl.append(Plane(-nrm, -lo))
			var cell := ConvexBuilder.build(pl, planes.size())
			if not cell.is_empty():
				results.append(cell)

	func _major_axes() -> PackedInt32Array:
		var order := PackedInt32Array([0, 1, 2])
		for a in 3:
			for b in range(a + 1, 3):
				if size[order[b]] > size[order[a]]:
					var t := order[a]
					order[a] = order[b]
					order[b] = t
		return order

	func _inside(p: Vector3, margin: float) -> bool:
		for pl in planes:
			if pl.distance_to(p) > -margin:
				return false
		return true

	func _make_seeds(s: int) -> PackedVector3Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var half := size * 0.5
		var axes := _major_axes()
		var au := axes[0]
		var av := axes[1]
		var seeds := PackedVector3Array()
		var margin := minf(0.03, size[axes[2]] * 0.2)
		var planar := mode != 0
		var area := size[au] * size[av]
		var spacing := sqrt(area / cell_count) if planar else pow(DestructionDefs.shape_volume(size, shape_type) / cell_count, 1.0 / 3.0)
		var min_d := spacing * 0.42
		if mode == 2:
			# Glass: impact point plus rings of seeds around it.
			var centre := bias
			centre[thin_axis] = 0.0
			seeds.append(centre)
			var reach := sqrt(area) * 0.75
			var rings := 3 if cell_count >= 8 else 1   # the coarse variant: a centre shard and three around it
			var left := cell_count - 1
			var ring_counts := PackedInt32Array()
			var weight_sum := 0.0
			for r in rings:
				weight_sum += float(r + 1)
			for r in rings:
				ring_counts.append(maxi(3, int(round(left * float(r + 1) / weight_sum))))
			for r in rings:
				var radius := reach * pow(float(r + 1) / rings, 1.4)
				var cnt := ring_counts[r]
				var off := rng.randf() * TAU
				for k in cnt:
					var a := off + TAU * float(k) / cnt + rng.randf_range(-0.25, 0.25) / cnt * TAU
					var rr := radius * rng.randf_range(0.75, 1.15)
					var p := centre
					p[au] += cos(a) * rr
					p[av] += sin(a) * rr
					p[au] = clampf(p[au], -half[au] + 0.02, half[au] - 0.02)
					p[av] = clampf(p[av], -half[av] + 0.02, half[av] - 0.02)
					if _far_enough(seeds, p, spacing * 0.25):
						seeds.append(p)
			return seeds
		var biased := int(cell_count * 0.4)
		var tries := 0
		while seeds.size() < cell_count and tries < cell_count * 60:
			tries += 1
			var p := Vector3.ZERO
			var near := seeds.size() < biased
			if near:
				var r := spacing * 1.1
				p = bias + Vector3(rng.randf_range(-r, r), rng.randf_range(-r, r), rng.randf_range(-r, r))
			else:
				p = Vector3(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y), rng.randf_range(-half.z, half.z))
			if planar:
				p[thin_axis] = 0.0
			if not _inside(p, margin if not planar else 0.0):
				continue
			if planar:
				var lim_u := half[au] - margin
				var lim_v := half[av] - margin
				if absf(p[au]) > lim_u or absf(p[av]) > lim_v:
					continue
			if not _far_enough(seeds, p, min_d * (0.7 if near else 1.0)):
				continue
			seeds.append(p)
		return seeds

	func _far_enough(seeds: PackedVector3Array, p: Vector3, d: float) -> bool:
		var d2 := d * d
		for q in seeds:
			if ((q - p) * squash).length_squared() < d2:
				return false
		return true

	func _cell(seeds: PackedVector3Array, i: int) -> Dictionary:
		var pl := planes.duplicate()
		var si := seeds[i] * squash
		for j in seeds.size():
			if j == i:
				continue
			var sj := seeds[j] * squash
			var n := sj - si
			var nl := n.length()
			if nl < 1e-6:
				continue
			n /= nl
			var dd := n.dot((si + sj) * 0.5)
			# Map the bisector of the squashed space back: normal scales by squash, offset unchanged.
			var nn := n * squash
			var nlen := nn.length()
			pl.append(Plane(nn / nlen, dd / nlen))
		return ConvexBuilder.build(pl, planes.size())


var _patterns: Dictionary = {}   # key -> Pattern
var _jobs: Dictionary = {}       # key -> Job, queued or running
var _queue: Array[Job] = []      # not yet started
var _running: Array[Job] = []
var _finishing: Array[Job] = []
var stats_cells_built := 0


static func key_for(size: Vector3, shape_type: int, material: StringName, variant: int) -> String:
	return "%s|%s|%d" % [ElementLibrary.size_key(size, shape_type), material, variant]


static func cell_count_for(size: Vector3, shape_type: int, material: StringName) -> int:
	var v := DestructionDefs.shape_volume(size, shape_type)
	var thin := minf(size.x, minf(size.y, size.z))
	if MaterialDB.base_of(material) == &"glass":
		var area := size.x * size.y * size.z / maxf(thin, 0.001)
		return clampi(int(area * 3.0) + 7, 8, 18)
	if MaterialDB.base_of(material) in [&"steel", &"metal_rusty", &"sheet_metal"]:
		return 3
	if MaterialDB.base_of(material) == &"wood":
		return clampi(int(3.0 + v * 6.0), 4, 8)
	return clampi(int(roundf(4.0 + v * 3.5)), 4, 12)


## Variant used for elements crushed under load: a few big cells (pulverised rubble, cheap to spawn).
const COARSE_VARIANT := 9


## Variant = 3 x 3 bin of the local hit point on the element's two largest axes (4 = centre).
static func variant_for(size: Vector3, local_hit: Vector3) -> int:
	var a := _sorted_axes(size)
	var u := local_hit[a[0]] / maxf(size[a[0]] * 0.5, 0.001)
	var v := local_hit[a[1]] / maxf(size[a[1]] * 0.5, 0.001)
	return _bin(u) * 3 + _bin(v)


static func _bin(x: float) -> int:
	return 0 if x < -0.34 else (2 if x > 0.34 else 1)


static func _sorted_axes(size: Vector3) -> PackedInt32Array:
	var order := PackedInt32Array([0, 1, 2])
	for a in 3:
		for b in range(a + 1, 3):
			if size[order[b]] > size[order[a]]:
				var t := order[a]
				order[a] = order[b]
				order[b] = t
	return order


## Returns the cached pattern, or null while it is being computed (the request is queued).
func get_pattern(size: Vector3, shape_type: int, material: StringName, variant: int, urgent: bool = true) -> Pattern:
	var key := key_for(size, shape_type, material, variant)
	var p: Pattern = _patterns.get(key)
	if p != null:
		return p
	var job: Job = _jobs.get(key)
	if job == null:
		job = _make_job(key, size, shape_type, material, variant)
		if Game.lite:
			job.cell_count = mini(job.cell_count, LITE_CELLS)
		job.priority = urgent
		_jobs[key] = job
		if urgent:
			_queue.push_front(job)
		else:
			_queue.append(job)
	elif urgent and not job.priority and job.task_id < 0:
		job.priority = true
		_queue.erase(job)
		_queue.push_front(job)
	return null


func has_pattern(size: Vector3, shape_type: int, material: StringName, variant: int) -> bool:
	return _patterns.has(key_for(size, shape_type, material, variant))


## Queue low-priority generation of every variant of an element type.
func prewarm(size: Vector3, shape_type: int, material: StringName, all_variants: bool = false) -> void:
	if Game.lite:
		return   # single-threaded browser: worker tasks would run on the main thread, every frame
	if all_variants:
		for v in 9:
			get_pattern(size, shape_type, material, v, false)
	else:
		get_pattern(size, shape_type, material, 4, false)


func pending_count() -> int:
	return _jobs.size()


func pattern_count() -> int:
	return _patterns.size()


func _make_job(key: String, size: Vector3, shape_type: int, material: StringName, variant: int) -> Job:
	var job := Job.new()
	job.key = key
	job.size = size
	job.shape_type = shape_type
	job.material = material
	job.variant = variant
	job.seed_value = absi(key.hash())
	job.cell_count = cell_count_for(size, shape_type, material)
	if variant == COARSE_VARIANT:
		# Glass keeps four shards (a centre and three around it), thin steel snaps in two, everything else
		# breaks into three chunks.
		var coarse := 3
		if MaterialDB.base_of(material) == &"glass":
			coarse = 4
		elif MaterialDB.base_of(material) in [&"steel", &"metal_rusty", &"sheet_metal"]:
			coarse = 2
		job.cell_count = mini(job.cell_count, coarse)
		variant = 4
	job.planes = ConvexBuilder.shape_planes(size, shape_type)
	var axes := _sorted_axes(size)
	job.thin_axis = axes[2]
	if MaterialDB.base_of(material) == &"glass":
		job.mode = 2
	elif size[axes[2]] <= size[axes[1]] * 0.42:
		job.mode = 1
	if MaterialDB.base_of(material) == &"wood":
		job.squash = Vector3.ONE
		job.squash[axes[0]] = 0.35
	var bins := PackedFloat32Array([-0.62, 0.0, 0.62])
	var bias := Vector3.ZERO
	bias[axes[0]] = bins[floori(variant / 3.0)] * size[axes[0]] * 0.5
	bias[axes[1]] = bins[variant % 3] * size[axes[1]] * 0.5
	if shape_type == DestructionDefs.Shape.PRISM:
		bias.y = minf(bias.y, 0.0)
	job.bias = bias
	return job


## Advances worker jobs and turns finished geometry into engine resources within budget_usec.
func poll(budget_usec: int) -> void:
	var t0 := Time.get_ticks_usec()
	for i in range(_running.size() - 1, -1, -1):
		var job := _running[i]
		if WorkerThreadPool.is_task_completed(job.task_id):
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			_running.remove_at(i)
			job.pattern = Pattern.new()
			job.pattern.key = job.key
			job.pattern.material = job.material
			_finishing.append(job)
	while _running.size() < (1 if Game.lite else MAX_RUNNING_JOBS) and not _queue.is_empty():
		var job: Job = _queue.pop_front()
		job.task_id = WorkerThreadPool.add_task(job.run, false, "fracture pattern")
		_running.append(job)
	while not _finishing.is_empty() and Time.get_ticks_usec() - t0 < budget_usec:
		var job := _finishing[0]
		if job.finish_index < job.results.size():
			var cell_data: Dictionary = job.results[job.finish_index]
			job.finish_index += 1
			var cell := Cell.new()
			cell.mesh = ConvexBuilder.make_mesh(cell_data, ElementLibrary.surface_material(job.material), ElementLibrary.interior_material(job.material))
			var shape := ConvexPolygonShape3D.new()
			shape.points = cell_data["points"]
			cell.shape = shape
			cell.centroid = cell_data["centroid"]
			cell.volume = cell_data["volume"]
			var box: AABB = cell_data["aabb"]
			cell.min_extent = minf(box.size.x, minf(box.size.y, box.size.z))
			cell.max_extent = maxf(box.size.x, maxf(box.size.y, box.size.z))
			job.pattern.cells.append(cell)
			job.pattern.volume += cell.volume
			stats_cells_built += 1
		else:
			_finishing.pop_front()
			job.results.clear()
			_patterns[job.key] = job.pattern
			_jobs.erase(job.key)


## Waits for running worker tasks and drops queued work (shutdown).
func shutdown() -> void:
	for job in _running:
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_running.clear()
	_queue.clear()
	_finishing.clear()
	_jobs.clear()


## Blocks until every queued pattern is built. Tests and loading screens only.
func flush(timeout_ms: int = 30000) -> void:
	var t0 := Time.get_ticks_msec()
	while not _jobs.is_empty():
		poll(1000000)
		if not _running.is_empty() and _finishing.is_empty():
			OS.delay_usec(300)
		if Time.get_ticks_msec() - t0 > timeout_ms:
			push_error("FractureLibrary.flush timed out with %d jobs (%d queued, %d running, %d finishing)" % [_jobs.size(), _queue.size(), _running.size(), _finishing.size()])
			return
