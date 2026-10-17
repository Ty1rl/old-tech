extends Node3D

class PlaybackShutdown extends Node:
	var players: Array[AudioStreamPlayer] = []

	func _exit_tree() -> void:
		# Children exit in reverse insertion order. This last child stops its
		# player siblings while they are still in-tree; a parent _exit_tree runs
		# after the players have exited and is too late for pending WAV playback.
		for player in players:
			player.stop()
			player.stream = null
		players.clear()

# Deliberately small synthesized placeholders. Arena owns every clock; this node
# has no process callback and never infers attacks from restored weapon state.
const SAMPLE_RATE := 22050
const MAX_VOICES := 8
const MAX_EFFECTS := 24
const CUE_COOLDOWN := 0.08
const SETTINGS_PATH := "user://combat-audio.cfg"
const LOOP_KINDS: Array[StringName] = [&"ring_loop", &"charge_loop", &"cone_loop", &"clock_loop"]
const CUE_KINDS: Array[StringName] = [&"ring_launch", &"ring_return", &"flash_fire", &"cone_pulse", &"hit", &"cable_cut", &"vent", &"core_break", &"repair_step"]
const RING := Color("60dbde")
const BEAM := Color("f0d77b")
const CONE := Color("ed9966")
const CLOCK := Color("ba9ce9")

var muted := false
var world_pitch := 1.0
var world_pitch_target := 1.0
var clock_pitch := 1.0
var clock_pitch_target := 1.0
var accepted_cues := 0
var dropped_cues := 0
var samples: Dictionary = {}
var _loops: Dictionary = {}
var _voices: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _cooldowns: Dictionary = {}
var _inspecting := false
var _audio_flush_pending := false
var _mesh := ImmediateMesh.new()
var _visual: MeshInstance3D


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		muted = bool(config.get_value("audio", "muted", false))
	for kind in CUE_KINDS + LOOP_KINDS:
		samples[kind] = _synthesize(kind, kind in LOOP_KINDS)
	for kind in LOOP_KINDS:
		var player := AudioStreamPlayer.new()
		player.stream = samples[kind]
		player.volume_db = -80.0
		add_child(player)
		_loops[kind] = {"player": player, "gain": 0.0, "target": 0.0, "pitch": 1.0}
	for index in range(MAX_VOICES - LOOP_KINDS.size()):
		var player := AudioStreamPlayer.new()
		player.volume_db = -80.0
		add_child(player)
		_voices.append({"player": player, "remaining": 0.0, "gain": 0.0, "strength": 1.0, "responsive": false, "pending": false})
	_visual = MeshInstance3D.new()
	_visual.mesh = _mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_visual.material_override = material
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	var shutdown := PlaybackShutdown.new()
	for loop in _loops.values():
		shutdown.players.append(loop.player)
	for voice in _voices:
		shutdown.players.append(voice.player)
	add_child(shutdown)


func _exit_tree() -> void:
	# Release the generated sample bank when leaving the arena, including on
	# Dummy audio runs where no output device advances the continuous loops.
	for loop in _loops.values():
		loop.player.stop()
		loop.player.stream = null
	for voice in _voices:
		voice.player.stop()
		voice.player.stream = null
	_loops.clear()
	_voices.clear()
	samples.clear()


func cue(kind: StringName, point: Vector3, strength: float = 1.0) -> void:
	if kind not in CUE_KINDS or not samples.has(kind):
		return
	# Repair feedback stays responsive during world slow/inspection. Other cues
	# must originate in actual gameplay; browsing itself cannot create them.
	if _inspecting and kind != &"repair_step":
		return
	if float(_cooldowns.get(kind, 0.0)) > 0.0:
		dropped_cues += 1
		return
	_cooldowns[kind] = CUE_COOLDOWN
	accepted_cues += 1
	strength = clampf(strength, 0.15, 1.5)
	if not _inspecting:
		_add_effect(kind, point, strength)
	if muted:
		return
	for voice in _voices:
		if float(voice.remaining) > 0.0 or voice.player.playing:
			continue
		var player: AudioStreamPlayer = voice.player
		player.stream = samples[kind]
		voice.responsive = kind == &"repair_step"
		voice.strength = strength
		voice.gain = 0.0
		voice.remaining = player.stream.get_length()
		player.pitch_scale = 1.0 if bool(voice.responsive) else world_pitch
		player.volume_db = -80.0
		voice.pending = true
		_queue_audio_flush()
		return
	# Drop rather than abruptly stealing a playing waveform.
	dropped_cues += 1


