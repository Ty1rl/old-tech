extends Control

# Explanations freeze via the campaign's world/action guard, not SceneTree.pause.
# Practice resumes actions but keeps crowd pressure gated until complete_lesson.
signal resume_requested(id: StringName)
signal lesson_completed(id: StringName)
signal blocking_changed(value: bool)

const UI = preload("res://scenes/ui/ui_style.gd")
const BLUE := Color("60dbde")
const ORANGE := Color("ed9966")
const YELLOW := Color("f0d77b")
const VIOLET := Color("ba9ce9")
const LESSONS := {
	"cut": ["Cut the blue connection", "1 · Hold the mouse, draw across the blue link, then release. The cutter follows your line. A bare blue link dismantles its host; armored hosts may need a yellow finisher.", "cut"],
	"heat": ["Strip the orange armor", "3 · Aim at the orange covering and hold the mouse until it breaks. Heat also pushes nearby enemies back, helping you make an escape.", "heat"],
	"shot": ["Aim for yellow", "2 · Aim at the yellow core and click. An exposed core needs only a quick shot.", "shot"],
	"slow": ["Make yourself time", "Your time meter fuels slow-motion, repairs, and survival. Keep 1 selected and hold Space to slow the world. Draw across the blue link and release the mouse while time is slow. Release Space to return to full speed.", "slow"],
	"repair": ["Keep your tools working", "The yellow flash camera is exhausted. Keep 2 selected and press E to toggle repair open. Follow the matching-shape contacts to spin or trace the marked circuit and restore one section. Press E again to close (or Tab / 1–3 to switch tools); completed repairs stay fixed.", "repair"],
	"charge": ["A charged shot goes through", "2 · Hold the mouse until the lens is bright, then release. A full charge pierces enemies in its path. Solid cover stops it.", "charge"],
	"opening": ["Open it, then shoot", "Cut the blue link OR heat the orange armor. The opening stays. Switch to 2 and shoot the exposed yellow core.", "opening"],
	"pair": ["A, then B", "2 · Shoot A to open B. Shoot B before its shutter closes. Quick aimed shots work. If you wait, try the pair again.", "pair"],
	"loop": ["Cut every support", "1 · Draw around the creature through every blue support before the links reconnect. A finished loop leaves the yellow core open. Switch to 2, hold to charge, then release at the core.", "loop"],
	"zigzag": ["Follow the blue spans", "1 · Bend your line across each blue span before they reconnect. Keep your turns deliberate. Finish the pattern, then use a charged shot from 2 on yellow.", "zigzag"],
	"rewind": ["Take back a bad moment", "When a hit empties your time meter, one emergency charge is spent and the world freezes. Begin practice, wait for the forced depletion, scroll the mouse wheel down to an earlier safe moment, then click or press Enter to recover there.", "rewind"],
	"final": ["Dismantle the burial device", "Shoot A then B. Cut the zigzag, then the loop of supports. Each completed opening stays. Finish with the yellow core.", "final"],
}
var blocking := false
var practicing := false
var active_id: StringName = &""
var learned: Dictionary = {}
var world_points: Array[Vector3] = []
var ghost: Array[Vector2] = []
var projected: Array[Vector2] = []
var offscreen: Array[bool] = []
var camera: Camera3D
var age := 0.0
var align_pattern := false
var card: PanelContainer
var heading: Label
var body_label: Label
var state_label: Label
var practice_button: Button
var accent := BLUE
var _layout_size := Vector2(-1, -1)
var _layout_dirty := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.skin()
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111c22")
	style.border_color = Color("697376")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	state_label = UI.label(column, "WORLD HELD · LOOK AT THE MARKED TARGET", 13)
	heading = UI.label(column, "", 25)
	body_label = UI.label(column, "", 18)
	practice_button = UI.button(column, "Try it safely", request_practice)
	resized.connect(func(): _layout(true))
	GameState.settings_changed.connect(_on_settings_changed)
	hide()

func setup(value: Camera3D) -> void:
	camera = value

