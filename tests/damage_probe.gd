extends StaticBody3D
## Test target: records every DamageHit DamageRouter delivers to it.

var hits: Array[DamageHit] = []


func receive_damage(hit: DamageHit, _user_id: int) -> void:
	hits.append(hit)


func total_energy() -> float:
	var e := 0.0
	for h in hits:
		e += h.energy
	return e
