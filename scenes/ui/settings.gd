extends Control
const UI = preload("res://scenes/ui/ui_style.gd")
var widgets: Dictionary = {}

func _ready() -> void:
	var column := UI.shell(self, "Settings", "Changes apply now and are saved automatically.", 610)
	column.add_theme_constant_override("separation", 8)
	var prefs: Dictionary = GameState.preferences()
	for entry in [["sound", "Sound"], ["fullscreen", "Fullscreen"], ["tutorial", "Contextual teaching"]]:
		var key: String = entry[0]
		var toggle := CheckButton.new()
		toggle.text = entry[1]
		toggle.button_pressed = prefs[key]
		toggle.toggled.connect(func(value: bool): GameState.set_setting(key, value))
		column.add_child(toggle)
		widgets[key] = toggle
		if key == "sound":
			toggle.grab_focus.call_deferred()
	UI.label(column, "Volume", 17)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 100
	volume.step = 1
	volume.value = float(prefs.volume) * 100
	volume.custom_minimum_size.y = 32
	volume.value_changed.connect(func(value: float): GameState.set_setting("volume", value / 100))
	column.add_child(volume)
	widgets.volume = volume
	UI.label(column, "HUD numbers", 17)
	var hud := OptionButton.new()
	for text in ["Full", "Dim", "Hidden"]:
		hud.add_item(text)
	hud.selected = prefs.hud
	hud.item_selected.connect(func(value: int): GameState.set_setting("hud", value))
	column.add_child(hud)
	widgets.hud = hud
	UI.label(column, "Teaching appears once per run. Turn it off to enter encounters directly.", 15).modulate = UI.MUTED
	UI.button(column, "Back", func(): SceneManager.close_popup(&"Settings"), "BackButton")
