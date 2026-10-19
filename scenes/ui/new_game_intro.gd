class_name NewGameIntro
extends Control
## One owned overlay in the existing NewGame popup. No Campaign instance exists
## during narration. AudioManager owns speech lifetime; this view owns presentation.
signal cancelled
const INTRO: StringName = &"narration.intro"
const UI = preload("res://scenes/ui/ui_style.gd")
enum Phase { IDLE, NARRATING, READY, TRANSITION }
@onready var quote: Label = %Quote
@onready var skip: Button = %Skip
var active := false
var phase := Phase.IDLE
var _difficulty: StringName = &"easy"
var _skip_tutorials := false
var _paused := false
var _armed := false
var _scene: Node
var _scene_mode: ProcessMode
var _from_result := false

func _ready() -> void:
	set_process(false)
	resized.connect(_fit)
	get_window().size_changed.connect(_fit)
	get_window().close_requested.connect(_window_closed)
	SceneManager.transition_cancelled.connect(_loading_cancelled)
	SceneManager.transition_failed.connect(_loading_failed)
	_fit.call_deferred()

func begin(difficulty: StringName, skip_tutorials: bool = false) -> void:
	if active: return
	_difficulty = difficulty
	_skip_tutorials = skip_tutorials
	_scene = SceneManager.get_current_scene()
	_scene_mode = _scene.process_mode if _scene != null else Node.PROCESS_MODE_INHERIT
	if _scene != null: _scene.process_mode = Node.PROCESS_MODE_DISABLED
	_from_result = GameState.is_game_over()
	GameState.open_menu()
	AudioManager.begin_run()
	AudioManager.set_music_context(&"intro")
	AudioManager.speech_finished.connect(_speech_finished)
	active = true
	_paused = false
	_armed = false
	phase = Phase.NARRATING
	show()
	set_process(true)
	AudioManager.say(INTRO, 2)
	_refresh_lifetime()
	# Skip is deliberately absent from keyboard/gamepad focus.
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()

func _process(_delta: float) -> void:
	if not active: return
	if SceneManager.get_popup(&"") != get_parent(): return
	if not _armed and not _controls_held(): _armed = true
	if _paused or get_tree().paused: return
	_refresh_lifetime()
	if phase == Phase.READY:
		if not _controls_held(): _start_game()

func _refresh_lifetime() -> void:
	if phase == Phase.NARRATING and not _paused and not get_tree().paused and not AudioManager.is_speaking(INTRO):
		phase = Phase.READY

func _speech_finished(event: StringName, _interrupted: bool) -> void:
	if active and event == INTRO: _refresh_lifetime()

func _controls_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _input(event: InputEvent) -> void:
	if not active or SceneManager.get_popup(&"") != get_parent(): return
	if not _armed:
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_on_pause()
		get_viewport().set_input_as_handled()

func _owns_input() -> bool:
	return active and _armed and SceneManager.get_popup(&"") == get_parent()

func _on_skip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _owns_input():
			_on_skip()
			skip.accept_event()

func _on_skip() -> void:
	if not _owns_input(): return
	AudioManager.stop_dialogue()
	phase = Phase.READY
	_set_paused(false)

func _on_pause() -> void:
	if _owns_input(): _set_paused(not _paused)

func _set_paused(value: bool) -> void:
	_paused = value
	get_tree().paused = value
	_refresh_lifetime()

func _on_settings() -> void:
	if not _owns_input(): return
	_set_paused(true)
	SceneManager.push_popup(&"Settings")

func _on_menu() -> void:
	if not _owns_input(): return
	cancel()
	cancelled.emit()

func cancel() -> void:
	if not active: return
	active = false
	phase = Phase.IDLE
	_cleanup(true)
	hide()
	set_process(false)

func _on_quit() -> void:
	if not _owns_input(): return
	cancel()
	AudioManager.request_quit()

func _window_closed() -> void:
	cancel()

func _loading_failed(_key: StringName, _reason: String) -> void:
	_loading_cancelled(_key)

func _loading_cancelled(_key: StringName) -> void:
	if phase != Phase.TRANSITION: return
	phase = Phase.IDLE
	_restore_scene()
	AudioManager.set_music_context(&"menu")
	hide()
	set_process(false)
	cancelled.emit()

func _start_game() -> void:
	if SceneManager.is_transitioning(): return
	Input.flush_buffered_events()
	if _controls_held(): return
	# Disable callbacks BEFORE start_play can synchronously trigger scene teardown.
	active = false
	phase = Phase.TRANSITION
	_cleanup(false)
	# Hand scene ownership back before the loader captures its rollback state.
	_restore_scene()
	# JAM-5 owns the compatible third argument; this dispatch keeps the UI
	# delivery importable before that independent manager commit is integrated.
	var accepted: bool = SceneManager.call(&"start_play", false, _difficulty, _skip_tutorials)
	if not accepted:
		_restore_scene()
		hide()
		cancelled.emit()

func _cleanup(stop_speech: bool) -> void:
	if AudioManager.speech_finished.is_connected(_speech_finished):
		AudioManager.speech_finished.disconnect(_speech_finished)
	if stop_speech: AudioManager.stop_dialogue()
	get_tree().paused = false
	if stop_speech:
		_restore_scene()
		AudioManager.set_music_context(&"menu")
		if _from_result and not SceneManager.is_transitioning(): GameState.end_game()

func _restore_scene() -> void:
	if is_instance_valid(_scene) and not _scene.is_queued_for_deletion() and not SceneManager.is_transitioning():
		_scene.process_mode = _scene_mode

func _exit_tree() -> void:
	if active: cancel()
	if get_window().size_changed.is_connected(_fit): get_window().size_changed.disconnect(_fit)
	if get_window().close_requested.is_connected(_window_closed): get_window().close_requested.disconnect(_window_closed)

func _fit() -> void:
	if not is_node_ready() or is_queued_for_deletion(): return
	var factor := UI.scale_for(self)
	quote.custom_minimum_size.x = minf(860 * factor, maxf(1, size.x - 64))
	for text: Label in find_children("*", "Label", true, false):
		text.add_theme_font_size_override("font_size", roundi((20 if size.y < 480 * factor else 25) * factor))
	for button: Button in find_children("*", "Button", true, false):
		button.add_theme_font_size_override("font_size", roundi(18 * factor))
