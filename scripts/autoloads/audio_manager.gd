extends Node
## Recorded speech only. CombatFeedback owns world effects and music.
@onready var voice: AudioStreamPlayer = $Voice
@onready var skip_intro: Button = $Overlay/SkipIntro
var library: DialogueLibrary
var current_event: StringName = &""
var _priority := 0
var _queue: Array[Dictionary] = []
var _variants: Dictionary = {}
var _once: Dictionary = {}
var _bark_cooldown := 0.0
var _intro_played := false
var _duck := 0.0
var played_events: Array[StringName] = [] # Bounded diagnostic evidence.
var _speaker_scene: Node
var _quitting := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	library = load("res://audio/voice/library.tres") as DialogueLibrary
	voice.finished.connect(_on_finished)
	skip_intro.pressed.connect(stop_dialogue)
	SceneManager.scene_changed.connect(_on_scene_changed)
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(request_quit)

func play_intro() -> void:
	if _intro_played: return
	_intro_played = true
	say(&"narration.intro", 2)

func begin_run() -> void:
	stop_dialogue()
	_once.clear()
	_bark_cooldown = 0

func lesson(id: StringName) -> void:
	stop_dialogue()
	say(StringName("tutorial." + String(id)), 3)
	if id == &"shot": say(&"tutorial.time_meter", 2, true)

func say(event: StringName, priority: int = 1, once: bool = false) -> bool:
	if library == null or not library.clips.has(event): return false
	if once and _once.has(event): return false
	if event == current_event or _queue.any(func(item): return item.event == event): return false
	_bind_speaker_scene()
	# Incidental speech never accumulates or talks over teaching/boss entrances.
	if priority == 1 and (_bark_cooldown > 0 or voice.playing): return false
	var item := {"event": event, "priority": priority, "once": once}
	if voice.playing and priority <= _priority:
		if priority == 1 or _queue.size() >= 3: return false
		_queue.append(item)
		return true
	if voice.playing:
		voice.stop()
		_queue.clear()
	_start(item)
	return true

func stop_dialogue() -> void:
	voice.stop()
	_queue.clear()
	current_event = &""
	_priority = 0
	skip_intro.hide()

func _start(item: Dictionary) -> void:
	var variants: Array = library.clips[item.event]
	if variants.is_empty(): return
	var index := int(_variants.get(item.event, 0)) % variants.size()
	_variants[item.event] = index + 1
	voice.stream = variants[index]
	# Restrained boss register; instructional speech never slows or reverses.
	voice.pitch_scale = .86 if String(item.event).begins_with("boss.") else 1.0
	current_event = item.event
	_priority = item.priority
	if item.once: _once[item.event] = true
	if _priority == 1: _bark_cooldown = 18
	played_events.append(current_event)
	if played_events.size() > 64: played_events.pop_front()
	skip_intro.visible = current_event == &"narration.intro"
	voice.play()

func _on_finished() -> void:
	current_event = &""
	_priority = 0
	skip_intro.hide()
	if not _queue.is_empty(): _start(_queue.pop_front())

func _on_scene_changed(_key: StringName) -> void:
	stop_dialogue()

func _bind_speaker_scene() -> void:
	var scene := get_tree().current_scene
	if is_instance_valid(_speaker_scene) and scene == _speaker_scene: return
	if is_instance_valid(_speaker_scene) and _speaker_scene.tree_exiting.is_connected(stop_dialogue):
		_speaker_scene.tree_exiting.disconnect(stop_dialogue)
	_speaker_scene = scene
	if is_instance_valid(scene): scene.tree_exiting.connect(stop_dialogue)

func request_quit() -> void:
	if _quitting: return
	_quitting = true
	get_tree().paused = true
	stop_dialogue()
	get_tree().call_group(&"world_audio", &"reset_state")
	await get_tree().create_timer(.25, true).timeout
	get_tree().quit()

func _exit_tree() -> void:
	voice.stop()
	voice.stream = null
	library = null
	_queue.clear()

func _process(delta: float) -> void:
	_bark_cooldown = maxf(0, _bark_cooldown - delta)
	voice.stream_paused = GameState.is_paused()
	var target := -8.0 if voice.playing else 0.0
	_duck = move_toward(_duck, target, delta * 24)
	var index := AudioServer.get_bus_index(&"World")
	# Music routes through World, so duck it once. Voice routes to Master.
	if index >= 0: AudioServer.set_bus_volume_db(index, _duck)
