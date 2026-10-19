class_name CombatFeedback
extends Node3D
## One feedback owner; the arena supplies time and real semantic events. No replay
## snapshot, process clock, or runtime sample synthesis lives in this node.

class PlaybackShutdown extends Node:
	var players: Array[Node] = []
	func _exit_tree() -> void:
		# Last child exits first, while sibling native players are still in-tree.
		for player in players:
			player.stop()
			player.stream = null
		players.clear()

const DEFAULT_LIBRARY: CombatAudioLibrary = preload("res://audio/combat/palette.tres")
const MAX_VOICES := 16 # six loops, one music slot, nine bounded transient players
const MAX_EFFECTS := 24
const RESERVED_IMPORTANT := 2
const SETTINGS_PATH := "user://combat-audio.cfg"
const LOOP_KINDS: Array[StringName] = [&"ring_loop", &"charge_loop", &"cone_loop", &"clock_loop", &"scrub_older", &"scrub_newer"]
const CUE_KINDS: Array[StringName] = [&"ring_launch", &"ring_return", &"flash_fire", &"flash_charged", &"flash_ready", &"pierce_hit", &"cone_pulse", &"hit", &"cable_cut", &"vent", &"core_break", &"repair_step", &"repair_full", &"room_open", &"player_hurt", &"recovery_confirm", &"ui_click"]
const HOSTILE_CUES := {&"hostile_warning": &"hostile_warning", &"hostile_fire": &"hostile_fire", &"player_hurt": &"player_hurt"}
const RING := Color("60dbde")
const BEAM := Color("f0d77b")
const CONE := Color("ed9966")
const CLOCK := Color("ba9ce9")

@export var cue_library: CombatAudioLibrary = DEFAULT_LIBRARY
@export var music_enabled := false
var muted := false
var world_pitch := 1.0
var world_pitch_target := 1.0
var clock_pitch := 1.0
var clock_pitch_target := 1.0
var accepted_cues := 0
var dropped_cues := 0
var samples: Dictionary = {}
var _cues: Dictionary[StringName, CombatAudioCue] = {}
var _loops: Dictionary = {}
var _voices: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _cooldowns: Dictionary = {}
var _inspecting := false
var _audio_flush_pending := false
var _mesh := ImmediateMesh.new()
var _visual: MeshInstance3D
var _music: AudioStreamPlayer
var _music_gain := 0.0

func _ready() -> void:
	add_to_group(&"world_audio")
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		muted = bool(config.get_value("audio", "muted", false))
	for entry in cue_library.cues:
		_cues[entry.id] = entry
		samples[entry.id] = entry.stream
	for kind in LOOP_KINDS:
		var player := AudioStreamPlayer.new()
		player.name = String(kind).to_pascal_case()
		player.stream = _cues[kind].stream
		player.bus = &"Time" if _cues[kind].responsive else &"World"
		player.process_mode = Node.PROCESS_MODE_ALWAYS if _cues[kind].responsive else Node.PROCESS_MODE_PAUSABLE
		player.volume_db = -80.0
		add_child(player)
		_loops[kind] = {"player": player, "gain": 0.0, "target": 0.0, "pitch": 1.0}
	for index in range(MAX_VOICES - LOOP_KINDS.size() - 1):
		var player := AudioStreamPlayer3D.new()
		player.name = "Cue%d" % index
		player.volume_db = -80.0
		# Top-down camera is above the action: generous falloff, restrained pan.
		player.unit_size = 16.0
		player.max_distance = 64.0
		player.panning_strength = 0.45
		add_child(player)
		_voices.append({"player": player, "remaining": 0.0, "gain": 0.0, "strength": 1.0,
			"responsive": false, "pending": false, "priority": 0, "cue": &"", "base_pitch": 1.0, "volume_db": -12.0})
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.stream = cue_library.music
	_music.bus = &"Music"
	_music.process_mode = Node.PROCESS_MODE_PAUSABLE
	_music.volume_db = -80.0
	add_child(_music)
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
	for loop in _loops.values(): shutdown.players.append(loop.player)
	for voice in _voices: shutdown.players.append(voice.player)
	shutdown.players.append(_music)
	add_child(shutdown)

func _exit_tree() -> void:
	_loops.clear()
	_voices.clear()
	_cues.clear()
	samples.clear()

