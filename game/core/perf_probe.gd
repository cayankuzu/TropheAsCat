class_name PerfProbe
extends RefCounted
## Opt-in timing of named sections of the game (2026-11-17). tests/bench_perf.tscn switches it on to pin a
## hitch on what ran in that frame; in the game it is off and costs one static check per call.
##   var t := PerfProbe.begin()
##   ... work ...
##   PerfProbe.add(&"prop_break", t)

static var on := false
## Section -> microseconds and calls since the last take().
static var usec := {}
static var calls := {}


static func begin() -> int:
	return Time.get_ticks_usec() if on else 0


static func add(section: StringName, stamp: int) -> void:
	if stamp == 0:
		return
	usec[section] = int(usec.get(section, 0)) + Time.get_ticks_usec() - stamp
	calls[section] = int(calls.get(section, 0)) + 1


## What was timed since the last call: {section: [ms, calls]}; starts a new count.
static func take() -> Dictionary:
	var out := {}
	for k: StringName in usec:
		out[k] = [usec[k] / 1000.0, calls[k]]
	usec.clear()
	calls.clear()
	return out
