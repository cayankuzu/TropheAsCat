class_name DamageHit
extends RefCounted
## One damage event. Every weapon, impact and power builds one of these and hands it to DamageRouter.

enum Kind {
	BLUNT,      ## Paw swat, thrown object, falling debris, hairball.
	EXPLOSION,  ## Fireball, gas, fuel: radial, falls off with distance.
	HEAT,       ## Laser dot, lava, fire: damage over time, ignites.
	ACID,       ## Dissolves material over time.
	CUT,        ## Clean slice along a plane (claw cut, laser line).
	SONIC,      ## Yowl / meow shockwave: shatters brittle things, pushes light ones.
	CRUSH,      ## Sustained weight (loaf, falling slab resting on something).
}

var position: Vector3 = Vector3.ZERO      ## World-space point of impact or blast centre.
var normal: Vector3 = Vector3.UP          ## Surface normal at the hit, if known.
var direction: Vector3 = Vector3.ZERO     ## Unit travel direction of the attack (zero for radial).
var energy: float = 0.0                   ## Joules spent against structural toughness.
var impulse: float = 0.0                  ## Newton-seconds pushed into dynamic bodies.
var radius: float = 0.0                   ## 0 for a point hit; blast radius in metres otherwise.
var kind: int = Kind.BLUNT
var source: Node = null                   ## Who caused it (player, projectile, debris), may be null.
var cause_id: int = 0                     ## Chain-reaction id: hits caused by the same root event share it.


static func point(pos: Vector3, dir: Vector3, energy_j: float, impulse_ns: float, kind_value: int = Kind.BLUNT, src: Node = null) -> DamageHit:
	var h := DamageHit.new()
	h.position = pos
	h.direction = dir.normalized() if dir.length_squared() > 0.0 else Vector3.ZERO
	h.energy = energy_j
	h.impulse = impulse_ns
	h.kind = kind_value
	h.source = src
	return h


static func blast(center: Vector3, radius_m: float, energy_j: float, impulse_ns: float, kind_value: int = Kind.EXPLOSION, src: Node = null) -> DamageHit:
	var h := DamageHit.new()
	h.position = center
	h.radius = radius_m
	h.energy = energy_j
	h.impulse = impulse_ns
	h.kind = kind_value
	h.source = src
	return h


## Copy of this hit scaled for a receiver at distance d from a blast centre (linear falloff).
func falloff_copy(distance: float) -> DamageHit:
	var h := DamageHit.new()
	var k := 1.0
	if radius > 0.0:
		k = clampf(1.0 - distance / radius, 0.0, 1.0)
	h.position = position
	h.normal = normal
	h.direction = direction
	h.energy = energy * k
	h.impulse = impulse * k
	h.radius = radius
	h.kind = kind
	h.source = source
	h.cause_id = cause_id
	return h