func cue(kind: StringName, point: Vector3, strength: float = 1.0) -> void:
	# The weapon's actual piercing-launch flag upgrades its queued quick shot
	# before native playback. No inferred charge threshold or second launch bang.
	var upgraded_launch := false
	if kind == &"flash_pierce":
		kind = &"flash_charged"
		for voice in _voices:
			if voice.pending and voice.cue == &"flash_fire" and not voice.player.playing:
				voice.pending = false
				voice.remaining = 0.0
				upgraded_launch = true
				break
	if kind == &"room_complete": kind = &"room_open"
	if kind == &"link_cut": kind = &"cable_cut"
	if kind == &"valve_b": kind = &"flash_ready"
	if not _cues.has(kind): return
	var entry: CombatAudioCue = _cues[kind]
	if entry.looping or (_inspecting and not entry.responsive): return
	if float(_cooldowns.get(kind, 0.0)) > 0.0:
		if not _inspecting and entry.effect in [&"cable_cut", &"vent", &"core_break"]:
			_add_effect(entry.effect, point, clampf(strength, 0.15, 1.5))
		dropped_cues += 1
		return
	_cooldowns[kind] = entry.cooldown
	accepted_cues += 1
	strength = clampf(strength, 0.15, 1.5)
	if not _inspecting and not upgraded_launch and not entry.effect.is_empty(): _add_effect(entry.effect, point, strength)
	if muted: return
	var free: Array[Dictionary] = []
	for voice in _voices:
		if float(voice.remaining) <= 0 and not voice.player.playing: free.append(voice)
	var chosen: Dictionary = {}
	if not free.is_empty() and (entry.priority >= 4 or free.size() > RESERVED_IMPORTANT):
		chosen = free[0]
	else:
		# Only cancel a lower-priority command that has NOT reached native
		# playback. Never chop/steal a playing waveform to fit another bark.
		for voice in _voices:
			if voice.pending and not voice.player.playing and int(voice.priority) < entry.priority:
				chosen = voice
				break
	if chosen.is_empty():
		dropped_cues += 1
		return
	var player: AudioStreamPlayer3D = chosen.player
	player.stream = entry.stream
	player.global_position = point
	player.bus = &"Responsive" if entry.responsive else &"World"
	player.process_mode = Node.PROCESS_MODE_ALWAYS if entry.responsive else Node.PROCESS_MODE_PAUSABLE
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if entry.responsive else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.panning_strength = 0.0 if entry.responsive else 0.45
	player.max_distance = 0.0 if entry.responsive else 64.0
	chosen.responsive = entry.responsive
	chosen.strength = strength
	chosen.gain = 1.0
	chosen.remaining = entry.stream.get_length() / entry.pitch
	chosen.base_pitch = entry.pitch
	chosen.volume_db = entry.volume_db
	chosen.priority = entry.priority
	chosen.cue = kind
	player.pitch_scale = entry.pitch * (1.0 if entry.responsive else world_pitch)
	player.volume_db = _volume(strength, entry.volume_db)
	chosen.pending = true
	_queue_audio_flush()

func enemy_cue(enemy_kind: StringName, event: StringName, point: Vector3, strength: float = 1.0) -> void:
	# Semantic events only, never inferred by polling a restored enemy's pose.
	cue(StringName("enemy_%s_%s" % [enemy_kind, event]), point, strength)

func set_music_playing(playing: bool) -> void:
	music_enabled = playing

