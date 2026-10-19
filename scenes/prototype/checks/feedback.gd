extends SceneTree

const Feedback = preload("res://scenes/prototype/combat_feedback.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var path: String = Feedback.SETTINGS_PATH
	var had_config := FileAccess.file_exists(path)
	var saved_config := FileAccess.get_file_as_bytes(path) if had_config else PackedByteArray()
	var feedback := Feedback.new()
	root.add_child(feedback)
	var weapons := preload("res://scenes/weapons/weapons.tscn").instantiate()
	root.add_child(weapons)
	var original_mute: bool = feedback.muted
	if feedback.muted:
		feedback.toggle_mute()
	var idle_silent := true
	for loop in feedback._loops.values():
		idle_silent = idle_silent and not loop.player.playing
	expect(idle_silent, "Creating feedback does not eagerly start permanent native audio playback")
	feedback.cue(&"hit", Vector3.ZERO)
	var queued_cue := false
	for voice in feedback._voices:
		queued_cue = queued_cue or (bool(voice.pending) and not voice.player.playing)
	expect(queued_cue, "Cue startup waits until the complete gameplay update has been coalesced")
	feedback.reset_state()
	await process_frame
	var cancelled_silent := true
	for voice in feedback._voices:
		cancelled_silent = cancelled_silent and not voice.player.playing and not bool(voice.pending)
	expect(cancelled_silent, "A same-update reset cancels queued native playback without starting or leaking it")
	expect(feedback.samples.size() == feedback.cue_library.cues.size(), "All inspector cues reference the baked stream bank")
	var total_bytes := 0
	var unique_streams := {}
	for kind in feedback.samples:
		var stream: AudioStream = feedback.samples[kind]
		var data: PackedByteArray = stream.get("data")
		if not unique_streams.has(stream.resource_path):
			unique_streams[stream.resource_path] = true
			total_bytes += data.size()
		if stream is AudioStreamMP3:
			expect(data.size() > 100 and stream.get_length() > .05, "%s has decodable supplied MP3 content" % kind)
			if kind in Feedback.LOOP_KINDS:
				expect(stream.loop and stream.loop_offset == 0, "%s has native compressed loop metadata" % kind)
			continue
		var sample: AudioStreamWAV = stream as AudioStreamWAV
		var peak := 0
		for offset in range(0, data.size(), 2):
			peak = maxi(peak, absi(data.decode_s16(offset)))
		expect(sample.mix_rate == 22050 and not sample.stereo and data.size() % 2 == 0, "%s has valid mono PCM data" % kind)
		expect(peak > 1000 and peak < 28000, "%s has audible signal and bounded headroom" % kind)
		if kind in Feedback.LOOP_KINDS:
			expect(absi(data.decode_s16(0) - data.decode_s16(data.size() - 2)) < 6500, "%s has a continuous periodic seam" % kind)
			expect(sample.loop_mode == AudioStreamWAV.LOOP_FORWARD and sample.loop_end <= data.size() / 2 and sample.loop_end > sample.loop_begin, "%s has bounded looping region" % kind)
		else:
			expect(data.decode_s16(0) == 0 and absi(data.decode_s16(data.size() - 2)) <= 2, "%s has silent transient edges" % kind)
	expect(total_bytes < 4000000 and unique_streams.size() >= 51 and unique_streams.size() <= 64, "Mixed supplied/fallback bank stays bounded and aliases share native resources")
	var duplicate := Feedback.new()
	root.add_child(duplicate)
	expect(duplicate.samples[&"hit"].data == feedback.samples[&"hit"].data, "Instances share the same baked content without synthesizing samples")
	duplicate.free()

	feedback.step(0.02, 0.0036, 0.18, false, 0.0, weapons, null)
	var first_pitch: float = feedback.clock_pitch
	expect(first_pitch < 1.0 and first_pitch > feedback.clock_pitch_target, "Slow entry eases clock speed down without an instantaneous pitch jump")
	for index in range(30):
		feedback.step(0.02, 0.0036, 0.18, false, 0.0, weapons, null)
	expect(feedback.clock_pitch < first_pitch and feedback.clock_pitch < 0.5, "Mechanical loop audibly winds down over several frames")
	expect(feedback.world_pitch < 0.55 and feedback.world_pitch > 0.35, "World sounds follow slow time")
	var slow_pitch: float = feedback.clock_pitch
	feedback.step(0.02, 0.02, 1.0, false, 0.0, weapons, null)
	expect(feedback.clock_pitch > slow_pitch and feedback.clock_pitch < 1.0, "Normal time spins the mechanical loop up gradually")
	for index in range(70):
		feedback.step(0.02, 0.02, 1.0, false, 0.0, weapons, null)
	expect(feedback.clock_pitch > 0.99, "Mechanical loop returns to normal speed")
	weapons.ring.flight_phase = "outbound"
	weapons.flash.charging = true
	weapons.flash.charge = 0.8
	weapons.bellows.active = true
	feedback.step(0.10, 0.10, 1.0, false, 0.0, weapons, null)
	await create_timer(0.15).timeout
	var stats: Dictionary = feedback.metrics()
	expect(stats.loops[&"ring_loop"].gain > 0.0 and stats.loops[&"charge_loop"].gain > 0.0 and stats.loops[&"cone_loop"].gain > 0.0, "Active tools have continuous sound layers")
	expect(feedback._loops[&"ring_loop"].player.playing and feedback._loops[&"charge_loop"].player.playing and feedback._loops[&"cone_loop"].player.playing, "Live tool layers start real native playback through deferred audio commands")
	expect(stats.loops[&"charge_loop"].pitch > 1.1, "Flash charge changes continuous oscillator playback speed")
	var cues_before: int = feedback.accepted_cues
	feedback.step(0.10, 0.0, 0.0, true, 0.0, weapons, null)
	var still_target: float = feedback.clock_pitch_target
	feedback.step(0.10, 0.0, 0.0, true, 4.0, weapons, null)
	expect(feedback.clock_pitch_target > still_target + 1.0 and feedback.clock_pitch < feedback.clock_pitch_target, "Wheel speed changes the mechanical target with an audible ramp")
	expect(feedback.metrics().loops[&"ring_loop"].target == 0.0 and feedback.metrics().loops[&"charge_loop"].target == 0.0 and feedback.metrics().loops[&"cone_loop"].target == 0.0, "Inspection suppresses attack loops even with historical flight state")
	feedback.cue(&"hit", Vector3.ZERO)
	expect(feedback.accepted_cues == cues_before and feedback.metrics().effects == 0, "Inspection step and rejected combat cues create no historical attack sounds or effects")
	feedback.cue(&"repair_step", Vector3.ZERO)
	var responsive_found := false
	for voice in feedback._voices:
		if bool(voice.responsive) and float(voice.remaining) > 0.0:
			responsive_found = is_equal_approx(voice.player.pitch_scale, 1.0)
	expect(responsive_found, "Repair feedback stays at normal pitch while inspecting")

	feedback.reset_state()
	feedback.step(0.1, 0.018, 0.18, false, 0.0, weapons, null)
	feedback.cue(&"hit", Vector3.ZERO)
	expect(feedback.metrics().effects == 1, "Real hit creates a modest mesh burst")
	var slow_hit_found := false
	for voice in feedback._voices:
		if float(voice.remaining) > 0.0 and not bool(voice.responsive):
			slow_hit_found = voice.player.pitch_scale < 0.9
	expect(slow_hit_found, "World hit playback has lower pitch while the world slows")
	var effect_age: float = feedback._effects[0].age
	feedback.step(0.1, 0.018, 0.18, false, 0.0, weapons, null)
	expect(is_equal_approx(float(feedback._effects[0].age) - effect_age, 0.018), "Effects advance in world seconds")
	feedback.step(0.1, 0.0, 0.0, true, 0.0, weapons, null)
	expect(is_equal_approx(feedback._effects[0].age, 0.018), "Inspection freezes remaining effect ages")
	feedback.clear_effects()
	expect(feedback.metrics().effects == 0, "Inspection/reset boundary explicitly clears effects")
	var occupied := 0
	for voice in feedback._voices:
		if float(voice.remaining) > 0.0:
			occupied += 1
	expect(occupied == 0, "Clearing inspection/reset effects also discards old transient voices")
	feedback.step(0.1, 0.0, 1.0, false, 0.0, weapons, null)
	for index in range(50):
		feedback.step(0.081, 0.0, 1.0, false, 0.0, weapons, null)
		for kind in Feedback.CUE_KINDS:
			feedback.cue(kind, Vector3(float(index % 5), 0.0, 0.0))
		expect(feedback.metrics().voices <= Feedback.MAX_VOICES, "Overlapping cues respect total voice cap")
	expect(feedback.metrics().effects == Feedback.MAX_EFFECTS, "Repeated cues cap effect storage at 24")
	expect(feedback.dropped_cues > 0, "Excess audio voices drop without waveform stealing")
	var count: int = feedback.accepted_cues
	for index in range(20):
		feedback.cue(&"hit", Vector3.ZERO)
	expect(feedback.accepted_cues == count, "Repeated frequent cues respect 80ms cooldown")
	feedback.step(0.1, 0.5, 1.0, false, 0.0, weapons, null)
	expect(feedback.metrics().effects == 0, "Mesh effects expire without persistent nodes")
	feedback.toggle_mute()
	expect(feedback.muted, "Mute toggles immediately")
	var silent := true
	for loop in feedback._loops.values():
		silent = silent and loop.player.volume_db == -80.0
	for voice in feedback._voices:
		silent = silent and voice.player.volume_db == -80.0
	expect(silent, "Mute immediately silences loops and voices without another tick")
	var restored := Feedback.new()
	root.add_child(restored)
	expect(restored.muted, "Mute persists through a new feedback instance")
	restored.reset_state()
	expect(restored.muted, "Gameplay reset retains mute preference")
	restored.free()
	feedback.reset_state()
	expect(feedback.accepted_cues == 0 and feedback.metrics().effects == 0, "Reset clears transient counters and effect state")
	# Start real loop playback, then remove the scene without a caller reset.
	# This exercises reverse child-exit cleanup rather than a test-only teardown.
	feedback.muted = false
	feedback.step(0.1, 0.018, 0.18, false, 0.0, weapons, null)
	await create_timer(0.05).timeout
	expect(feedback._loops[&"clock_loop"].player.playing, "Scene removal exercises active native clock playback")
	feedback.muted = original_mute
	feedback.free()
	weapons.free()
	if had_config:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(saved_config)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Let the Dummy audio server release streams after all players are freed.
	await create_timer(0.10).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
