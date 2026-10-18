extends "res://scenes/ui/menu_layout.gd"
@onready var sound: CheckButton = %Sound
@onready var fullscreen: CheckButton = %Fullscreen
@onready var tutorial: CheckButton = %Tutorial
@onready var volume: HSlider = %Volume
@onready var hud: OptionButton = %Hud
var widgets: Dictionary = {}

func _ready() -> void:
	super._ready()
	var prefs: Dictionary = GameState.preferences()
	sound.set_pressed_no_signal(prefs.sound)
	fullscreen.set_pressed_no_signal(prefs.fullscreen)
	tutorial.set_pressed_no_signal(prefs.tutorial)
	volume.set_value_no_signal(float(prefs.volume) * 100)
	hud.select(prefs.hud)
	widgets = {"sound": sound, "fullscreen": fullscreen, "tutorial": tutorial, "volume": volume, "hud": hud}
	UI.focus_on_open(self, sound)

func _on_sound(value: bool) -> void: GameState.set_setting("sound", value)
func _on_fullscreen(value: bool) -> void: GameState.set_setting("fullscreen", value)
func _on_tutorial(value: bool) -> void: GameState.set_setting("tutorial", value)
func _on_volume(value: float) -> void: GameState.set_setting("volume", value / 100)
func _on_hud(value: int) -> void: GameState.set_setting("hud", value)
func _on_back() -> void: SceneManager.close_popup(&"Settings")
