class_name NewGameMenu
extends "res://scenes/ui/menu_layout.gd"
## Difficulty is fixed before the story. Campaign is built only after completion.
@onready var easy: Button = %Easy
@onready var hard: Button = %Hard
@onready var start_button: Button = %StartButton
@onready var intro: NewGameIntro = %Intro
@onready var skip_tutorials: CheckBox = %SkipTutorials
func _ready() -> void:
	super._ready()
	intro.cancelled.connect(_on_intro_cancelled)
	skip_tutorials.set_pressed_no_signal(bool(GameState.preferences().skip_tutorials))
	UI.focus_on_open(self, easy)
func selected_difficulty() -> StringName:
	return &"hard" if hard.button_pressed else &"easy"
func _on_start() -> void:
	if intro.active or SceneManager.is_transitioning(): return
	start_button.disabled = true
	$Margin.hide()
	$Shade.hide()
	intro.begin(selected_difficulty(), skip_tutorials.button_pressed)
func _on_intro_cancelled() -> void:
	SceneManager.close_popup(&"NewGame")
	var scene: Node = SceneManager.get_current_scene()
	if scene != null and scene.scene_file_path != "res://scenes/main.tscn":
		SceneManager.return_main()
func _on_back() -> void:
	SceneManager.close_popup(&"NewGame")

func _on_skip_tutorials(value: bool) -> void:
	GameState.set_setting("skip_tutorials", value)