func step(real_delta: float, world_delta: float, world_scale: float, inspecting: bool, scrub_speed: float, weapons: Node3D, _equipment: RefCounted) -> void:
	var dt := maxf(0.0, real_delta)
	var frozen := inspecting or world_scale <= 0.0
	if frozen and not _inspecting:
		# Discard pending and already heard WORLD transients at the boundary.
		# Responsive confirmations survive; unfreezing never replays a bark/hit.
		for voice in _voices:
			if not voice.responsive:
				voice.pending = false
				voice.remaining = 0.0
				voice.gain = 0.0
				voice.player.volume_db = -80.0
	_inspecting = frozen
	var scale_target := clampf(world_scale, 0.02, 1.0)
	world_pitch_target = pow(scale_target, 0.45)
	clock_pitch_target = clampf(0.45 + absf(scrub_speed) * 0.32, 0.45, 2.6) if frozen else pow(scale_target, 0.65)
	world_pitch = lerpf(world_pitch, world_pitch_target, 1.0 - exp(-dt / 0.22))
	clock_pitch = lerpf(clock_pitch, clock_pitch_target, 1.0 - exp(-dt / 0.30))
	for kind in _cooldowns: _cooldowns[kind] = maxf(0.0, float(_cooldowns[kind]) - dt)
	var ring_active := false
	var charge_active := false
	var cone_active := false
	var charge := 0.0
	if weapons != null and not frozen:
		ring_active = weapons.ring.flight_phase != "idle"
		charge_active = weapons.flash.charging
		cone_active = weapons.bellows.active
		charge = clampf(weapons.flash.charge, 0.0, 1.0)
	var bed_gain := 1.0
	for voice in _voices:
		if float(voice.remaining) > 0 and int(voice.priority) >= 4:
			bed_gain = 0.35
			break
	_set_loop(&"ring_loop", 0.8 * bed_gain if ring_active else 0.0, world_pitch, dt)
	_set_loop(&"charge_loop", (0.55 + charge * 0.45) * bed_gain if charge_active else 0.0, (0.72 + charge * 0.65) * world_pitch, dt)
	_set_loop(&"cone_loop", 0.65 * bed_gain if cone_active else 0.0, world_pitch, dt)
	var clock_gain := 0.45 if frozen or scale_target < 0.99 else 0.32 * clampf((1.0 - clock_pitch) / 0.10, 0.0, 1.0)
	var low_time := false
	if weapons != null and weapons.time_controller != null:
		low_time = weapons.time_controller.meter < weapons.time_controller.capacity * .2 and not frozen
	var clock_stream: AudioStream = _cues[&"time_low_loop"].stream if low_time and scale_target >= .99 else _cues[&"clock_loop"].stream
	var clock_player: AudioStreamPlayer = _loops[&"clock_loop"].player
	if clock_player.stream != clock_stream:
		clock_player.stop()
		clock_player.stream = clock_stream
	if low_time: clock_gain = maxf(clock_gain, .22)
	_set_loop(&"clock_loop", clock_gain, clock_pitch, dt)
	var scrub_gain := clampf(absf(scrub_speed) * 0.3, 0, 0.7) if frozen else 0.0
	_set_loop(&"scrub_older", scrub_gain if scrub_speed > 0 else 0.0, clock_pitch, dt)
	_set_loop(&"scrub_newer", scrub_gain if scrub_speed < 0 else 0.0, clock_pitch, dt)
	var music_target := bed_gain if music_enabled and not frozen and cue_library.music != null else 0.0
	_music_gain = lerpf(_music_gain, music_target, 1.0 - exp(-dt / 0.20))
	_music.pitch_scale = world_pitch # World policy applied ONCE here, never on a bus.
	_music.volume_db = _volume(_music_gain, cue_library.music_volume_db)
	if music_target > 0 and not _music.playing: _queue_audio_flush()
	elif music_target == 0 and _music_gain < 0.001 and _music.playing: _music.stop()
	for voice in _voices:
		if float(voice.remaining) <= 0: continue
		var player: AudioStreamPlayer3D = voice.player
		var rate := 1.0 if voice.responsive else world_pitch
		player.pitch_scale = float(voice.base_pitch) * rate
		voice.remaining = maxf(0.0, float(voice.remaining) - dt * rate)
		var target := minf(1.0, float(voice.remaining) / 0.025)
		voice.gain = move_toward(float(voice.gain), target, dt * 60.0)
		player.volume_db = _volume(float(voice.gain) * float(voice.strength), float(voice.volume_db))
		if float(voice.remaining) <= 0:
			voice.pending = false
			player.volume_db = -80.0
	if not frozen:
		for index in range(_effects.size() - 1, -1, -1):
			_effects[index].age = float(_effects[index].age) + maxf(0.0, world_delta)
			if float(_effects[index].age) >= float(_effects[index].life): _effects.remove_at(index)
	_rebuild_effects()

