class_name EmergencyRewind
extends Node
## Emergency recovery logic (no UI). When TimeController reports a hit-driven
## depletion, this node captures the present, offers NOW plus recorded moments
## (newest first, or the seeded checkpoint when nothing is recorded) and waits for
## the player's confirmed choice. Selection only previews; confirm restores.
##
## The charge was already spent by TimeController before this begins; neither
## preview, confirm nor abandon can refund it. The world stays frozen through
## TimeController.world_scale == 0 until confirm() calls finish_emergency().
## UI (wheel/click/Enter) and world restore belong to consumers via the signals.

## A recovery choice list is ready. Choice 0 is always NOW.
signal started(choice_count: int)
## Preview request for the selected choice; restore visuals only, not run state.
signal selection_changed(index: int, age_seconds: float, state: Dictionary)
## Restore the world to `state`. Emitted before the meter floor/grace apply.
signal confirmed(age_seconds: float, state: Dictionary)
signal ended

## Age reported for the checkpoint choice, which has no recorded age.
const CHECKPOINT_AGE := -1.0
## Default world seconds stepped per mouse-wheel / arrow notch.
const DEFAULT_SCRUB_STEP_SECONDS := 1.0

@export var time_controller: TimeController:
	set = set_time_controller

## Rolling history to choose from. Assigned by the world owner.
var history: ReplayHistory
## Returns the current world snapshot; used when an emergency starts automatically.
var capture_present: Callable
## Optional per-session override for world seconds stepped per notch (0 = use TimeSettings).
var scrub_step_seconds: float = 0.0
## Optional lower bound on selectable choice index (0 = NOW allowed; >0 clamps tutorial scrub to safe moments).
var min_selectable_index: int = 0

var active: bool:
	get: return _active
## 0 = NOW; 1..n = recorded moments newest first; last may be the checkpoint.
var selected_index: int:
	get: return _selected
var choice_count: int:
	get: return _choice_count

var _active := false
var _selected := 0
var _choice_count := 0
var _present: Dictionary = {}
var _uses_checkpoint := false
var _scrub_target_age := 0.0
var _applying_step_target := false


func _ready() -> void:
	# Emergency choice input must keep working while the world tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Connects to the controller's emergency/attempt signals; safe to call from code.
func set_time_controller(value: TimeController) -> void:
	if time_controller == value:
		return
	if is_instance_valid(time_controller):
		time_controller.emergency_started.disconnect(_on_emergency_started)
		time_controller.attempt_started.disconnect(abandon)
	time_controller = value
	if is_instance_valid(time_controller):
		time_controller.emergency_started.connect(_on_emergency_started)
		# A fresh attempt (room retry) always closes a pending session without restore.
		time_controller.attempt_started.connect(abandon)


## World seconds stepped per wheel notch (~1.0s by default).
func step_seconds() -> float:
	if scrub_step_seconds > 0.0:
		return scrub_step_seconds
	if is_instance_valid(time_controller) and time_controller.settings != null:
		return maxf(0.1, time_controller.settings.scrub_step_seconds)
	return DEFAULT_SCRUB_STEP_SECONDS


## Oldest recorded age in world seconds for the current session (0.0 when empty or checkpoint-only).
func max_choice_age() -> float:
	if not _active or _choice_count <= 1 or _uses_checkpoint:
		return 0.0
	return maxf(0.0, choice_age(_choice_count - 1))


## Opens the choice list with `present` as NOW. Returns false if already active.
func begin(present: Dictionary) -> bool:
	if _active:
		return false
	_present = present.duplicate(true)
	var recorded := history.snapshot_count if history != null else 0
	_uses_checkpoint = recorded == 0 and history != null and history.has_checkpoint
	_choice_count = 1 + recorded + (1 if _uses_checkpoint else 0)
	_active = true
	_selected = 0
	min_selectable_index = 0
	_scrub_target_age = 0.0
	_applying_step_target = false
	started.emit(_choice_count)
	selection_changed.emit(0, 0.0, _present)
	return true