func step(real_delta: float, world_delta: float, world_scale: float, inspecting: bool, scrub_speed: float, weapons: Node3D, _equipment: RefCounted) -> void:
	var dt := maxf(0.0, real_delta)
	_inspecting = inspecting
	var scale_target := clampf(world_scale, 0.02, 1.0)
	world_pitch_target = pow(scale_target, 0.45)
	clock_pitch_target = clampf(0.24 + absf(scrub_speed) * 0.32, 0.24, 2.6) if inspecting else pow(scale_target, 0.65)
	# Continuous mechanical pitch slews over roughly a third of a second, so
	# entering slow winds down and resuming spins up instead of swapping beeps.
	world_pitch = lerpf(world_pitch, world_pitch_target, 1.0 - exp(-dt / 0.22))
	clock_pitch = lerpf(clock_pitch, clock_pitch_target, 1.0 - exp(-dt / 0.30))
	for kind in _cooldowns.keys():
		_cooldowns[kind] = maxf(0.0, float(_cooldowns[kind]) - dt)
	var ring_active := false
	var charge_active := false
	var cone_active := false
	var charge := 0.0
	if weapons != null and not inspecting:
		ring_active = String(weapons.get("ring_phase")) != "idle"
		charge_active = bool(weapons.get("beam_charging"))
		cone_active = bool(weapons.get("cone_active"))
		charge = clampf(float(weapons.get("beam_charge")), 0.0, 1.0)
	_set_loop(&"ring_loop", 0.8 if ring_active else 0.0, world_pitch, dt)
	_set_loop(&"charge_loop", 0.55 + charge * 0.45 if charge_active else 0.0, (0.72 + charge * 0.65) * world_pitch, dt)
	_set_loop(&"cone_loop", 0.65 if cone_active else 0.0, world_pitch, dt)
	# The clock runs during time manipulation and while spinning back up. It
	# becomes silent at rest rather than starting permanent ambient playback.
	var clock_gain := 0.45 if inspecting or scale_target < 0.99 else 0.32 * clampf((1.0 - clock_pitch) / 0.10, 0.0, 1.0)
	_set_loop(&"clock_loop", clock_gain, clock_pitch, dt)
	for voice in _voices:
		if float(voice.remaining) <= 0.0:
			continue
		var player: AudioStreamPlayer = voice.player
		var pitch := 1.0 if bool(voice.responsive) else world_pitch
		player.pitch_scale = pitch
		voice.remaining = maxf(0.0, float(voice.remaining) - dt * pitch)
		var target := minf(1.0, float(voice.remaining) / 0.025)
		if inspecting and not bool(voice.responsive):
			target = 0.0
		voice.gain = move_toward(float(voice.gain), target, dt * 60.0)
		player.volume_db = _volume(float(voice.gain) * float(voice.strength), -22.0)
		if float(voice.remaining) <= 0.0:
			voice.pending = false
			player.volume_db = -80.0
	if not inspecting:
		for index in range(_effects.size() - 1, -1, -1):
			_effects[index].age = float(_effects[index].age) + maxf(0.0, world_delta)
			if float(_effects[index].age) >= float(_effects[index].life):
				_effects.remove_at(index)
	_rebuild_effects()


func _set_loop(kind: StringName, target: float, pitch: float, dt: float) -> void:
	if not _loops.has(kind):
		return
	var loop: Dictionary = _loops[kind]
	loop.target = target
	loop.gain = lerpf(float(loop.gain), target, 1.0 - exp(-dt / 0.045))
	loop.pitch = pitch
	var player: AudioStreamPlayer = loop.player
	player.pitch_scale = clampf(pitch, 0.05, 4.0)
	player.volume_db = _volume(float(loop.gain), -30.0)
	if not muted and float(loop.gain) > 0.001 and not player.playing:
		_queue_audio_flush()


func _queue_audio_flush() -> void:
	if not _audio_flush_pending:
		_audio_flush_pending = true
		call_deferred("_flush_audio")


