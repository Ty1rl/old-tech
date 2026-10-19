extends Node
## Recorded speech lifetime + ONE contextual music player. Presentation belongs
## to the intro/tutorial owners; world effects/time motors stay in CombatFeedback.
signal speech_finished(event: StringName, interrupted: bool)

const MAX_QUEUE := 3
const BARK_INITIAL_DELAY_SECONDS := 60.0
const BARK_TUTORIAL_GRACE_SECONDS := 20.0
const PROTAGONIST_GAIN_DB := -2.0
const MENU_MUSIC_BOOST_DB := 6.0 # Menu cue only; preserve encounter/boss/victory and Voice.
@export var music_library: CombatAudioLibrary = preload("res://audio/music/contexts.tres")
@onready var voice: AudioStreamPlayer = $Voice
@onready var music: AudioStreamPlayer = $Music
@onready var _default_voice_volume_db: float = voice.volume_db
var library: DialogueLibrary
var current_event: StringName = &""
var music_context: StringName:
	get: return _music_context
var _priority := 0
var _queue: Array[Dictionary] = []
var _variants: Dictionary = {}
var reactions := ProtagonistVoice.new()
var _once: Dictionary = {}
var _bark_cooldown := 0.0
var _intro_played := false
var _duck := 0.0
var played_events: Array[StringName] = []
var _speaker_scene: Node
var _quitting := false
var _cancelling := false
var _speech_elapsed := 0.0
var _speech_serial := 0
var _music_context: StringName = &"intro"
var _music_gain := 0.0
var _music_pending := false
var _music_completed := false
var _world_pitch := 1.0
var _world_frozen := false
var _foreground_gain := 1.0
var _world_muted := false
var web_sample_voice := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	library = load("res://audio/voice/library.tres") as DialogueLibrary
	_load_voice_history()
	configure_playback_types(OS.has_feature("web"))
	voice.finished.connect(_on_finished)
	music.finished.connect(func(): _music_completed = true)
	SceneManager.scene_changed.connect(_on_scene_changed)
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(request_quit)

func configure_playback_types(for_web: bool = OS.has_feature("web")) -> void:
	web_sample_voice = for_web and not OS.has_feature("web_threaded")
	if is_instance_valid(voice):
		voice.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if web_sample_voice else AudioServer.PLAYBACK_TYPE_STREAM
	if is_instance_valid(music):
		music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM


func prepare_web_samples() -> Dictionary:
	if not OS.has_feature("web") or OS.has_feature("web_threaded"):
		return {}
	# Web Sample playback decodes a whole clip on its first play. Do that on
	# the loading screen, one clip per frame, instead of during a shot or hit.
	# Keep music streamed to avoid retaining large decoded browser buffers.
	var streams: Array[AudioStream] = []
	for variants: Array in library.clips.values():
		for stream: AudioStream in variants:
			streams.append(stream)
	var combat := load("res://audio/combat/palette.tres") as CombatAudioLibrary
	for cue: CombatAudioCue in combat.cues:
		streams.append(cue.stream)
	var prepared := 0
	var decoded_seconds := 0.0
	var longest_decode_usec := 0
	for stream in streams:
		if _quitting:
			break
		if stream == null or AudioServer.is_stream_registered_as_sample(stream):
			continue
		var started := Time.get_ticks_usec()
		AudioServer.register_stream_as_sample(stream)
		longest_decode_usec = maxi(longest_decode_usec, Time.get_ticks_usec() - started)
		prepared += 1
		decoded_seconds += stream.get_length()
		await get_tree().process_frame
	return {"prepared": prepared, "decoded_seconds": decoded_seconds, "longest_decode_usec": longest_decode_usec}

func instruction_busy() -> bool:
	if not _speech_available(): return false
	if String(current_event).begins_with("tutorial."): return true
	for item in _queue:
		if String(item.event).begins_with("tutorial."): return true
	return false

func is_speaking(event: StringName) -> bool:
	if event.is_empty() or not _speech_available(): return false
	return current_event == event or _queue.any(func(item): return item.event == event)

