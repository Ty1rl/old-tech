extends SceneTree

const Flow = preload("res://scenes/prototype/flow.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
const Rooms = preload("res://scenes/prototype/rooms.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func run() -> void:
	for difficulty in [&"easy", &"hard"]:
		for room: Dictionary in Rooms.definitions(difficulty):
			var cover := Cover.new(room.cover)
			for wave: Dictionary in room.waves:
				if not bool(wave.get("boss", false)):
					continue
				var kind: StringName = wave.enemies[0]
				for player_z in [-15.0, 0.0, 12.0]:
					var player := Vector3(0, 0, player_z)
					for entrance in range(4):
						var flow := Flow.new()
						# Includes a preferred bottom entrance, exercising redirection.
						var slots := flow.layout(wave.formation, [kind], player, cover, entrance, [])
						var context := "%s %s player z=%.0f entrance=%d" % [difficulty, kind, player_z, entrance]
						expect(slots.size() == 1, context + " has a usable arrival")
						if slots.is_empty():
							continue
						var slot: Dictionary = slots[0]
						expect(slot.position.z + float(slot.radius) <= float(Tuning.ARENA_HALF_SIZE) * 0.5,
							context + " keeps the entire boss clear of the bottom entrance")
						expect(Flow.safe(slot.position, slot.radius, player, cover), context + " remains cover-safe")
						if player_z == 12.0:
							expect(slot.position.z < player.z, context + " favors above the player at normal room entry")
	# Ordinary reinforcements can still approach from the bottom.
	var escort_flow := Flow.new()
	var escorts := escort_flow.layout(&"mixed", [&"yellow"], Vector3.ZERO, Cover.new(), 2, [])
	expect(escorts.size() == 1 and escorts[0].position.z > 8.0, "Escort bottom arrival remains available")
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
