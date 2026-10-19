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
const MAX_VOICES := 15 # six loops + nine transients; music belongs to AudioManager
const MAX_EFFECTS := 24
const RESERVED_IMPORTANT := 2
const MAX_MONSTER_VOICES := 2
const MONSTER_INTERVAL := 0.45
const SETTINGS_PATH := "user://combat-audio.cfg"
const LOOP_KINDS: Array[StringName] = [&"ring_loop", &"charge_loop", &"cone_loop", &"clock_loop", &"scrub_older", &"scrub_newer"]
const CUE_KINDS: Array[StringName] = [&"ring_launch", &"ring_return", &"flash_fire", &"flash_charged", &"flash_ready", &"pierce_hit", &"cone_pulse", &"hit", &"cable_cut", &"vent", &"core_break", &"repair_step", &"repair_full", &"room_open", &"player_hurt", &"recovery_confirm", &"ui_click"]
const HOSTILE_CUES := {&"hostile_warning": &"hostile_warning", &"hostile_fire": &"hostile_fire", &"player_hurt": &"player_hurt"}
const RING_EFFECT_KINDS: Array[StringName] = [&"ring_launch", &"ring_return", &"cone_pulse", &"vent", &"repair_step", &"player_hurt"]
const RING := Color("60dbde")
const BEAM := Color("f0d77b")
const CONE := Color("ed9966")
const CLOCK := Color("ba9ce9")
const HURT := Color("ff6458")

## Geometry is computed once per feedback owner and released with its scene.
var _ring_dirs: PackedVector3Array = PackedVector3Array()
var _burst_dirs: PackedVector3Array = PackedVector3Array()
var _burst_sides: PackedVector3Array = PackedVector3Array()

@export var cue_library: CombatAudioLibrary = DEFAULT_LIBRARY
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
var _effects_dirty := false
var _mesh_has_surface := false
var _audio_manager: Node
var _mesh := ImmediateMesh.new()
var _visual: MeshInstance3D

func _ensure_geometry_tables() -> void:
	if not _ring_dirs.is_empty():
		return
	_ring_dirs.resize(21)
	for index in range(21):
		var angle := TAU * float(index) / 20.0
		_ring_dirs[index] = Vector3(cos(angle), 0.0, sin(angle))
	_burst_dirs.resize(6)
	_burst_sides.resize(6)
	for index in range(6):
		var angle := TAU * float(index) / 6.0 + 0.4
		_burst_dirs[index] = Vector3(cos(angle), 0.3 + float(index % 3) * 0.25, sin(angle))
		_burst_sides[index] = Vector3(-sin(angle), 0.0, cos(angle)) * 0.035

func _ready() -> void:
	_ensure_geometry_tables()
	_audio_manager = get_node_or_null("/root/AudioManager")
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
		_loops[kind] = {"player": player, "gain": 0.0, "target": 0.0, "pitch": 1.0, "stopped": true}
	for index in range(MAX_VOICES - LOOP_KINDS.size()):
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
	# A mixed swarm shares one cadence and two slots, rather than barking per type.
	var kind := StringName("enemy_%s_%s" % [enemy_kind, event])
	if not _cues.has(kind) or _inspecting or muted: return
	var active := 0
	for voice in _voices:
		if float(voice.remaining) > 0 and String(voice.cue).begins_with("enemy_"):
			active += 1
	if float(_cooldowns.get(&"monster_voice", 0.0)) > 0 or active >= MAX_MONSTER_VOICES:
		dropped_cues += 1
		return
	var before := accepted_cues
	cue(kind, point, strength)
	if accepted_cues > before: _cooldowns[&"monster_voice"] = MONSTER_INTERVAL


func set_music_playing(playing: bool) -> void:
	# Legacy arena hook. Explicit campaign boss/victory contexts take precedence.
	var manager := _audio_manager if _audio_manager != null else get_node_or_null("/root/AudioManager")
	if manager == null:
		return
	if playing and manager.music_context in [&"intro", &"menu", &"encounter"]:
		manager.set_music_context(&"encounter")
	elif not playing and manager.music_context in [&"encounter", &"boss"]:
		manager.set_music_context(&"intro")

func step(real_delta: float, world_delta: float, world_scale: float, inspecting: bool, scrub_speed: float, weapons: Node3D, _equipment: RefCounted) -> void:
	var dt := maxf(0.0, real_delta)
	var frozen := inspecting or world_scale <= 0.0
	var scale_target := clampf(world_scale, 0.02, 1.0)
	_step_pitches_and_cooldowns(dt, frozen, scale_target, scrub_speed)
	_step_loops(dt, frozen, scale_target, scrub_speed, weapons)
	_step_voices(dt)
	_step_effects(world_delta, frozen)