## Moves the selection by `steps` wheel notches (~1 world second per notch by
## recorded timestamp); positive steps go further into the past (wheel down),
## negative steps go toward NOW (wheel up).
func step_selection(steps: int) -> void:
	if not _active or steps == 0 or _choice_count <= 1:
		return
	var lo := clampi(min_selectable_index, 0, _choice_count - 1)
	var hi := _choice_count - 1
	if _uses_checkpoint or history == null or history.snapshot_count <= 0:
		select(clampi(_selected + steps, lo, hi))
		return
	var max_age := maxf(0.0, choice_age(hi))
	if max_age <= 0.0001:
		select(clampi(_selected + steps, lo, hi))
		return
	var min_age := maxf(0.0, choice_age(lo))
	var step_sec := step_seconds()
	var base_age := clampf(_scrub_target_age, min_age, max_age)
	var target_age := clampf(base_age + float(steps) * step_sec, min_age, max_age)
	var best_index := lo
	if steps < 0 and target_age <= min_age + 0.0001:
		best_index = lo
	elif steps > 0 and target_age >= max_age - 0.0001:
		best_index = hi
	else:
		var best_diff := INF
		var start_i := maxi(1, lo) if target_age > 0.0001 else lo
		for i in range(start_i, _choice_count):
			var age_i := maxf(0.0, choice_age(i))
			var diff := absf(age_i - target_age)
			if diff < best_diff - 0.000001:
				best_diff = diff
				best_index = i
	if steps > 0 and _selected < hi and best_index <= _selected:
		best_index = _selected + 1
		target_age = maxf(target_age, maxf(0.0, choice_age(best_index)))
	elif steps < 0 and _selected > lo and best_index >= _selected:
		best_index = _selected - 1
		target_age = minf(target_age, maxf(0.0, choice_age(best_index)))
	best_index = clampi(best_index, lo, hi)
	if best_index == lo or best_index == hi:
		target_age = maxf(0.0, choice_age(best_index))
	_applying_step_target = true
	select(best_index)
	_applying_step_target = false
	_scrub_target_age = target_age


func select(index: int) -> void:
	if not _active:
		return
	var lo := clampi(min_selectable_index, 0, maxi(0, _choice_count - 1))
	var clamped := clampi(index, lo, _choice_count - 1)
	if not _applying_step_target:
		_scrub_target_age = maxf(0.0, choice_age(clamped))
	if clamped == _selected:
		return
	_selected = clamped
	selection_changed.emit(_selected, choice_age(_selected), choice_state(_selected))


## Recorded seconds before NOW, 0.0 for NOW, CHECKPOINT_AGE for the checkpoint.
func choice_age(index: int) -> float:
	if index <= 0:
		return 0.0
	if _is_checkpoint(index):
		return CHECKPOINT_AGE
	return history.age_of(_history_index(index))


func choice_state(index: int) -> Dictionary:
	if index <= 0:
		return _present
	if _is_checkpoint(index):
		return history.checkpoint_state()
	return history.state_at(_history_index(index))


## Commits the selected choice: emits confirmed(state) for the world restore,
## trims newer history, then lets TimeController apply its recovery floor/grace.
func confirm() -> void:
	if not _active:
		return
	var age := choice_age(_selected)
	var state: Dictionary
	if _selected == 0:
		state = _present
	elif _is_checkpoint(_selected):
		state = history.checkpoint_state()
		history.clear()
	else:
		state = history.rewind_to(_history_index(_selected))
	_close()
	confirmed.emit(age, state)
	if is_instance_valid(time_controller):
		time_controller.finish_emergency()
	ended.emit()


## Ends the session without restoring (room retry, scene exit). No refund; the
## caller is expected to start a fresh attempt with TimeController.begin_attempt().
func abandon() -> void:
	if not _active:
		return
	_close()
	ended.emit()


func _on_emergency_started(_charges_remaining: int) -> void:
	var present: Dictionary = capture_present.call() if capture_present.is_valid() else {}
	begin(present)


func _is_checkpoint(index: int) -> bool:
	return _uses_checkpoint and index == _choice_count - 1


func _history_index(index: int) -> int:
	return history.snapshot_count - index


func _close() -> void:
	_active = false
	_selected = 0
	_choice_count = 0
	_present = {}
	_uses_checkpoint = false
	min_selectable_index = 0
	_scrub_target_age = 0.0
	_applying_step_target = false
