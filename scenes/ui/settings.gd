extends "res://scenes/ui/menu_layout.gd"
@onready var sound: CheckButton = %Sound
@onready var fullscreen: CheckButton = %Fullscreen
@onready var tutorial: CheckButton = %Tutorial
@onready var volume: HSlider = %Volume
@onready var voice_volume: HSlider = %VoiceVolume
@onready var developer_button: Button = %DeveloperButton
var widgets: Dictionary = {}

func _ready() -> void:
	super._ready()
	developer_button.visible = SceneManager.developer_tools
	var prefs: Dictionary = GameState.preferences()
	sound.set_pressed_no_signal(prefs.sound)
	fullscreen.set_pressed_no_signal(prefs.fullscreen)
	tutorial.set_pressed_no_signal(prefs.tutorial)
	volume.set_value_no_signal(float(prefs.volume) * 100)
	voice_volume.set_value_no_signal(float(prefs.voice_volume) * 100)
	voice_volume.value_changed.connect(_on_voice_volume)
	widgets = {"sound": sound, "fullscreen": fullscreen, "tutorial": tutorial, "volume": volume}
	UI.focus_on_open(self, sound)

func _on_sound(value: bool) -> void: GameState.set_setting("sound", value)
func _on_fullscreen(value: bool) -> void: GameState.set_setting("fullscreen", value)
func _on_tutorial(value: bool) -> void: GameState.set_setting("tutorial", value)
func _on_volume(value: float) -> void: GameState.set_setting("volume", value / 100)
func _on_voice_volume(value: float) -> void: GameState.set_setting("voice_volume", value / 100)
func _on_back() -> void: SceneManager.close_popup(&"Settings")

func _on_developer() -> void:
	if not SceneManager.developer_tools: return
	developer_button.grab_focus()
	SceneManager.push_popup(&"Developer")