func _step_pitches_and_cooldowns(dt: float, frozen: bool, scale_target: float, scrub_speed: float) -> void:
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
	world_pitch_target = pow(scale_target, 0.45)
	clock_pitch_target = clampf(0.45 + absf(scrub_speed) * 0.32, 0.45, 2.6) if frozen else pow(scale_target, 0.65)
	world_pitch = lerpf(world_pitch, world_pitch_target, 1.0 - exp(-dt / 0.22))
	clock_pitch = lerpf(clock_pitch, clock_pitch_target, 1.0 - exp(-dt / 0.30))
	if not _cooldowns.is_empty():
		var expired: Array[StringName] = []
		for kind: StringName in _cooldowns:
			var remaining_cooldown := float(_cooldowns[kind]) - dt
			if remaining_cooldown <= 0.0:
				expired.append(kind)
			else:
				_cooldowns[kind] = remaining_cooldown
		for kind in expired:
			_cooldowns.erase(kind)


func _step_loops(dt: float, frozen: bool, scale_target: float, scrub_speed: float, weapons: Node3D) -> void:
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
		if float(voice.remaining) > 0.0 and int(voice.priority) >= 4:
			bed_gain = 0.35
			break
	_set_loop(&"ring_loop", 0.8 * bed_gain if ring_active else 0.0, world_pitch, dt)
	_set_loop(&"charge_loop", (0.55 + charge * 0.45) * bed_gain if charge_active else 0.0, (0.72 + charge * 0.65) * world_pitch, dt)
	_set_loop(&"cone_loop", 0.65 * bed_gain if cone_active else 0.0, world_pitch, dt)
	var clock_gain := 0.45 if frozen or scale_target < 0.99 else 0.32 * clampf((1.0 - clock_pitch) / 0.10, 0.0, 1.0)
	var low_time := false
	if weapons != null and weapons.time_controller != null:
		low_time = weapons.time_controller.meter < weapons.time_controller.capacity * 0.2 and not frozen
	var clock_stream: AudioStream = _cues[&"time_low_loop"].stream if low_time and scale_target >= 0.99 else _cues[&"clock_loop"].stream
	var clock_player: AudioStreamPlayer = _loops[&"clock_loop"].player
	if clock_player.stream != clock_stream:
		clock_player.stop()
		clock_player.stream = clock_stream
	if low_time:
		clock_gain = maxf(clock_gain, 0.22)
	_set_loop(&"clock_loop", clock_gain, clock_pitch, dt)
	var scrub_gain := clampf(absf(scrub_speed) * 0.3, 0.0, 0.7) if frozen else 0.0
	_set_loop(&"scrub_older", scrub_gain if scrub_speed > 0.0 else 0.0, clock_pitch, dt)
	_set_loop(&"scrub_newer", scrub_gain if scrub_speed < 0.0 else 0.0, clock_pitch, dt)
	# Send the smoothed world policy once; music has no second pitch/bus clock.
	var manager := _audio_manager if _audio_manager != null else get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.set_world_audio_state(world_pitch, frozen, bed_gain, muted)


func _step_voices(dt: float) -> void:
	for voice in _voices:
		var remaining := float(voice.remaining)
		if remaining <= 0.0:
			continue
		var player: AudioStreamPlayer3D = voice.player
		var rate := 1.0 if voice.responsive else world_pitch
		var next_pitch := float(voice.base_pitch) * rate
		if absf(player.pitch_scale - next_pitch) > 0.001:
			player.pitch_scale = next_pitch
		remaining = maxf(0.0, remaining - dt * rate)
		voice.remaining = remaining
		var target := minf(1.0, remaining / 0.025)
		var next_gain := move_toward(float(voice.gain), target, dt * 60.0)
		voice.gain = next_gain
		var next_db := _volume(next_gain * float(voice.strength), float(voice.volume_db))
		if absf(player.volume_db - next_db) > 0.02:
			player.volume_db = next_db
		if remaining <= 0.0:
			voice.pending = false
			player.volume_db = -80.0
			if player.playing:
				player.stop()


func _step_effects(world_delta: float, frozen: bool) -> void:
	if not frozen and not _effects.is_empty():
		var world_elapsed := maxf(0.0, world_delta)
		for index in range(_effects.size() - 1, -1, -1):
			var next_age := float(_effects[index].age) + world_elapsed
			_effects[index].age = next_age
			if next_age >= float(_effects[index].life):
				_effects.remove_at(index)
				_effects_dirty = true
			elif world_elapsed > 0.0:
				_effects_dirty = true
	if _effects_dirty:
		_rebuild_effects()


