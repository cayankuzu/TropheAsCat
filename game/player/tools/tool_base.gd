class_name CatTool
extends Node
## Base class for everything the cat can wield (paw, powers, gadgets). Lives under the ToolBelt.
## The belt calls equip/unequip on selection and forwards primary (LMB / attack) and secondary
## (RMB / aim) presses and releases. process() runs every physics tick while equipped.

## Seconds between two answers of a CAT-PROOF thing to a continuous tool (see deliver()).
const PROTECTED_REPLY_GAP := 0.7

@export var tool_name := "Tool"
## Progress id of the tool (Progress.TOOL_*); empty for tools that are never locked.
@export var tool_id: StringName = &""
## When true, the cat rears up on its hind legs while this tool is held ready.
@export var wants_stand_pose := false

var cat: CatPlayer = null
var equipped := false

var _protected_reply_at := -10.0


func equip(owner_cat: CatPlayer) -> void:
	cat = owner_cat
	equipped = true


func unequip() -> void:
	equipped = false


func primary(_pressed: bool) -> void:
	pass


func secondary(_pressed: bool) -> void:
	pass


func process(_delta: float) -> void:
	pass


## True while the tool is mid-action (the belt will not switch away until it is done).
func is_busy() -> bool:
	return false


## What the crosshair points at: an intersect_ray result (position, normal, collider, rid), or {} when
## nothing solid lies within max_dist. The ray starts level with the cat, so nothing between the camera
## and the cat becomes the target.
func crosshair_hit(max_dist: float = 200.0, mask: int = Layers.SOLID) -> Dictionary:
	var ray := _crosshair_ray()
	return trace(ray[0], ray[0] + ray[1] * max_dist, mask)


## The point the crosshair is on, or a point max_dist ahead when it is on the sky.
func crosshair_point(max_dist: float = 200.0) -> Vector3:
	var ray := _crosshair_ray()
	var hit := trace(ray[0], ray[0] + ray[1] * max_dist)
	if not hit.is_empty():
		return hit["position"]
	return ray[0] + ray[1] * max_dist


## First solid thing on the segment (the cat and what it holds are skipped); {} when the way is clear.
func trace(from: Vector3, to: Vector3, mask: int = Layers.SOLID) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var ex: Array[RID] = [cat.get_rid()]
	if cat.grab != null and cat.grab.is_holding():
		ex.append(cat.grab.held.get_rid())
	q.exclude = ex
	return cat.get_world_3d().direct_space_state.intersect_ray(q)


## Where shots leave the cat: just in front of the mouth.
func muzzle() -> Vector3:
	return cat.get_mouth_position()


## Delivers a point hit to one collider. Continuous tools (beams, pools) go through here so that
## CAT-PROOF things answer at most once per PROTECTED_REPLY_GAP instead of on every tick.
func deliver(hit: DamageHit, collider: Object, rid: RID) -> void:
	var node := collider as Node
	if node != null and is_cat_proof(node):
		var now := Time.get_ticks_msec() * 0.001
		if now - _protected_reply_at < PROTECTED_REPLY_GAP:
			return
		_protected_reply_at = now
	DamageRouter.apply_hit(hit, collider, rid)


static func is_cat_proof(node: Node) -> bool:
	var n := node
	for i in 4:
		if n == null:
			return false
		if n.is_in_group(&"protected"):
			return true
		n = n.get_parent()
	return false


## [origin, unit direction] of the crosshair ray. Without a camera the cat's heading is used.
func _crosshair_ray() -> Array[Vector3]:
	var chest := cat.get_chest_position()
	var cam: Camera3D = cat.camera.get_camera() if cat.camera != null else null
	if cam == null:
		return [chest, cat.get_facing()]
	var dir := -cam.global_basis.z
	var from := cam.global_position
	from += dir * maxf(dir.dot(chest - from), 0.0)
	return [from, dir]