func play_intro() -> bool:
	if _intro_played: return false
	var accepted := say(&"narration.intro", 2)
	if accepted: _intro_played = true
	return accepted

func begin_run() -> void:
	stop_dialogue()
	reactions.reset()
	_once.clear()
	_bark_cooldown = maxf(_bark_cooldown, BARK_INITIAL_DELAY_SECONDS)
	_intro_played = false # Next explicit New Game may present its intro again.

func lesson(id: StringName) -> void:
	stop_dialogue()
	say(StringName("tutorial." + String(id)), 3)

func _bus_audible(name: StringName) -> bool:
	var index := AudioServer.get_bus_index(name)
	return index >= 0 and not AudioServer.is_bus_mute(index) and AudioServer.get_bus_volume_db(index) > -70

func _speech_available() -> bool:
	return not _quitting and library != null and is_instance_valid(voice) and _bus_audible(&"Master") and _bus_audible(&"Voice")

func react(event: StringName) -> void:
	reactions.offer(event)


func step_reactions(delta: float, active: bool, repairing: bool, idle: bool) -> void:
	reactions.step(delta, active, repairing, idle)
	if _bark_cooldown > 0 or not current_event.is_empty() or not _queue.is_empty(): return
	var candidate := reactions.choose()
	if not candidate.is_empty():
		say(candidate.event, 1, false, candidate.variant)


func _load_voice_history() -> void:
	var config := ConfigFile.new()
	if config.load(GameState.SETTINGS_PATH) != OK: return
	for event in library.clips:
		if String(event).begins_with("protagonist.") and config.has_section_key("voice_variants", event):
			_variants[event] = maxi(0, int(config.get_value("voice_variants", event)))


func _save_voice_history(event: StringName) -> void:
	var config := ConfigFile.new()
	config.load(GameState.SETTINGS_PATH)
	config.set_value("voice_variants", event, int(_variants[event]) % library.clips[event].size())
	config.save(GameState.SETTINGS_PATH)


func say(event: StringName, priority: int = 1, once: bool = false, variant_override: int = -1) -> bool:
	if event.is_empty() or _cancelling or not _speech_available() or not library.clips.has(event): return false
	if not library.clips[event] is Array: return false
	if once and _once.has(event): return false
	if event == current_event or _queue.any(func(item): return item.event == event): return false
	var variants: Array = library.clips[event]
	var clips: Array[AudioStream] = []
	for clip in variants:
		if clip is AudioStream and clip.get_length() > 0: clips.append(clip)
	if clips.is_empty(): return false
	# Milestones use the same protagonist limit; they must not queue extra chatter.
	var protagonist := String(event).begins_with("protagonist.")
	if (priority == 1 or protagonist) and (_bark_cooldown > 0 or not current_event.is_empty()): return false
	if protagonist and not _variants.has(event): _variants[event] = randi_range(0, clips.size() - 1)
	var variant := variant_override if variant_override >= 0 else int(_variants.get(event, 0)) % clips.size()
	if variant >= clips.size(): return false
	var item := {"event":event, "priority":priority, "once":once, "stream":clips[variant], "variant":variant}
	_bind_speaker_scene()
	if not current_event.is_empty() and priority <= _priority:
		if priority == 1 or _queue.size() >= MAX_QUEUE: return false
		_queue.append(item)
		return true
	if not current_event.is_empty(): stop_dialogue()
	_start(item)
	return true

func stop_dialogue() -> void:
	if _cancelling: return
	_cancelling = true
	reactions.clear_pending()
	var cancelled: Array[StringName] = []
	if not current_event.is_empty(): cancelled.append(current_event)
	for item in _queue: cancelled.append(item.event)
	# Clear before callbacks; a terminal listener cannot see stale busy state or
	# enqueue a new scene's request in the middle of this cancellation batch.
	_queue.clear()
	current_event = &""
	_priority = 0
	_speech_elapsed = 0
	_speech_serial += 1
	if is_instance_valid(voice):
		voice.stop()
		voice.volume_db = _default_voice_volume_db
	for event in cancelled:
		if String(event).begins_with("tutorial."):
			_bark_cooldown = maxf(_bark_cooldown, BARK_TUTORIAL_GRACE_SECONDS)
		speech_finished.emit(event, true)
	_cancelling = false

