class_name TimeStatusHUD
extends Control
## Display only. Arena supplies its ONE TimeController through bind_time_controller.
## Weapon IDs remain 1=ring, 2=beam, 3=cone. Time is never equipment.
const UI = preload("res://scenes/ui/ui_style.gd")
const Segments = preload("res://scenes/ui/condition_segments.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const TOOLS: Array[StringName] = [&"ring", &"beam", &"cone"]
const COLORS: Array[Color] = [ToolStyle.RING, ToolStyle.BEAM, ToolStyle.CONE]
const NAMES: Array[String] = ["Ring", "Flash", "Cone"]
const TIME_COLOR := Color("bf92e8")
var checkpoints: int = 4 # Updated from the active equipment resource.
const READOUT_FILE := "user://combat-hud.cfg"
const READOUT_ALPHA: Array[float] = [1.0, 0.25, 0.0]

var time_controller: TimeController
var tracked_player: Node3D
var center := Vector2.ZERO
var fractions: Array[float] = [1.0, 1.0, 1.0]
var available_tools: Array[int] = []
var selected := 0
var repairing := false
var caption := ""
var charging := false
var charge_fraction := 0.0
var readout_mode := 1
var key_hint: Label
var _scale := 1.0
var _font: Font
var _hit_light := 0.0
var _hint_state := -1
var _muted := false
var _repair_overlay: CanvasLayer
var _repair_gauge: Control
var _caption_time := 0.0
var _developer_tools := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = preload("res://assets/fonts/inter_regular.tres")
	var config := ConfigFile.new()
	if config.load(READOUT_FILE) == OK:
		readout_mode = clampi(int(config.get_value("hud", "readout", 1)), 0, 2)
	key_hint = Label.new()
	key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_hint.modulate = Color(1, 1, 1, .65)
	add_child(key_hint)
	_scale = UI.scale_for(self)
	key_hint.add_theme_font_size_override("font_size", roundi(13 * _scale))
	key_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	set_combat_hint(false)
	# Authored overlay lives above the transparent repair popup's layer (100).
	# It reads this same controller; it owns no meter/charge state or input.
	_repair_overlay = preload("res://scenes/ui/repair_time_overlay.tscn").instantiate()
	add_child(_repair_overlay)
	_repair_gauge = _repair_overlay.get_node("Gauge")
	_repair_gauge.draw.connect(_draw_repair_time)

func bind_time_controller(controller: TimeController) -> void:
	if is_instance_valid(time_controller) and time_controller.hit_taken.is_connected(_on_hit):
		time_controller.hit_taken.disconnect(_on_hit)
	time_controller = controller
	if is_instance_valid(time_controller):
		time_controller.hit_taken.connect(_on_hit)
	if is_node_ready(): set_combat_hint(_muted)
	queue_redraw()

func _on_hit(cost: float) -> void:
	if cost > 0: _hit_light = 1.0

func cycle_readout() -> void:
	readout_mode = (readout_mode + 1) % READOUT_ALPHA.size()
	var config := ConfigFile.new()
	config.set_value("hud", "readout", readout_mode)
	config.save(READOUT_FILE)

func set_combat_hint(muted: bool) -> void:
	var manager := get_node_or_null("/root/SceneManager")
	var developer := bool(manager.developer_tools) if manager else false
	_developer_tools = developer
	_muted = muted
	var slow: bool = is_instance_valid(time_controller) and time_controller.slow_unlocked
	var next := int(muted) + 2 * int(developer) + 4 * int(slow)
	if next == _hint_state: return
	_hint_state = next
	# Gameplay uses the arcs and contextual teaching. Debug help lives in F10.
	key_hint.text = ""

func update_status(player: Node3D, weapons: Node3D, equipment: RefCounted) -> void:
	checkpoints = equipment.repair_steps
	tracked_player = player
	var camera: Camera3D = player.camera
	visible = not camera.is_position_behind(player.global_position)
	var previous_tool := selected
	selected = clampi(weapons.selected_tool - 1, 0, 2)
	if previous_tool != selected: _caption_time = 1.2
	repairing = equipment.repairing != &""
	if repairing and equipment.repairing in TOOLS:
		selected = TOOLS.find(equipment.repairing)
	available_tools.clear()
	for tool: int in weapons.available_tools:
		if tool in [1, 2, 3]: available_tools.append(tool)
	var presentation: Dictionary = weapons.presentation_state()
	charging = bool(presentation.get("charging", false))
	charge_fraction = clampf(float(presentation.get("charge", 0.0)), 0, 1)
	for i in range(TOOLS.size()):
		fractions[i] = clampf(equipment.condition(TOOLS[i]), 0, 1)
	caption = ""
	if selected + 1 in available_tools:
		if fractions[selected] <= .00001: caption = "E · repair"
		elif _caption_time > 0: caption = NAMES[selected]
	queue_redraw()

func _process(delta: float) -> void:
	set_combat_hint(_muted)
	_caption_time = maxf(0.0, _caption_time - delta)
	_hit_light = maxf(0.0, _hit_light - delta * 1.6)
	var scale := UI.scale_for(self)
	if not is_equal_approx(_scale, scale):
		_scale = scale
		key_hint.add_theme_font_size_override("font_size", roundi(13 * _scale))
	key_hint.position = Vector2(16, size.y - 28 * _scale)
	key_hint.size.x = size.x - 32
	var emergency := is_instance_valid(time_controller) and time_controller.emergency_active
	key_hint.visible = false
	_repair_overlay.visible = repairing and is_visible_in_tree() and not get_tree().paused and not emergency
	if _repair_overlay.visible: _repair_gauge.queue_redraw()
	if is_instance_valid(tracked_player):
		# Project interpolated camera and player together to prevent movement drift.
		var camera: Camera3D = tracked_player.camera
		var point: Vector3 = tracked_player.get_global_transform_interpolated() * (Vector3.UP * .5)
		var view: Vector3 = camera.get_global_transform_interpolated().affine_inverse() * point
		var clip: Vector4 = camera.get_camera_projection() * Vector4(view.x, view.y, view.z, 1)
		if absf(clip.w) > .000001:
			center = (Vector2(clip.x, -clip.y) / clip.w + Vector2.ONE) * get_viewport_rect().size * .5
	queue_redraw()

func _draw() -> void:
	for i in range(TOOLS.size()):
		if not i + 1 in available_tools: continue
		var active := i == selected
		var radius := (62.0 if active else 53.0) * _scale
		var start := -PI + i * PI / 3.0 + .08
		var end := -PI + (i + 1) * PI / 3.0 - .08
		var color := Color(COLORS[i], .92 if active else .22)
		Segments.draw(self, center, radius, start, end, fractions[i], checkpoints,
			color, Color(COLORS[i], .14 if active else .06), 6 * _scale)
		if active:
			draw_arc(center, radius + 8 * _scale, start, end, 24, color, 1.5 * _scale, true)
		var middle := (start + end) * .5
		_draw_centered(str(i + 1), center + Vector2(cos(middle), sin(middle)) * (radius + 19 * _scale), 12, color)
	if not repairing: _draw_time(self, center)
	if not repairing and not (is_instance_valid(time_controller) and time_controller.emergency_active):
		_draw_centered(caption, center + Vector2(0, 125) * _scale, 12, Color("ece4d2", .8))
	if charging:
		var pointer := (get_viewport().get_mouse_position() + Vector2(0, -24 * _scale)).clamp(Vector2.ONE * 16 * _scale, size - Vector2.ONE * 16 * _scale)
		draw_arc(pointer, 12 * _scale, -PI * .5, PI * 1.5, 32, Color(COLORS[1], .2), 3 * _scale, true)
		draw_arc(pointer, 12 * _scale, -PI * .5, -PI * .5 + TAU * charge_fraction, 32, COLORS[1], 3 * _scale, true)

func _draw_repair_time() -> void:
	_draw_time(_repair_gauge, Vector2(size.x - 140 * _scale, 120 * _scale))

func _draw_time(surface: Control, origin: Vector2) -> void:
	if is_instance_valid(time_controller):
		var radius := 56 * _scale
		var start := PI * .13
		var end := PI * .87
		var fraction := clampf(time_controller.meter / maxf(.00001, time_controller.capacity), 0, 1)
		surface.draw_arc(origin, radius, start, end, 48, Color(TIME_COLOR, .16), 7 * _scale, true)
		if fraction > 0:
			surface.draw_arc(origin, radius, start, lerpf(start, end, fraction), 48, Color(TIME_COLOR.lightened(_hit_light * .35), .9), 6 * _scale, true)
		# Emergency header carries the charge count above its timeline.
		if rewind_pips_visible():
			for i in range(time_controller.charges_per_attempt):
				var at := origin + Vector2((i - (time_controller.charges_per_attempt - 1) * .5) * 15, 79) * _scale
				var points := PackedVector2Array([at + Vector2(0, -5) * _scale, at + Vector2(4, 0) * _scale, at + Vector2(0, 5) * _scale, at + Vector2(-4, 0) * _scale])
				if i < time_controller.charges_remaining: surface.draw_colored_polygon(points, TIME_COLOR)
				else:
					points.append(points[0]); surface.draw_polyline(points, Color(TIME_COLOR, .4), _scale, true)
		if _developer_tools and (repairing or readout_mode < 2) and not time_controller.emergency_active:
			_draw_centered(time_readout(), origin + Vector2(0, 104) * _scale, 12, Color(TIME_COLOR, 1.0 if repairing else READOUT_ALPHA[readout_mode]), surface)

func rewind_pips_visible() -> bool:
	return is_instance_valid(time_controller) and time_controller.rewind_unlocked and not time_controller.emergency_active

func time_readout() -> String:
	if not is_instance_valid(time_controller): return ""
	var text := "Time %.0f%%" % (100 * time_controller.meter / maxf(.00001, time_controller.capacity))
	if time_controller.rewind_unlocked: text += " · %d rewinds left" % time_controller.charges_remaining
	return text

func _draw_centered(text: String, at: Vector2, font_size: int, color: Color, surface: Control = self) -> void:
	font_size = roundi(font_size * _scale)
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := clampf(at.x - width * .5, 8, maxf(8, size.x - width - 8))
	var y := clampf(at.y, font_size, maxf(font_size, size.y - 52 * _scale))
	surface.draw_string(_font, Vector2(x, y + _scale), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, .65))
	surface.draw_string(_font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