func _flush_audio() -> void:
	_audio_flush_pending = false
	# Coalesce all commands from one gameplay update before starting native
	# playback. Starting then stopping WAV playback before the audio thread's
	# first mix leaks native playback references in Godot 4.7's Dummy driver.
	var ancestor: Node = self
	while ancestor != null:
		if ancestor.is_queued_for_deletion():
			return
		ancestor = ancestor.get_parent()
	if muted or not is_inside_tree():
		return
	for loop in _loops.values():
		if float(loop.gain) > 0.001 and not loop.player.playing:
			loop.player.play()
	for voice in _voices:
		if bool(voice.pending) and float(voice.remaining) > 0.0:
			voice.pending = false
			voice.player.play()


func _volume(gain: float, base_db: float) -> float:
	return -80.0 if muted or gain <= 0.0001 else maxf(-80.0, base_db + linear_to_db(gain))


func toggle_mute() -> void:
	muted = not muted
	var config := ConfigFile.new()
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)
	# Immediate silence also covers a paused arena, where step may not run.
	if muted:
		for loop in _loops.values():
			loop.player.volume_db = -80.0
		for voice in _voices:
			voice.player.volume_db = -80.0


func clear_effects() -> void:
	_effects.clear()
	_mesh.clear_surfaces()
	# Historical snapshots carry no audio. Stop old transients at the explicit
	# inspection/reset boundary; continuous loops are smoothly faded by step.
	for voice in _voices:
		# A cancelled pending cue never reaches the audio server. Already mixed
		# one-shots finish silently instead of being stolen/restarted mid-wave.
		voice.pending = false
		voice.player.volume_db = -80.0
		voice.remaining = 0.0
		voice.gain = 0.0


func reset_state() -> void:
	clear_effects()
	for loop in _loops.values():
		loop.gain = 0.0
		loop.target = 0.0
		loop.player.stop()
	_cooldowns.clear()
	_inspecting = false
	accepted_cues = 0
	dropped_cues = 0


func metrics() -> Dictionary:
	var active := 0
	for voice in _voices:
		if float(voice.remaining) > 0.0:
			active += 1
	for loop in _loops.values():
		if float(loop.gain) > 0.001:
			active += 1
	var loop_metrics: Dictionary = {}
	for kind in _loops:
		var loop: Dictionary = _loops[kind]
		loop_metrics[kind] = {"gain": loop.gain, "target": loop.target, "pitch": loop.pitch}
	return {"voices": active, "voice_cap": MAX_VOICES, "effects": _effects.size(), "effect_cap": MAX_EFFECTS,
		"world_pitch": world_pitch, "world_pitch_target": world_pitch_target,
		"clock_pitch": clock_pitch, "clock_pitch_target": clock_pitch_target,
		"accepted_cues": accepted_cues, "dropped_cues": dropped_cues, "loops": loop_metrics}