func _set_loop(kind: StringName, target: float, pitch: float, dt: float) -> void:
	var loop: Dictionary = _loops[kind]
	loop.target = target
	loop.pitch = pitch
	var previous_gain := float(loop.gain)
	if target <= 0.0005 and previous_gain == 0.0 and bool(loop.get("stopped", false)):
		return
	var next_gain := lerpf(previous_gain, target, 1.0 - exp(-dt / 0.045))
	if target <= 0.0005 and next_gain <= 0.0005:
		next_gain = 0.0
	loop.gain = next_gain
	var player: AudioStreamPlayer = loop.player
	var next_pitch := clampf(pitch, 0.05, 4.0)
	if absf(player.pitch_scale - next_pitch) > 0.001:
		player.pitch_scale = next_pitch
	var next_db := _volume(next_gain, _cues[kind].volume_db)
	if absf(player.volume_db - next_db) > 0.02:
		player.volume_db = next_db
	if next_gain <= 0.0001 and target <= 0.0005:
		if player.playing:
			player.stop()
		player.volume_db = -80.0
		loop.stopped = true
	else:
		loop.stopped = false
		if not muted and next_gain > 0.001 and not player.playing:
			_queue_audio_flush()

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
	if not is_inside_tree(): return
	if _effects_dirty:
		_rebuild_effects()
	if muted: return
	for loop in _loops.values():
		if float(loop.gain) > 0.001 and not loop.player.playing:
			loop.stopped = false
			loop.player.play()
	for voice in _voices:
		if voice.pending and float(voice.remaining) > 0:
			voice.pending = false
			voice.player.play()

func _volume(gain: float, base_db: float) -> float:
	return -80.0 if muted or gain <= 0.0001 else maxf(-80.0, base_db + linear_to_db(gain))

func toggle_mute() -> void:
	muted = not muted
	var config := ConfigFile.new()
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)
	var manager := _audio_manager if _audio_manager != null else get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.set_world_audio_state(world_pitch, _inspecting, 1.0, muted)
	if muted:
		for loop in _loops.values(): loop.player.volume_db = -80.0
		for voice in _voices:
			voice.player.volume_db = -80.0
			voice.pending = false
			voice.remaining = 0.0

func clear_effects() -> void:
	_effects.clear()
	_effects_dirty = false
	if _mesh_has_surface:
		_mesh.clear_surfaces()
		_mesh_has_surface = false
	for voice in _voices:
		voice.pending = false
		voice.player.volume_db = -80.0
		voice.remaining = 0.0
		voice.gain = 0.0

func reset_state() -> void:
	clear_effects()
	# Restart/quit is a native teardown boundary, not just an inaudible tail.
	# Release compressed transients before AudioManager's mixer drain expires.
	for voice in _voices:
		voice.player.stop()
		voice.player.stream = null
	for loop in _loops.values():
		loop.gain = 0.0
		loop.target = 0.0
		loop.stopped = true
		loop.player.volume_db = -80.0
		loop.player.stop()
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
		color = HURT
	var is_hurt := kind == &"player_hurt"
	_effects.append({
		"kind": kind,
		"point": to_local(point) + Vector3.UP * 0.12,
		"age": 0.0,
		"life": 0.48 if is_hurt else (0.40 if kind == &"core_break" else 0.22),
		"color": color,
		"strength": strength,
		"is_ring": kind in RING_EFFECT_KINDS,
		"is_hurt": is_hurt,
	})
	_effects_dirty = true
	_queue_audio_flush()


func _rebuild_effects() -> void:
	_effects_dirty = false
	if _effects.is_empty():
		if _mesh_has_surface:
			_mesh.clear_surfaces()
			_mesh_has_surface = false
		return
	_ensure_geometry_tables()
	if _mesh_has_surface:
		_mesh.clear_surfaces()
	_mesh_has_surface = true
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for effect in _effects:
		var fraction := clampf(float(effect.age) / float(effect.life), 0.0, 1.0)
		var fade := 1.0 - fraction
		var color: Color = effect.color
		color.a = fade * 0.8
		_mesh.surface_set_color(color)
		var center: Vector3 = effect.point
		var strength := float(effect.strength)
		var is_hurt := bool(effect.get("is_hurt", effect.kind == &"player_hurt"))
		var radius := ((0.72 + fraction * 0.6) if is_hurt else (0.12 + fraction * 0.8)) * strength
		if bool(effect.get("is_ring", effect.kind in RING_EFFECT_KINDS)):
			var outer := radius + (0.09 if is_hurt else 0.035) * fade
			var dir_a: Vector3 = _ring_dirs[0]
			var inner_a := center + dir_a * radius
			var outer_a := center + dir_a * outer
			for index in range(20):
				var dir_b: Vector3 = _ring_dirs[index + 1]
				var inner_b := center + dir_b * radius
				var outer_b := center + dir_b * outer
				_mesh.surface_add_vertex(inner_a)
				_mesh.surface_add_vertex(inner_b)
				_mesh.surface_add_vertex(outer_a)
				_mesh.surface_add_vertex(inner_b)
				_mesh.surface_add_vertex(outer_b)
				_mesh.surface_add_vertex(outer_a)
				inner_a = inner_b
				outer_a = outer_b
		else:
			var inner_radius := radius * 0.3
			for index in range(6):
				var direction: Vector3 = _burst_dirs[index]
				var side: Vector3 = _burst_sides[index] * fade
				var start := center + direction * inner_radius
				_mesh.surface_add_vertex(start - side)
				_mesh.surface_add_vertex(start + side)
				_mesh.surface_add_vertex(center + direction * radius)
	_mesh.surface_end()

