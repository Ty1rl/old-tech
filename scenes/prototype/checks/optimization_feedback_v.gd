extends SceneTree
## Round V focused check & benchmark for jam-8: CombatFeedback update/rebuild cost and invariants.

const Feedback = preload("res://scenes/prototype/combat_feedback.gd")
const RING_KINDS: Array[StringName] = [&"ring_launch", &"ring_return", &"cone_pulse", &"vent", &"repair_step", &"player_hurt"]
const BURST_KINDS: Array[StringName] = [&"hit", &"cable_cut", &"core_break", &"flash_fire", &"flash_charged"]
const BURST_SEQUENCE: Array[StringName] = [&"ring_launch", &"cone_pulse", &"hit", &"cable_cut", &"vent", &"core_break", &"repair_step", &"player_hurt"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _expected_effect_vertices(effects: Array[Dictionary]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for effect in effects:
		var fraction := clampf(float(effect.age) / float(effect.life), 0.0, 1.0)
		var center: Vector3 = effect.point
		var radius := (0.12 + fraction * 0.8) * float(effect.strength)
		if effect.kind == &"player_hurt":
			radius = (0.72 + fraction * 0.6) * float(effect.strength)
		if effect.kind in RING_KINDS:
			var width := (0.09 if effect.kind == &"player_hurt" else 0.035) * (1.0 - fraction)
			for index in range(20):
				var a := TAU * float(index) / 20.0
				var b := TAU * float(index + 1) / 20.0
				var direction_a := Vector3(cos(a), 0.0, sin(a))
				var direction_b := Vector3(cos(b), 0.0, sin(b))
				out.append(center + direction_a * radius)
				out.append(center + direction_b * radius)
				out.append(center + direction_a * (radius + width))
				out.append(center + direction_b * radius)
				out.append(center + direction_b * (radius + width))
				out.append(center + direction_a * (radius + width))
		else:
			for index in range(6):
				var angle := TAU * float(index) / 6.0 + 0.4
				var direction := Vector3(cos(angle), 0.3 + float(index % 3) * 0.25, sin(angle))
				var side := Vector3(-sin(angle), 0.0, cos(angle)) * 0.035 * (1.0 - fraction)
				var start := center + direction * radius * 0.3
				out.append(start - side)
				out.append(start + side)
				out.append(center + direction * radius)
	return out


func _summarize_samples_us(samples_us: Array[float], total_steps: int) -> Dictionary:
	var sorted: Array[float] = samples_us.duplicate()
	sorted.sort()
	var sum_us := 0.0
	for v in sorted:
		sum_us += v
	var n := sorted.size()
	var p50: float = sorted[n / 2] if n > 0 else 0.0
	var p95: float = sorted[mini(n - 1, int(floor(float(n) * 0.95)))] if n > 0 else 0.0
	var max_v: float = sorted[n - 1] if n > 0 else 0.0
	return {
		"steps": total_steps,
		"total_ms": snappedf(sum_us / 1000.0, 0.001),
		"mean_us": snappedf(sum_us / float(max(1, total_steps)), 0.01),
		"median_us": snappedf(p50, 0.01),
		"p95_us": snappedf(p95, 0.01),
		"max_us": snappedf(max_v, 0.01),
	}


func run() -> void:
	var path: String = Feedback.SETTINGS_PATH
	var had_config := FileAccess.file_exists(path)
	var saved_config := FileAccess.get_file_as_bytes(path) if had_config else PackedByteArray()
	var manager := root.get_node("AudioManager")
	var state := root.get_node("GameState")
	var saved_prefs: Dictionary = state.preferences()
	for pair in [["sound", true], ["volume", 0.8], ["voice_volume", 0.9]]:
		state.set_setting(pair[0], pair[1])

	var feedback := Feedback.new()
	root.add_child(feedback)
	var weapons := preload("res://scenes/weapons/weapons.tscn").instantiate()
	root.add_child(weapons)
	var listener := AudioListener3D.new()
	root.add_child(listener)
	listener.make_current()
	var orig_mute: bool = feedback.muted
	feedback.muted = false

	# 1. Core caps, player counts, and palette mix invariants.
	expect(Feedback.MAX_VOICES == 15 and Feedback.MAX_EFFECTS == 24, "Voice and effect caps remain 15 and 24")
	expect(Feedback.MAX_MONSTER_VOICES == 2 and is_equal_approx(Feedback.MONSTER_INTERVAL, 0.45), "Monster cadence (0.45s) and 2-voice cap preserved")
	var player_count := 0
	for child in feedback.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			player_count += 1
	expect(player_count == 15 and feedback._loops.size() == 6 and feedback._voices.size() == 9, "Six loop players and nine 3D transient players preserved")
	for cue_entry: CombatAudioCue in feedback.cue_library.cues:
		expect(cue_entry.volume_db <= -6.0 and cue_entry.volume_db >= -26.0, "Cue gain budget preserved: " + String(cue_entry.id))

	# 2. Geometry & visual effect equivalence check.
	feedback.reset_state()
	expect(feedback._mesh.get_surface_count() == 0, "Reset leaves ImmediateMesh with zero surfaces")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	for i in range(6):
		var rk: StringName = RING_KINDS[i % RING_KINDS.size()]
		var bk: StringName = BURST_KINDS[i % BURST_KINDS.size()]
		feedback._cooldowns.clear()
		feedback.cue(rk, Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-8.0, 8.0)), rng.randf_range(0.4, 1.3))
		feedback._cooldowns.clear()
		feedback.cue(bk, Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-8.0, 8.0)), rng.randf_range(0.4, 1.3))
	feedback.step(0.016, 0.03, 0.5, false, 0.0, weapons, null)
	expect(feedback.metrics().effects == 12 and feedback._mesh.get_surface_count() == 1, "Stepping active effects builds single triangle surface")

	var expected_verts := _expected_effect_vertices(feedback._effects)
	var mesh_arrays := feedback._mesh.surface_get_arrays(0)
	var actual_verts: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
	var actual_colors: PackedColorArray = mesh_arrays[Mesh.ARRAY_COLOR]
	expect(actual_verts.size() == expected_verts.size() and actual_verts.size() == 6 * 120 + 6 * 18, "ImmediateMesh vertex count matches exact 120/ring + 18/burst formula (%d)" % actual_verts.size())
	expect(actual_colors.size() == actual_verts.size(), "Every emitted vertex carries its effect color")
	var max_vert_err := 0.0
	for idx in range(min(actual_verts.size(), expected_verts.size())):
		max_vert_err = maxf(max_vert_err, actual_verts[idx].distance_to(expected_verts[idx]))
	expect(max_vert_err < 0.0001, "Emitted ImmediateMesh vertices match reference trigonometry within 1e-4 (max_err=%.6f)" % max_vert_err)

	# 3. Monster crowd cadence, slow-time pitch, freeze boundary, and loop decay.
	feedback.reset_state()
	feedback.enemy_cue(&"blue", &"warning", Vector3.ZERO)
	for kind: StringName in [&"yellow", &"orange", &"swarmer", &"brute", &"ranged"]:
		feedback.enemy_cue(kind, &"warning", Vector3.ZERO)
	var active_monsters := 0
	for v in feedback._voices:
		if float(v.remaining) > 0.0 and String(v.cue).begins_with("enemy_"):
			active_monsters += 1
	expect(active_monsters == 1, "450ms monster cadence blocks simultaneous swarm barks")
	feedback._cooldowns.erase(&"monster_voice")
	feedback.enemy_cue(&"orange", &"death", Vector3.ZERO)
	feedback._cooldowns.erase(&"monster_voice")
	feedback.enemy_cue(&"yellow", &"attack", Vector3.ZERO)
	active_monsters = 0
	for v in feedback._voices:
		if float(v.remaining) > 0.0 and String(v.cue).begins_with("enemy_"):
			active_monsters += 1
	expect(active_monsters == 2, "Monster voice overlap capped at 2")

	weapons.ring.flight_phase = "outbound"
	weapons.flash.charging = true
	weapons.flash.charge = 0.75
	weapons.bellows.active = true
	feedback.step(0.05, 0.01, 0.2, false, 0.0, weapons, null)
	await create_timer(0.06).timeout
	expect(feedback._loops[&"ring_loop"].player.playing and feedback._loops[&"charge_loop"].player.playing and feedback._loops[&"cone_loop"].player.playing, "Active weapon loops start playback")
	expect(feedback.world_pitch < 1.0 and is_equal_approx(manager.music.pitch_scale if manager.music.playing else feedback.world_pitch, feedback.world_pitch), "Slow time lowers world pitch")

	# Freeze boundary preserves effect ages and accepts responsive cues while silencing world transients.
	feedback.cue(&"hit", Vector3.ZERO)
	var count_before_freeze: int = feedback.metrics().effects
	var age_before_freeze: float = float(feedback._effects[0].age) if count_before_freeze > 0 else -1.0
	feedback.step(0.05, 0.0, 0.0, true, 1.2, weapons, null)
	expect(feedback.metrics().effects == count_before_freeze and is_equal_approx(float(feedback._effects[0].age), age_before_freeze), "Frozen inspection preserves existing effect ages and geometry")
	var accepted_before_repair: int = feedback.accepted_cues
	feedback.cue(&"repair_step", Vector3.ZERO)
	feedback.step(0.05, 0.0, 0.0, true, 1.2, weapons, null)
	expect(feedback.accepted_cues == accepted_before_repair + 1 and feedback.metrics().effects == count_before_freeze and feedback._mesh.get_surface_count() == 1, "Responsive repair_step cue is accepted while frozen without mutating frozen world effects")

	weapons.ring.flight_phase = "idle"
	weapons.flash.charging = false
	weapons.flash.charge = 0.0
	weapons.bellows.active = false
	for _i in range(90):
		feedback.step(0.05, 0.05, 1.0, false, 0.0, weapons, null)
	expect(feedback.metrics().effects == 0 and feedback._mesh.get_surface_count() == 0, "Expired effects clear ImmediateMesh surfaces")
	expect(feedback._cooldowns.is_empty(), "Expired cooldown entries are pruned so idle steps do not iterate stale keys")

	# Verify standalone cue() without step() still flushes visual mesh on deferred audio flush.
	feedback.reset_state()
	feedback.cue(&"hit", Vector3.ZERO)
	expect(feedback._effects_dirty and feedback.metrics().effects == 1, "Cue marks effect mesh dirty for frame coalescing")
	await process_frame
	expect(not feedback._effects_dirty and feedback._mesh.get_surface_count() == 1, "Deferred flush builds ImmediateMesh when cue() is called without step()")

	# 4. Native mix ceiling check via AudioEffectRecord.
	feedback.reset_state()
	manager.set_music_context(&"encounter")
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, record)
	record.set_recording_active(true)
	for kind in [&"flash_charged", &"core_break", &"repair_full", &"room_open", &"player_hurt"]:
		feedback.cue(kind, Vector3.ZERO, 1.4)
	feedback.step(0.016, 0.016, 0.25, false, 0.0, weapons, null)
	await create_timer(0.25).timeout
	record.set_recording_active(false)
	var capture := record.get_recording()
	var peak := 0.0
	if capture != null:
		for offset in range(0, capture.data.size(), 2):
			peak = maxf(peak, absf(capture.data.decode_s16(offset) / 32768.0))
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	manager.set_music_context(&"intro")
	expect(capture != null and capture.data.size() > 500 and peak > 0.001 and peak <= 0.90, "Master bus mix remains audible and within limiter ceiling (peak=%.4f)" % peak)

	# 5. Deterministic CPU Benchmarks (4 workloads).
	# Warmup and populate realistic post-burst idle state (expired cooldowns, 0 active effects).
	feedback.reset_state()
	for kind in Feedback.CUE_KINDS:
		feedback.cue(kind, Vector3.ZERO)
	for _i in range(40):
		feedback.step(0.05, 0.05, 1.0, false, 0.0, weapons, null)
	expect(feedback.metrics().effects == 0, "Idle benchmark starts with zero active effects after burst expiry")

	var idle_samples: Array[float] = []
	var idle_steps := 2500
	for _i in range(idle_steps):
		var t0 := Time.get_ticks_usec()
		feedback.step(0.016, 0.016, 1.0, false, 0.0, weapons, null)
		idle_samples.append(float(Time.get_ticks_usec() - t0))

	# Workload 2: Active combat step with 24 active effects (12 rings + 12 bursts), active loops, and voices.
	feedback.reset_state()
	weapons.ring.flight_phase = "outbound"
	weapons.flash.charging = true
	weapons.flash.charge = 0.65
	weapons.bellows.active = true
	for i in range(12):
		feedback._cooldowns.clear()
		feedback.cue(RING_KINDS[i % RING_KINDS.size()], Vector3(float(i), 0.0, float(i % 4)), 1.0)
		feedback._cooldowns.clear()
		feedback.cue(BURST_KINDS[i % BURST_KINDS.size()], Vector3(-float(i), 0.0, float(i % 4)), 1.0)
	var active_samples: Array[float] = []
	var active_steps := 2000
	for i in range(active_steps):
		# Keep all 24 effects alive with deterministic varying ages so every step rebuilds 24 effects.
		for idx in range(feedback._effects.size()):
			feedback._effects[idx].age = fmod(float(i + idx) * 0.007, 0.18)
		var t0 := Time.get_ticks_usec()
		feedback.step(0.016, 0.002, 0.25, false, 0.0, weapons, null)
		active_samples.append(float(Time.get_ticks_usec() - t0))

	# Workload 3: Multi-cue burst + step (8 cues with visual effects fired in a single frame + step).
	feedback.reset_state()
	var burst_samples: Array[float] = []
	var burst_frames := 1000
	for i in range(burst_frames):
		feedback._cooldowns.clear()
		var t0 := Time.get_ticks_usec()
		for k_idx in range(BURST_SEQUENCE.size()):
			feedback.cue(BURST_SEQUENCE[k_idx], Vector3(float(k_idx), 0.0, float(i % 5)), 0.9)
		feedback.step(0.016, 0.016, 1.0, false, 0.0, weapons, null)
		burst_samples.append(float(Time.get_ticks_usec() - t0))

	# Workload 4: Frozen inspection scrub step with 24 frozen effects on screen.
	feedback.reset_state()
	for i in range(12):
		feedback._cooldowns.clear()
		feedback.cue(RING_KINDS[i % RING_KINDS.size()], Vector3(float(i), 0.0, 1.0), 1.0)
		feedback._cooldowns.clear()
		feedback.cue(BURST_KINDS[i % BURST_KINDS.size()], Vector3(-float(i), 0.0, 1.0), 1.0)
	feedback.step(0.016, 0.016, 1.0, false, 0.0, weapons, null)
	feedback.step(0.016, 0.0, 0.0, true, 1.5, weapons, null)
	expect(not feedback._effects_dirty and feedback._mesh.get_surface_count() == 1, "Frozen inspection retains built mesh surface without staying dirty")
	var frozen_samples: Array[float] = []
	var frozen_steps := 2500
	for i in range(frozen_steps):
		var scrub := 1.5 if (i % 2 == 0) else -1.5
		var t0 := Time.get_ticks_usec()
		feedback.step(0.016, 0.0, 0.0, true, scrub, weapons, null)
		frozen_samples.append(float(Time.get_ticks_usec() - t0))

	var bench := {
		"idle_step": _summarize_samples_us(idle_samples, idle_steps),
		"active_combat_step": _summarize_samples_us(active_samples, active_steps),
		"burst_8cues_and_step": _summarize_samples_us(burst_samples, burst_frames),
		"frozen_inspect_step": _summarize_samples_us(frozen_samples, frozen_steps),
	}
	expect(float(bench.idle_step.mean_us) < 40.0, "Idle step mean CPU time stays below 40us (got %.2fus)" % float(bench.idle_step.mean_us))
	expect(float(bench.active_combat_step.mean_us) < 550.0, "Active 24-effect step mean CPU time stays below 550us (got %.2fus)" % float(bench.active_combat_step.mean_us))
	expect(float(bench.burst_8cues_and_step.mean_us) < 1200.0, "8-cue burst + step mean CPU time stays below 1200us via coalesced rebuild (got %.2fus)" % float(bench.burst_8cues_and_step.mean_us))
	expect(float(bench.frozen_inspect_step.mean_us) < 80.0, "Frozen inspection step mean CPU time stays below 80us by skipping static mesh rebuilds (got %.2fus)" % float(bench.frozen_inspect_step.mean_us))
	print(JSON.stringify({"benchmark": bench}))

	# Teardown and restore settings.
	weapons.ring.flight_phase = "idle"
	weapons.flash.charging = false
	weapons.bellows.active = false
	feedback.reset_state()
	feedback.muted = orig_mute
	feedback.free()
	weapons.free()
	listener.free()
	if had_config:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(saved_config)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for key in ["sound", "volume", "voice_volume"]:
		state.set_setting(key, saved_prefs[key])
	await create_timer(0.1).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