func _start(item: Dictionary) -> void:
	_speech_serial += 1
	var protagonist := String(item.event).begins_with("protagonist.")
	voice.stream = item.stream
	voice.volume_db = _default_voice_volume_db + (PROTAGONIST_GAIN_DB if protagonist else 0.0)
	voice.pitch_scale = .86 if String(item.event).begins_with("boss.") else 1.0
	current_event = item.event
	_priority = item.priority
	_speech_elapsed = 0
	_variants[item.event] = int(_variants.get(item.event, 0)) + 1
	if protagonist:
		_variants[item.event] = int(item.variant) + 1
		reactions.played(item.event)
		_save_voice_history(item.event)
	else:
		reactions.clear_pending()
	if item.once: _once[item.event] = true
	if _priority == 1 or protagonist:
		_bark_cooldown = reactions.interval() if protagonist else ProtagonistVoice.NORMAL_INTERVAL
	played_events.append(current_event)
	if played_events.size() > 64: played_events.pop_front()
	voice.play()

func _finish_current(interrupted: bool) -> void:
	if current_event.is_empty(): return
	var event := current_event
	current_event = &""
	_priority = 0
	_speech_elapsed = 0
	voice.volume_db = _default_voice_volume_db
	if String(event).begins_with("tutorial."):
		_bark_cooldown = maxf(_bark_cooldown, BARK_TUTORIAL_GRACE_SECONDS)
	# Handoff before notification keeps instruction_busy true across a queued
	# tutorial chain; consumers can proceed immediately after its final line.
	if not _queue.is_empty() and _speech_available(): _start(_queue.pop_front())
	speech_finished.emit(event, interrupted)

func _on_finished() -> void:
	_finish_current(false)

func _check_stopped_speech(serial: int) -> void:
	# The player's native finished signal is processed after its parent's tick.
	# Give it that turn before treating stopped playback as an interruption.
	if serial == _speech_serial and not current_event.is_empty() and not voice.playing:
		var expected := voice.stream.get_length() / maxf(.01, voice.pitch_scale) if voice.stream != null else 0.0
		var natural := web_sample_voice and expected > 0.25 and _speech_elapsed >= expected - 0.15
		_finish_current(not natural)

func _on_scene_changed(_key: StringName) -> void:
	stop_dialogue()

func _bind_speaker_scene() -> void:
	var scene := get_tree().current_scene
	if is_instance_valid(_speaker_scene) and scene == _speaker_scene: return
	if is_instance_valid(_speaker_scene) and _speaker_scene.tree_exiting.is_connected(stop_dialogue):
		_speaker_scene.tree_exiting.disconnect(stop_dialogue)
	_speaker_scene = scene
	if is_instance_valid(scene): scene.tree_exiting.connect(stop_dialogue)

func set_music_context(context: StringName) -> bool:
	if _quitting: return false
	if context != &"intro" and not music_library.music_tracks.has(context): return false
	if context == _music_context: return true
	_music_context = context
	music.stop()
	music.stream = null
	_music_gain = 0
	_music_completed = false
	if context == &"intro": return true
	music.stream = music_library.music_tracks[context]
	music.process_mode = Node.PROCESS_MODE_ALWAYS if context in [&"menu", &"victory"] else Node.PROCESS_MODE_PAUSABLE
	var pause_music := context in [&"encounter", &"boss"] and (GameState.is_paused() or get_tree().paused)
	if music.stream_paused != pause_music: music.stream_paused = pause_music
	if context in [&"menu", &"victory"]:
		_world_pitch = 1
		_world_frozen = false
		_foreground_gain = 1
		_world_muted = false
	_queue_music_start()
	return true