func show_known_lesson(id: StringName, targets: Array[Vector3]) -> bool:
	if not LESSONS.has(String(id)):
		return false
	var text: Array = LESSONS[String(id)]
	show_lesson(id, text[0], text[1], targets, gesture_for(id))
	if active_id == id:
		align_pattern = true
	return visible and active_id == id

func show_lesson(id: StringName, title: String, text: String, targets: Array[Vector3], gesture: Array[Vector2] = []) -> void:
	if is_learned(id) or id == active_id or not active_id.is_empty():
		return
	active_id = id
	align_pattern = false
	world_points = targets.duplicate()
	ghost = gesture.duplicate()
	heading.text = title
	body_label.text = text
	accent = ORANGE if id == &"heat" else YELLOW if id in [&"shot", &"charge", &"pair"] else VIOLET if id in [&"slow", &"rewind"] else BLUE
	state_label.modulate = accent
	state_label.text = "WORLD HELD · LOOK AT THE MARKED TARGET"
	practice_button.focus_mode = Control.FOCUS_ALL
	practice_button.mouse_filter = Control.MOUSE_FILTER_STOP
	practice_button.show()
	practicing = false
	age = 0
	_set_blocking(true)
	show()
	_layout(true)
	practice_button.grab_focus.call_deferred()

func request_practice() -> void:
	if active_id.is_empty() or not blocking or SceneManager.has_popup():
		return
	practicing = true
	practice_button.release_focus()
	practice_button.focus_mode = Control.FOCUS_NONE
	practice_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	practice_button.hide()
	state_label.text = "SAFE PRACTICE · COMPLETE THE ACTION"
	_set_blocking(false)
	resume_requested.emit(active_id)
	_layout(true)

func complete_lesson(id: StringName) -> void:
	# Only the campaign calls this after observing actual success.
	if id != active_id or not practicing:
		return
	learned[id] = true
	active_id = &""
	practicing = false
	_set_blocking(false)
	world_points.clear()
	projected.clear()
	hide()
	lesson_completed.emit(id)

func is_learned(id: StringName) -> bool:
	return bool(learned.get(id, false)) or not bool(GameState.preferences().tutorial)

func dismiss() -> void:
	active_id = &""
	practicing = false
	_set_blocking(false)
	world_points.clear()
	projected.clear()
	hide()

func reset_run() -> void:
	learned.clear()
	active_id = &""
	practicing = false
	_set_blocking(false)
	world_points.clear()
	projected.clear()
	hide()

func _set_blocking(value: bool) -> void:
	var filter := Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	mouse_filter = filter
	if is_instance_valid(card):
		card.mouse_filter = filter
	if blocking != value:
		blocking = value
		blocking_changed.emit(value)

func _on_settings_changed(values: Dictionary) -> void:
	if not values.tutorial and not active_id.is_empty():
		var id := active_id
		var prior := learned.duplicate()
		reset_run()
		learned = prior
		resume_requested.emit(id)

func _layout(force: bool = true) -> void:
	if not is_instance_valid(card):
		return
	if force or _layout_dirty or _layout_size != size:
		_layout_size = size
		_layout_dirty = false
		var factor := UI.scale_for(self)
		theme.default_font_size = roundi(19 * factor)
		var width := minf(550 * factor, maxf(220, size.x - 32))
		card.custom_minimum_size.x = width
		card.size.x = width
		heading.add_theme_font_size_override("font_size", roundi((21 if size.y < 480 else 25) * factor))
		body_label.add_theme_font_size_override("font_size", roundi((15 if size.y < 480 else 18) * factor))
		state_label.add_theme_font_size_override("font_size", roundi(13 * factor))
		card.reset_size()
	card.position.x = (size.x - card.size.x) * 0.5
	var target_y := size.y * 0.4
	if not projected.is_empty():
		target_y = projected[0].y
	card.position.y = maxf(16, size.y - card.size.y - 18) if target_y < size.y * 0.55 else 18

