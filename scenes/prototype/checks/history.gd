extends SceneTree

const History = preload("res://scenes/prototype/history.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)


func _make_realistic_snapshot(tick: int) -> Dictionary:
	var enemies: Array[Dictionary] = []
	for i in range(32):
		var angle: float = float(i) * TAU / 32.0 + float(tick) * 0.05
		var kinds: Array[StringName] = [&"target", &"swarmer", &"brute", &"skirmisher"]
		enemies.append({
			"rewind_id": i + 1,
			"kind": kinds[i % kinds.size()],
			"position": Vector3(cos(angle) * 12.0, 0.0, sin(angle) * 12.0),
			"facing": Vector3(-cos(angle), 0.0, -sin(angle)),
			"health": 180.0 - float(tick % 20) * 2.5,
			"contact_timer": fmod(float(i) * 0.13 + float(tick) * 0.05, 1.0),
			"knockback_velocity": Vector3(cos(angle) * 3.0, 0.0, sin(angle) * 3.0),
			"stagger_timer": maxf(0.0, 0.65 - float(tick % 10) * 0.05),
			"skirmisher_phase": i % 3,
			"skirmisher_timer": 0.45,
			"skirmisher_orbit_sign": 1.0 if (i % 2 == 0) else -1.0,
			"flash_timer": 0.08,
		})

	var ring_points: Array[Vector3] = []
	for p in range(120):
		var d: float = float(p) * 0.18
		ring_points.append(Vector3(-6.0 + d * 0.5, 0.0, -4.0 + sin(d) * 1.5))

	var pulses: Array[Dictionary] = []
	for b in range(8):
		pulses.append({
			"origin": Vector3(0.0, 0.3, 0.0),
			"position": Vector3(float(b) * 2.5, 0.3, -float(tick % 15) * 1.8),
			"direction": Vector2(0.0, -1.0),
			"damage": 30.0 + float(b) * 8.5,
			"charge_ratio": float(b) / 7.0,
			"remaining_range": 35.0 - float(b) * 3.0,
		})

	return {
		"tick": tick,
		"player": {
			"position": Vector3(float(tick) * 0.12, 0.55, -float(tick) * 0.08),
			"velocity": Vector3(4.2, 0.0, -2.1),
			"facing": Basis.IDENTITY.rotated(Vector3.UP, float(tick) * 0.04),
			"health": 100.0 - float(tick % 30),
			"world_scale": 0.18 if (tick % 5 == 0) else 1.0,
		},
		"equipment": {
			"remaining": {
				"ring": 32.0 - float(tick % 16),
				"beam": 48.0 - float(tick % 24),
				"cone": 45.0 - float(tick % 20) * 0.5,
				"clock": 24.0 - float(tick % 12) * 0.4,
			},
			"repairing": &"",
		},
		"weapons": {
			"selected_tool": (tick % 4) + 1,
			"ring_phase": "stroke",
			"ring_pos": ring_points[tick % ring_points.size()],
			"ring_points": ring_points,
			"ring_stroke_index": tick % ring_points.size(),
			"ring_hit_ids": [1, 4, 9, 15, 22, 31],
			"beam_cooldown": 0.15,
			"beam_pulses": pulses,
			"cone_burst_cooldown": 0.6,
		},
		"director": {
			"spawn_counter": 32 + tick,
			"encounter_active": true,
			"encounter_elapsed": float(tick) * 0.05,
			"encounter_wave": tick / 20,
			"enemies": enemies,
		},
	}


func run() -> void:
	var history := History.new()

	# 1. Initial & empty boundary behavior (no history / zero age)
	expect(not history.inspecting and is_equal_approx(history.selected_seconds_ago, 0.0),
		"New History starts not inspecting with selected_seconds_ago == 0")
	expect(is_equal_approx(history.available_seconds, 0.0) and history.snapshot_count == 0 and history.encoded_bytes == 0,
		"New History starts with 0 available_seconds, 0 snapshots, and 0 encoded_bytes")
	expect(history.seek(1.0).is_empty() and history.commit_inspection().is_empty() and history.cancel_inspection().is_empty(),
		"seek, commit_inspection, and cancel_inspection return empty Dictionary when not inspecting")

	var zero_present := {"marker": "only_present", "hp": 100.0}
	history.begin_inspection(zero_present)
	expect(history.inspecting and history.snapshot_count == 1 and is_equal_approx(history.available_seconds, 0.0),
		"begin_inspection with no prior history captures present with 0.0 available past")
	expect(history.seek(0.0).get("marker") == "only_present" and is_equal_approx(history.selected_seconds_ago, 0.0),
		"seek(0.0) with no prior history returns exact present")
	expect(history.seek(3.5).get("marker") == "only_present" and is_equal_approx(history.selected_seconds_ago, 0.0),
		"seek(>0) with no prior history clamps to 0.0 and returns present")
	expect(history.seek(-2.0).get("marker") == "only_present" and is_equal_approx(history.selected_seconds_ago, 0.0),
		"Negative seek clamps to 0.0 and returns present")
	var cancelled_zero: Dictionary = history.cancel_inspection()
	expect(cancelled_zero.get("marker") == "only_present" and not history.inspecting and history.snapshot_count == 0,
		"Cancelling zero-history inspection returns present and restores empty buffer")

	# 2. Sampling rate (20 Hz / 0.05s), sub-interval accumulation, and bounded stalled frames
	var capture_state := {"calls": 0}
	for sub in range(4):
		history.record(0.01, func() -> Dictionary:
			capture_state["calls"] = int(capture_state["calls"]) + 1
			return {"call": int(capture_state["calls"])}
		)
	expect(int(capture_state["calls"]) == 0 and history.snapshot_count == 0,
		"Sub-interval ticks (< 0.05s total) accumulate without prematurely capturing")
	history.record(0.01, func() -> Dictionary:
		capture_state["calls"] = int(capture_state["calls"]) + 1
		return {"call": int(capture_state["calls"])}
	)
	expect(int(capture_state["calls"]) == 1 and history.snapshot_count == 1 and is_equal_approx(history.available_seconds, 0.0),
		"Reaching 0.05s triggers exactly one snapshot capture")

	# Stalled frame (e.g. delta = 1.5s) captures at most once (no unbounded catch-up loop)
	history.record(1.5, func() -> Dictionary:
		capture_state["calls"] = int(capture_state["calls"]) + 1
		return {"call": int(capture_state["calls"]), "stalled": true}
	)
	expect(int(capture_state["calls"]) == 2 and history.snapshot_count == 2,
		"Stalled frame (1.5s) captures once without a catch-up loop")
	# Subsequent tiny frame (0.01s) does not immediately burst-capture from leftover stall time
	history.record(0.01, func() -> Dictionary:
		capture_state["calls"] = int(capture_state["calls"]) + 1
		return {"call": int(capture_state["calls"])}
	)
	expect(int(capture_state["calls"]) == 2 and history.snapshot_count == 2,
		"Frame after a stalled frame does not trigger catch-up captures")

	# Ignore non-positive, NaN, or infinite delta
	history.record(0.0, func() -> Dictionary:
		capture_state["calls"] = int(capture_state["calls"]) + 1
		return {}
	)
	history.record(-0.5, func() -> Dictionary:
		capture_state["calls"] = int(capture_state["calls"]) + 1
		return {}
	)
	history.record(NAN, func() -> Dictionary:
		capture_state["calls"] = int(capture_state["calls"]) + 1
		return {}
	)
	expect(int(capture_state["calls"]) == 2, "Zero, negative, and NaN deltas are ignored by record()")

	# 3. 5-second time cap with irregular dt (< 100 snapshots)
	history.clear()
	for sec in range(1, 8):
		history.record(1.0, func() -> Dictionary:
			return {"sec": sec}
		)
	expect(history.snapshot_count == 6 and is_equal_approx(history.available_seconds, 5.0),
		"5-second time cap evicts snapshots older than 5.0s even when count < 100")
	history.begin_inspection({"sec": 99})
	var oldest_irregular: Dictionary = history.seek(10.0)
	expect(int(oldest_irregular.get("sec", -1)) == 2,
		"Oldest retained snapshot after 7x1.0s steps + present is sec=2 (5.0s ago)")
	history.cancel_inspection()

	# 4. 100-snapshot count cap, 5.0s window at 20 Hz, and begin_inspection eviction
	history.clear()
	for i in range(100):
		var step_id: int = i
		history.record(0.05, func() -> Dictionary:
			return {"tick": step_id, "time": float(step_id) * 0.05}
		)
	expect(history.snapshot_count == 100 and is_equal_approx(history.available_seconds, 4.95),
		"100 samples at 0.05s fill max 100 snapshots and 4.95 available_seconds")

	# Recording while inspecting must be ignored
	history.begin_inspection({"tick": 1000, "present": true})
	expect(history.snapshot_count == 100,
		"begin_inspection on a 100-snapshot buffer evicts oldest to preserve max 100 cap")
	var ignored_state := {"calls": 0}
	history.record(0.05, func() -> Dictionary:
		ignored_state["calls"] = int(ignored_state["calls"]) + 1
		return {"tick": 9999}
	)
	expect(int(ignored_state["calls"]) == 0 and history.snapshot_count == 100,
		"record() during inspection is completely ignored")

	# 5. Scrubbing back and forward without destroying future
	var at_now: Dictionary = history.seek(0.0)
	expect(bool(at_now.get("present", false)) and int(at_now.get("tick", -1)) == 1000 and is_equal_approx(history.selected_seconds_ago, 0.0),
		"seek(0.0) always returns exact original present")
	var one_step_back: Dictionary = history.seek(0.05)
	expect(int(one_step_back.get("tick", -1)) == 98 and is_equal_approx(history.selected_seconds_ago, 0.05),
		"seek(0.05) selects the most recent recorded snapshot (tick 98)")
	var two_sec_back: Dictionary = history.seek(2.0)
	expect(int(two_sec_back.get("tick", -1)) == 59 and is_equal_approx(history.selected_seconds_ago, 2.0),
		"seek(2.0) selects snapshot 2.0s ago (tick 59)")
	var oldest_retained: Dictionary = history.seek(99.0)
	expect(int(oldest_retained.get("tick", -1)) == 1 and is_equal_approx(history.selected_seconds_ago, 4.9),
		"seek past available_seconds clamps to oldest retained snapshot (tick 1 at 4.9s ago)")
	# Scrub forward again after scrubbing to oldest
	var forward_half_sec: Dictionary = history.seek(0.5)
	expect(int(forward_half_sec.get("tick", -1)) == 89 and is_equal_approx(history.selected_seconds_ago, 0.5),
		"Scrubbing back to oldest and forward to 0.5s ago preserves future snapshots (tick 89)")
	var back_to_now: Dictionary = history.seek(0.0)
	expect(int(back_to_now.get("tick", -1)) == 1000 and is_equal_approx(history.selected_seconds_ago, 0.0),
		"Scrubbing back to 0.0 returns exact original present")

	# 6. Cancel retains old timeline (including pre-inspection 100 snapshots)
	history.seek(3.0)
	var cancelled: Dictionary = history.cancel_inspection()
	expect(not history.inspecting and is_equal_approx(history.selected_seconds_ago, 0.0),
		"cancel_inspection exits inspection and resets selected_seconds_ago to 0")
	expect(int(cancelled.get("tick", -1)) == 1000 and bool(cancelled.get("present", false)),
		"cancel_inspection returns exact original present even when seek was at 3.0s ago")
	expect(history.snapshot_count == 100 and is_equal_approx(history.available_seconds, 4.95),
		"cancel_inspection retains full original 100-snapshot / 4.95s timeline")

	# 7. Commit at NOW (0.0s ago) vs Commit in the past + branching timeline
	history.begin_inspection({"tick": 1000, "present": true})
	history.seek(1.5)
	history.seek(0.0)
	var committed_now: Dictionary = history.commit_inspection()
	expect(int(committed_now.get("tick", -1)) == 1000 and history.snapshot_count == 100 and is_equal_approx(history.available_seconds, 4.95),
		"commit_inspection at 0.0s ago (NOW) resumes from present without truncating history")

	# Now jump back 2.0s (to tick 59) and commit, then record a new branch
	history.begin_inspection({"tick": 1000, "present": true})
	var target_past: Dictionary = history.seek(2.0)
	expect(int(target_past.get("tick", -1)) == 59, "Pre-commit seek(2.0) selects tick 59")
	var committed_past: Dictionary = history.commit_inspection()
	expect(not history.inspecting and int(committed_past.get("tick", -1)) == 59,
		"commit_inspection returns selected past snapshot (tick 59)")
	expect(history.snapshot_count == 60 and is_equal_approx(history.available_seconds, 2.95),
		"commit_inspection truncates future snapshots (> tick 59) and rebases recorder time")

	# Record 4 new branched ticks (0.20s) after tick 59
	for b in range(1, 5):
		var branch_step: int = 2000 + b
		history.record(0.05, func() -> Dictionary:
			return {"tick": branch_step, "branched": true}
		)
	expect(history.snapshot_count == 64 and is_equal_approx(history.available_seconds, 3.15),
		"Recording after commit appends to rebased timeline")

	history.begin_inspection({"tick": 3000, "present": true})
	expect(int(history.seek(0.0).get("tick", -1)) == 3000, "New inspection seek(0.0) is new present (3000)")
	expect(int(history.seek(0.05).get("tick", -1)) == 2003, "0.05s ago is previous branched tick (2003)")
	expect(int(history.seek(0.20).get("tick", -1)) == 59, "0.20s ago is branch point (tick 59), replacing old future")
	expect(int(history.seek(0.25).get("tick", -1)) == 58, "0.25s ago is pre-branch tick 58")
	expect(int(history.seek(0.30).get("tick", -1)) == 57, "0.30s ago is pre-branch history (tick 57)")
	history.cancel_inspection()

	# 8. Mutation isolation (caller mutating input or returned dictionaries/arrays)
	history.clear()
	var source_dict := {
		"hp": 80.0,
		"nested": {"ammo": 10},
		"items": [Vector3(1, 2, 3), Vector3(4, 5, 6)],
	}
	history.record(0.05, func() -> Dictionary:
		return source_dict
	)
	# Mutate source_dict after record()
	source_dict["hp"] = 0.0
	source_dict["nested"]["ammo"] = 0
	source_dict["items"].clear()

	var present_dict := {
		"hp": 50.0,
		"nested": {"ammo": 5},
		"items": [Vector3(7, 8, 9)],
	}
	history.record(0.01, func() -> Dictionary: return source_dict)
	history.begin_inspection(present_dict)
	# Mutate present_dict after begin_inspection()
	present_dict["hp"] = -999.0
	present_dict["nested"]["ammo"] = -1

	var seek_past: Dictionary = history.seek(0.05)
	expect(is_equal_approx(float(seek_past["hp"]), 80.0) and int(seek_past["nested"]["ammo"]) == 10 and (seek_past["items"] as Array).size() == 2,
		"Mutating source Dictionary after record() does not affect stored snapshot")
	# Mutate returned seek_past dictionary and re-seek
	seek_past["hp"] = 1.0
	seek_past["nested"]["ammo"] = 999
	(seek_past["items"] as Array).clear()
	var seek_past_again: Dictionary = history.seek(0.05)
	expect(is_equal_approx(float(seek_past_again["hp"]), 80.0) and int(seek_past_again["nested"]["ammo"]) == 10 and (seek_past_again["items"] as Array).size() == 2,
		"Mutating Dictionary returned by seek() does not mutate stored snapshot")

	var seek_now: Dictionary = history.seek(0.0)
	expect(is_equal_approx(float(seek_now["hp"]), 50.0) and int(seek_now["nested"]["ammo"]) == 5,
		"Mutating present Dictionary after begin_inspection() does not affect stored present")
	seek_now["hp"] = -1.0
	var cancelled_copy: Dictionary = history.cancel_inspection()
	expect(is_equal_approx(float(cancelled_copy["hp"]), 50.0),
		"cancel_inspection() returns a fresh unmutated copy of original present")

	# 9. Invalid & oversize payload rejection with diagnostics (no silent truncation)
	var valid_count_before: int = history.snapshot_count
	var valid_bytes_before: int = history.encoded_bytes
	var rejected_before: int = history.rejected_count

	var dummy_node := Node.new()
	history.record(0.05, func() -> Dictionary:
		return {"bad_node": dummy_node}
	)
	dummy_node.free()
	expect(history.rejected_count == rejected_before + 1 and history.snapshot_count == valid_count_before and history.last_diagnostic.contains("Object"),
		"Snapshot containing a Node/Object reference is rejected with diagnostic")

	var dummy_ref := RefCounted.new()
	history.record(0.05, func() -> Dictionary:
		return {"nested": [dummy_ref]}
	)
	expect(history.rejected_count == rejected_before + 2 and history.snapshot_count == valid_count_before,
		"Snapshot containing a nested RefCounted reference is rejected")

	history.record(0.05, func() -> Dictionary:
		return {"bad_callable": func() -> void: pass}
	)
	expect(history.rejected_count == rejected_before + 3 and history.snapshot_count == valid_count_before,
		"Snapshot containing a Callable is rejected")

	var oversize_blob := PackedByteArray()
	oversize_blob.resize(History.MAX_PAYLOAD_BYTES + 1024)
	history.record(0.05, func() -> Dictionary:
		return {"oversize": oversize_blob}
	)
	expect(history.rejected_count == rejected_before + 4 and history.snapshot_count == valid_count_before and history.encoded_bytes == valid_bytes_before and history.last_diagnostic.contains("exceeds"),
		"Oversize payload (> 64 KiB) is safely rejected without silent truncation or corrupting buffer")

	history.begin_inspection({"oversize": oversize_blob})
	expect(not history.inspecting and history.rejected_count == rejected_before + 5,
		"begin_inspection rejects oversize present payload safely without entering broken inspection")

	# 10. clear() while inspecting
	history.begin_inspection({"hp": 42.0})
	history.seek(0.05)
	expect(history.inspecting and history.snapshot_count > 0, "Inspecting active before clear()")
	history.clear()
	expect(not history.inspecting and is_equal_approx(history.selected_seconds_ago, 0.0) and is_equal_approx(history.available_seconds, 0.0) and history.snapshot_count == 0 and history.encoded_bytes == 0,
		"clear() during inspection resets inspecting state, timestamps, count, and encoded_bytes")

	# 11. Realistic 32-enemy + ring path + projectile state full 100-snapshot memory & round-trip test
	for i in range(100):
		var t_idx: int = i
		history.record(0.05, func() -> Dictionary:
			return _make_realistic_snapshot(t_idx)
		)
	var single_realistic_bytes: int = var_to_bytes(_make_realistic_snapshot(100)).size()
	expect(single_realistic_bytes > 0 and single_realistic_bytes <= History.MAX_PAYLOAD_BYTES,
		"Realistic 32-enemy + ring + projectiles snapshot (%d B) fits well within 64 KiB cap" % single_realistic_bytes)
	expect(history.snapshot_count == 100 and is_equal_approx(history.available_seconds, 4.95),
		"100 realistic combat snapshots retained across 4.95s sampled window")
	expect(history.encoded_bytes > 0 and history.encoded_bytes <= History.MAX_SNAPSHOTS * History.MAX_PAYLOAD_BYTES,
		"Total encoded_bytes (%d B) for 100 realistic snapshots stays within 6.25 MiB cap" % history.encoded_bytes)

	history.begin_inspection(_make_realistic_snapshot(100))
	expect(history.snapshot_count == 100 and history.encoded_bytes <= History.MAX_SNAPSHOTS * History.MAX_PAYLOAD_BYTES,
		"begin_inspection with realistic 32-enemy present maintains 100-snapshot cap")
	var sample_mid: Dictionary = history.seek(2.5)
	var mid_enemies: Array = sample_mid["director"]["enemies"]
	var mid_ring_pts: Array = sample_mid["weapons"]["ring_points"]
	var mid_pulses: Array = sample_mid["weapons"]["beam_pulses"]
	expect(int(sample_mid["tick"]) == 49 and mid_enemies.size() == 32 and mid_ring_pts.size() == 120 and mid_pulses.size() == 8,
		"Realistic snapshot round-trips all 32 enemies, 120 ring points, and 8 active flash pulses")
	expect(int(mid_enemies[31]["rewind_id"]) == 32 and is_equal_approx(float(mid_enemies[0]["health"]), 180.0 - float(49 % 20) * 2.5),
		"Realistic enemy rewind_id and health round-trip accurately")
	var realistic_bytes: int = history.encoded_bytes
	var realistic_count: int = history.snapshot_count
	history.cancel_inspection()

	print(JSON.stringify({
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
		"snapshot_count": realistic_count,
		"single_snapshot_bytes": single_realistic_bytes,
		"encoded_bytes": realistic_bytes,
	}))
	quit(0 if failures.is_empty() else 1)