func set_world_audio_state(pitch: float, frozen: bool, foreground_gain: float, muted: bool = false) -> void:
	_world_pitch = clampf(pitch, .05, 4)
	_world_frozen = frozen
	_foreground_gain = clampf(foreground_gain, 0, 1)
	_world_muted = muted

func _queue_music_start() -> void:
	if not _music_pending:
		_music_pending = true
		call_deferred("_flush_music")

func _flush_music() -> void:
	_music_pending = false
	if _quitting or is_queued_for_deletion() or _music_completed or _music_context == &"intro": return
	# A paused player reports !playing; starting it again would reset its cursor.
	if not music.can_process(): return
	if music.stream_paused: return
	if _bus_audible(&"Master") and not (_music_context in [&"encounter", &"boss"] and (_world_muted or _world_frozen)) and not music.playing and music.stream != null: music.play()

func request_quit() -> void:
	if _quitting: return
	_quitting = true
	stop_dialogue()
	music.stop()
	_music_context = &"intro"
	get_tree().paused = true
	get_tree().call_group(&"world_audio", &"reset_state")
	await get_tree().create_timer(.25, true).timeout
	get_tree().quit()

func _exit_tree() -> void:
	_quitting = true
	stop_dialogue()
	voice.stream = null
	music.stop()
	music.stream = null
	library = null
	var index := AudioServer.get_bus_index(&"World")
	if index >= 0: AudioServer.set_bus_volume_db(index, 0)

func _process(delta: float) -> void:
	_bark_cooldown = maxf(0, _bark_cooldown - delta)
	var paused: bool = GameState.is_paused() or get_tree().paused
	# Web Sample playback restarts its source on every unpause assignment.
	# Only send pause transitions, even though the desktop mixer tolerates repeats.
	if voice.stream_paused != paused: voice.stream_paused = paused
	if not _speech_available() and (not current_event.is_empty() or not _queue.is_empty()):
		stop_dialogue()
	elif not current_event.is_empty():
		if not paused:
			_speech_elapsed += minf(maxf(0, delta), 0.25) if web_sample_voice else maxf(0, delta)
			# Native completion normally owns the terminal event. This bounded
			# fallback cancels an externally stopped/failed/looping stream too.
			if voice.stream == null or _speech_elapsed > voice.stream.get_length() / maxf(.01, voice.pitch_scale) + 1:
				voice.stop()
				_finish_current(true)
			elif not voice.playing and _speech_elapsed > .2:
				_check_stopped_speech.call_deferred(_speech_serial)
	var target := -8.0 if not current_event.is_empty() else 0.0
	_duck = move_toward(_duck, target, delta * 24)
	var index := AudioServer.get_bus_index(&"World")
	if index >= 0 and absf(AudioServer.get_bus_volume_db(index) - _duck) > 0.01:
		AudioServer.set_bus_volume_db(index, _duck)
	var world_music := _music_context in [&"encounter", &"boss"]
	var pause_music := world_music and paused
	if music.stream_paused != pause_music: music.stream_paused = pause_music
	var audible := _bus_audible(&"Master") and _music_context != &"intro" and not _quitting and not (world_music and _world_muted)
	var gain_target := _foreground_gain if world_music else 1.0
	if not audible or (world_music and _world_frozen): gain_target = 0
	_music_gain = lerpf(_music_gain, gain_target, 1 - exp(-maxf(0, delta) / .2))
	var next_pitch := _world_pitch if world_music else 1.0
	if absf(music.pitch_scale - next_pitch) > 0.001: music.pitch_scale = next_pitch
	var context_boost := MENU_MUSIC_BOOST_DB if _music_context == &"menu" else 0.0
	var next_db := -80.0 if _music_gain < .0001 else music_library.music_volume_db + context_boost + linear_to_db(_music_gain)
	if absf(music.volume_db - next_db) > 0.02: music.volume_db = next_db
	if not audible or (world_music and _world_frozen and _music_gain < .001):
		if music.playing: music.stop()
	elif music.can_process() and not music.stream_paused and not (world_music and _world_frozen) and not _music_completed and music.stream != null and not music.playing: _queue_music_start()
