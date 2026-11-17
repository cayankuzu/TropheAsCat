class_name DestructionDefs
extends RefCounted
## Enums and tuning constants shared by the destruction module (buildings, support, fracture, debris).

## TRIM .. FIXTURE (2026-11-17) are facade parts that carry nothing: cornices and ledges, awnings, balcony
## slabs, chimneys, rooftop plant and signs.
enum Kind { COLUMN, SLAB, WALL, PIER, SILL, LINTEL, CORE, PARTITION, GLASS, MULLION, PARAPET, RAILING, ROOF, GABLE, FLOOR, DOOR, RIDGE, SPANDREL,
	TRIM, AWNING, BALCONY, CHIMNEY, FIXTURE }

## How an element takes part in the support graph.
## VERTICAL elements rest on things below them (or on the ground), HORIZONTAL ones rest on verticals
## and may cantilever over a few lateral neighbours, ATTACHED ones (glass, sills, partitions...) only
## hang on structural hosts and never carry anything.
enum Role { VERTICAL, HORIZONTAL, ATTACHED }

enum Shape { BOX, PRISM }

## Edge types of the topology graph. RESTS_ON/CARRIES and ATTACHED_TO/HOSTS are the two directions of
## the same relation. RESTS_ON edges always point to a lower level, so support flow is acyclic.
enum Edge { RESTS_ON, CARRIES, LATERAL, ATTACHED_TO, HOSTS, TOUCH }

enum State { INTACT, PENDING, DESTROYED, DETACHED }

enum Style { TOWER, APARTMENT, PARKING, HOUSE, WAREHOUSE, MALL, CANOPY, SHOP }

const KIND_NAMES: PackedStringArray = ["column", "slab", "wall", "pier", "sill", "lintel", "core", "partition",
	"glass", "mullion", "parapet", "railing", "roof", "gable", "floor", "door", "ridge", "spandrel",
	"trim", "awning", "balcony", "chimney", "fixture"]
const STYLE_NAMES: PackedStringArray = ["tower", "apartment", "parking", "house", "warehouse", "mall", "canopy", "shop"]

const STOREY_H := 3.2
const CANT_INF := 15

## Element ids handed to DamageRouter: building_id * ID_STRIDE + element_index.
const ID_STRIDE := 1 << 16

## Dust colour per material (linear-ish albedo for the particle billboards).
const DUST_COLORS := {
	&"concrete": Color(0.66, 0.64, 0.61), &"concrete_light": Color(0.72, 0.7, 0.67),
	&"brick": Color(0.62, 0.48, 0.4), &"brick_old": Color(0.6, 0.5, 0.43),
	&"plaster": Color(0.86, 0.84, 0.8), &"glass": Color(0.8, 0.86, 0.9),
	&"steel": Color(0.45, 0.46, 0.48), &"metal_rusty": Color(0.5, 0.38, 0.3),
	&"wood": Color(0.55, 0.45, 0.34), &"roof": Color(0.58, 0.42, 0.36), &"tile": Color(0.8, 0.8, 0.78),
}


static func dust_color(material: StringName) -> Color:
	var c: Variant = DUST_COLORS.get(material)
	if c == null:
		c = DUST_COLORS.get(MaterialDB.base_of(material), Color(0.65, 0.63, 0.6))
	return c


static func shape_volume(size: Vector3, shape: int) -> float:
	var v := size.x * size.y * size.z
	return v * 0.5 if shape == Shape.PRISM else v


## Centre of mass of the element shape in its local frame.
static func shape_centroid(size: Vector3, shape: int) -> Vector3:
	if shape == Shape.PRISM:
		return Vector3(0.0, -size.y / 6.0, 0.0)
	return Vector3.ZERO
