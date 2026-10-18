extends Control
const UI = preload("res://scenes/ui/ui_style.gd")

func _ready() -> void:
	# Retain the scene resource and public button callbacks used by the teammate.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var column := UI.shell(self, "Old Tech", "A restored burial device has woken something beneath the museum. Reach it. Take it apart.", 520)
	var play := UI.button(column, "Play", _on_play_button_pressed, "PlayButton")
	UI.button(column, "Settings", _on_settings_button_pressed, "SettingsButton")
	UI.button(column, "Prototype sandbox", func(): SceneManager.start_play(true))
	UI.button(column, "Quit", _on_exit_button_pressed)
	UI.label(column, "WASD move  ·  Mouse aim  ·  Escape pause", 15).modulate = UI.MUTED
	play.grab_focus.call_deferred()

func _on_play_button_pressed() -> void:
	SceneManager.start_play()

func _on_settings_button_pressed() -> void:
	SceneManager.push_popup(&"Settings")

func _on_exit_button_pressed() -> void:
	get_tree().quit()