func _synthesize(kind: StringName, looping: bool) -> AudioStreamWAV:
	var duration := 1.0 if looping else (0.42 if kind == &"core_break" else 0.16)
	var frames := int(float(SAMPLE_RATE) * duration)
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 719 + CUE_KINDS.find(kind) * 83 + LOOP_KINDS.find(kind) * 151
	var phase := 0.0
	var filtered_noise := 0.0
	for index in range(frames):
		var time := float(index) / SAMPLE_RATE
		var fraction := float(index) / maxf(1.0, frames - 1.0)
		filtered_noise = lerpf(filtered_noise, random.randf_range(-1.0, 1.0), 0.22)
		var frequency := 220.0
		var signal_value := 0.0
		match kind:
			&"ring_loop":
				signal_value = sin(TAU * 132.0 * time) * 0.38 + sin(TAU * 396.0 * time) * 0.15
				signal_value *= 0.7 + 0.3 * sin(TAU * 8.0 * time)
			&"charge_loop":
				signal_value = sin(TAU * 176.0 * time) * 0.30 + sin(TAU * 352.0 * time) * 0.18 + filtered_noise * 0.12
			&"cone_loop":
				signal_value = filtered_noise * 0.65 + sin(TAU * 66.0 * time) * 0.22
			&"clock_loop":
				var tick_age := fmod(time, 0.125)
				var tick := exp(-tick_age * 125.0)
				signal_value = (sin(TAU * 880.0 * time) * 0.4 + filtered_noise * 0.5) * tick
				signal_value += sin(TAU * 48.0 * time) * 0.10 + sin(TAU * 144.0 * time) * 0.035
			_:
				match kind:
					&"ring_launch": frequency = lerpf(320.0, 680.0, fraction)
					&"ring_return": frequency = lerpf(650.0, 240.0, fraction)
					&"flash_fire": frequency = lerpf(540.0, 95.0, fraction)
					&"cone_pulse": frequency = lerpf(150.0, 55.0, fraction)
					&"hit": frequency = lerpf(280.0, 80.0, fraction)
					&"cable_cut": frequency = lerpf(1250.0, 360.0, fraction)
					&"vent": frequency = lerpf(110.0, 65.0, fraction)
					&"core_break": frequency = lerpf(165.0, 36.0, fraction)
					&"repair_step": frequency = 660.0 if fraction < 0.45 else 880.0
				phase += TAU * frequency / SAMPLE_RATE
				var noise_weight := 0.12 if kind in [&"ring_launch", &"ring_return", &"repair_step"] else 0.65
				signal_value = sin(phase) * (0.6 - noise_weight * 0.35) + filtered_noise * noise_weight
				signal_value *= pow(1.0 - fraction, 1.2)
		# Fade sample edges as well as player gains to prevent loop/voice clicks.
		var envelope := minf(1.0, minf(time / 0.004, (duration - time - 1.0 / SAMPLE_RATE) / 0.012))
		var value := int(clampf(signal_value * maxf(0.0, envelope), -0.85, 0.85) * 32767.0)
		pcm.encode_s16(index * 2, value)
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = SAMPLE_RATE
	sample.stereo = false
	sample.data = pcm
	if looping:
		sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sample.loop_begin = 0
		sample.loop_end = frames
	return sample


func _add_effect(kind: StringName, point: Vector3, strength: float) -> void:
	if _effects.size() >= MAX_EFFECTS:
		_effects.pop_front()
	var color := BEAM
	if kind in [&"ring_launch", &"ring_return", &"cable_cut"]:
		color = RING
	elif kind in [&"cone_pulse", &"vent"]:
		color = CONE
	elif kind in [&"core_break", &"repair_step"]:
		color = CLOCK
	_effects.append({"kind": kind, "point": to_local(point) + Vector3.UP * 0.12,
		"age": 0.0, "life": 0.40 if kind == &"core_break" else 0.22,
		"color": color, "strength": strength})
	_rebuild_effects()


func _rebuild_effects() -> void:
	_mesh.clear_surfaces()
	if _effects.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for effect in _effects:
		var fraction := clampf(float(effect.age) / float(effect.life), 0.0, 1.0)
		var color: Color = effect.color
		color.a = (1.0 - fraction) * 0.8
		var center: Vector3 = effect.point
		var radius := (0.12 + fraction * 0.8) * float(effect.strength)
		if effect.kind in [&"ring_launch", &"ring_return", &"cone_pulse", &"vent", &"repair_step"]:
			for index in range(20):
				var a := TAU * float(index) / 20.0
				var b := TAU * float(index + 1) / 20.0
				var direction_a := Vector3(cos(a), 0, sin(a))
				var direction_b := Vector3(cos(b), 0, sin(b))
				var width := 0.035 * (1.0 - fraction)
				_triangle(center + direction_a * radius, center + direction_b * radius, center + direction_a * (radius + width), color)
				_triangle(center + direction_b * radius, center + direction_b * (radius + width), center + direction_a * (radius + width), color)
		else:
			for index in range(6):
				var angle := TAU * float(index) / 6.0 + 0.4
				var direction := Vector3(cos(angle), 0.3 + float(index % 3) * 0.25, sin(angle))
				var side := Vector3(-sin(angle), 0, cos(angle)) * 0.035 * (1.0 - fraction)
				var start := center + direction * radius * 0.3
				_triangle(start - side, start + side, center + direction * radius, color)
	_mesh.surface_end()


func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_add_vertex(b)
	_mesh.surface_add_vertex(c)
