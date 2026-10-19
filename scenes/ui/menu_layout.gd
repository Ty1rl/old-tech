class_name MuseumMenuLayout
extends Control
## Authored popup composition. Scripts change state; .tscn owns controls/layout.
const UI = preload("res://scenes/ui/ui_style.gd")
@export var panel_width := 540.0
@export var panel_height := 560.0
@onready var panel: PanelContainer = %Panel
@onready var header: VBoxContainer = %Header
@onready var scroll: ScrollContainer = %Scroll
@onready var body: VBoxContainer = %Body

func _ready() -> void:
	resized.connect(_fit)
	get_window().size_changed.connect(_fit)
	header.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	_fit.call_deferred()

func _exit_tree() -> void:
	if get_window().size_changed.is_connected(_fit):
		get_window().size_changed.disconnect(_fit)

func _fit() -> void:
	if not is_node_ready() or is_queued_for_deletion(): return
	var factor := UI.scale_for(self)
	for text in find_children("*", "Label", true, false):
		if text.has_meta("base_font_size"):
			var font_size := roundi(text.get_meta("base_font_size") * factor)
			if text.get_theme_font_size("font_size") != font_size:
				text.add_theme_font_size_override("font_size", font_size)
	for control in body.get_children():
		if control is BaseButton or control is Slider:
			control.add_theme_font_size_override("font_size", roundi(19 * factor))
	panel.custom_minimum_size.x = maxf(200, minf(panel_width * factor, size.x - 40))
	var budget := maxf(120, minf(panel_height * factor, size.y - 84))
	scroll.custom_minimum_size.y = maxf(48, budget - header.get_combined_minimum_size().y - 12)