func _set_loop(kind: StringName, target: float, pitch: float, dt: float) -> void:
	var loop: Dictionary = _loops[kind]
	loop.target = target
	loop.gain = lerpf(float(loop.gain), target, 1.0 - exp(-dt / 0.045))
	loop.pitch = pitch
	var player: AudioStreamPlayer = loop.player
	player.pitch_scale = clampf(pitch, 0.05, 4.0)
	player.volume_db = _volume(float(loop.gain), _cues[kind].volume_db)
	if not muted and float(loop.gain) > 0.001 and not player.playing: _queue_audio_flush()

func _queue_audio_flush() -> void:
	if not _audio_flush_pending:
		_audio_flush_pending = true
		call_deferred("_flush_audio")

func _flush_audio() -> void:
	_audio_flush_pending = false
	var ancestor: Node = self
	while ancestor != null:
		if ancestor.is_queued_for_deletion(): return
		ancestor = ancestor.get_parent()
	if muted or not is_inside_tree(): return
	for loop in _loops.values():
		if float(loop.gain) > 0.001 and not loop.player.playing: loop.player.play()
	for voice in _voices:
		if voice.pending and float(voice.remaining) > 0:
			voice.pending = false
			voice.player.play()
	if music_enabled and _music.stream != null and _music_gain > 0.001 and not _music.playing: _music.play()

func _volume(gain: float, base_db: float) -> float:
	return -80.0 if muted or gain <= 0.0001 else maxf(-80.0, base_db + linear_to_db(gain))

func toggle_mute() -> void:
	muted = not muted
	var config := ConfigFile.new()
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)
	if muted:
		for loop in _loops.values(): loop.player.volume_db = -80.0
		for voice in _voices:
			voice.player.volume_db = -80.0
			voice.pending = false
			voice.remaining = 0.0
		_music.volume_db = -80.0

func clear_effects() -> void:
	_effects.clear()
	_mesh.clear_surfaces()
	for voice in _voices:
		voice.pending = false
		voice.player.volume_db = -80.0
		voice.remaining = 0.0
		voice.gain = 0.0

func reset_state() -> void:
	clear_effects()
	for loop in _loops.values():
		loop.gain = 0.0
		loop.target = 0.0
		loop.player.volume_db = -80.0
		loop.player.stop()
	_music.stop()
	_music_gain = 0.0
	_music.volume_db = -80.0
	_cooldowns.clear()
	_inspecting = false
	world_pitch = 1.0
	clock_pitch = 1.0
	accepted_cues = 0
	dropped_cues = 0

func metrics() -> Dictionary:
	var active := 0
	for voice in _voices:
		if float(voice.remaining) > 0: active += 1
	var loop_metrics := {}
	for kind in _loops:
		var loop: Dictionary = _loops[kind]
		if float(loop.gain) > 0.001: active += 1
		loop_metrics[kind] = {"gain": loop.gain, "target": loop.target, "pitch": loop.pitch}
	if _music_gain > 0.001: active += 1
	return {"voices": active, "voice_cap": MAX_VOICES, "effects": _effects.size(), "effect_cap": MAX_EFFECTS,
		"world_pitch": world_pitch, "world_pitch_target": world_pitch_target,
		"clock_pitch": clock_pitch, "clock_pitch_target": clock_pitch_target,
		"accepted_cues": accepted_cues, "dropped_cues": dropped_cues, "loops": loop_metrics}

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
	elif kind in HOSTILE_CUES:
		color = Color("ff6458")
	_effects.append({"kind": kind, "point": to_local(point) + Vector3.UP * 0.12,
		"age": 0.0, "life": 0.48 if kind == &"player_hurt" else (0.40 if kind == &"core_break" else 0.22),
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
		if effect.kind == &"player_hurt": radius = (.72 + fraction * .6) * float(effect.strength)
		if effect.kind in [&"ring_launch", &"ring_return", &"cone_pulse", &"vent", &"repair_step", &"player_hurt"]:
			for index in range(20):
				var a := TAU * float(index) / 20.0
				var b := TAU * float(index + 1) / 20.0
				var direction_a := Vector3(cos(a), 0, sin(a))
				var direction_b := Vector3(cos(b), 0, sin(b))
				var width := 0.035 * (1.0 - fraction)
				if effect.kind == &"player_hurt": width = .09 * (1.0 - fraction)
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
