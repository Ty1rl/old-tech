class_name NewGameMenu
extends "res://scenes/ui/menu_layout.gd"
## Selection belongs to this start dialog only; the run uses SceneManager.params.
@onready var easy: Button = %Easy
@onready var hard: Button = %Hard
@onready var start_button: Button = %StartButton
func _ready() -> void:
	super._ready()
	UI.focus_on_open(self, easy)
func selected_difficulty() -> StringName:
	return &"hard" if hard.button_pressed else &"easy"
func _on_start() -> void:
	if SceneManager.start_play(false, selected_difficulty()):
		start_button.disabled = true
func _on_back() -> void:
	SceneManager.close_popup(&"NewGame")