func _process(delta: float) -> void:
	if not visible:
		return
	# Pause/settings cover this card and stop its practice controls; emergency mode stays uncovered.
	var in_emergency: bool = GameState.has_method("is_in_emergency") and bool(GameState.call("is_in_emergency")) and not GameState.is_paused()
	var covered: bool = SceneManager.has_popup() or (not GameState.is_playing() and not in_emergency)
	card.visible = not covered
	if covered:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()
		return
	var filter := Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE
	mouse_filter = filter
	card.mouse_filter = filter
	age += delta
	projected.clear()
	offscreen.clear()
	if is_instance_valid(camera):
		var rect := get_viewport_rect().grow(-36)
		for point in world_points:
			var behind := camera.is_position_behind(point)
			var screen := camera.unproject_position(point)
			if behind:
				var local := camera.to_local(point)
				var direction := Vector2(local.x, -local.y)
				if direction.is_zero_approx():
					direction = Vector2.DOWN
				screen = size * 0.5 + direction.normalized() * size.length()
			var outside := behind or not rect.has_point(screen)
			projected.append(screen.clamp(rect.position, rect.end))
			offscreen.append(outside)
	_layout(false)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if blocking and event is InputEventMouse:
		accept_event()

func _draw() -> void:
	if not visible or not card.visible:
		return
	if blocking:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.025, 0.035, 0.35))
	var font := ThemeDB.fallback_font
	var factor := UI.scale_for(self)
	for i in range(projected.size()):
		var p := projected[i]
		draw_arc(p, 23 + 3 * sin(age * 4), 0, TAU, 40, accent, 3, true)
		draw_circle(p, 4, accent)
		var caption := str(i + 1) + (" · offscreen" if offscreen[i] else "")
		var label_position := p + Vector2(28, 6)
		label_position.x = clampf(label_position.x, 16, maxf(16, size.x - 170 * factor))
		draw_string(font, label_position, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(17 * factor), UI.PAPER)
		if offscreen[i]:
			var direction := (p - size * 0.5).normalized()
			var side := direction.orthogonal()
			draw_colored_polygon(PackedVector2Array([p + direction * 17, p - direction * 8 + side * 8, p - direction * 8 - side * 8]), accent)
	if ghost.size() >= 2 and not projected.is_empty() and not offscreen.has(true):
		var area := Rect2(projected[0], Vector2.ZERO)
		for p in projected:
			area = area.expand(p)
		area = area.grow(48)
		var path := PackedVector2Array()
		for p in ghost:
			path.append(area.position + p * area.size)
		if align_pattern and active_id in [&"loop", &"final", &"zigzag", &"pair"] and projected.size() >= 2:
			path = PackedVector2Array(projected)
			if active_id in [&"loop", &"final"]:
				path.append(projected[0])
		draw_polyline(path, Color(accent, 0.45), 3, true)
		var step := fmod(age * 0.65, 1.0) * (path.size() - 1)
		var index := mini(int(step), path.size() - 2)
		var cursor := path[index].lerp(path[index + 1], step - index)
		draw_circle(cursor, 7, UI.PAPER)
		draw_arc(cursor, 11, 0, TAU, 24, accent, 2, true)

# Ghost coordinates are normalized to the padded projected target bounds.
static func gesture_for(id: StringName) -> Array[Vector2]:
	if id in [&"loop", &"final", &"repair"]:
		var path: Array[Vector2] = []
		for i in range(25):
			path.append(Vector2(0.5, 0.5) + Vector2(cos(i * TAU / 24), sin(i * TAU / 24)) * 0.43)
		return path
	if id == &"rewind":
		return [Vector2(0.9, 0.5), Vector2(0.1, 0.5)]
	if id == &"zigzag":
		return [Vector2(0, 0.75), Vector2(0.25, 0.2), Vector2(0.5, 0.8), Vector2(0.75, 0.2), Vector2(1, 0.7)]
	if id in [&"shot", &"pair", &"charge", &"heat"]:
		return [Vector2(0.5, 1), Vector2(0.5, 0.5)]
	return [Vector2(0, 0.75), Vector2(1, 0.25)]
