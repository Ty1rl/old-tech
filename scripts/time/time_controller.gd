class_name TimeController
extends Node
## The ONE authority for the player's time meter and emergency charges.
##
## Hits, slow and repair spend from a single recharging meter. Voluntary spending
## (slow, repair) stops at zero and never ends the run. Only a hit that leaves the
## meter at zero is a depletion: it immediately spends one emergency charge and
## freezes the world (world_scale == 0) until EmergencyRewind confirms a recovery.
## Depletion with no charge left reports attempt_exhausted; the campaign then
## restarts the room with begin_attempt().
##
## Nothing here is captured in replay snapshots: rewinding the world never refunds
## time or charges. Consumers read state and call the methods below; they must not
## keep their own copy of the meter or charges. See scripts/time/CONTRACT.md.

signal meter_changed(meter: float, capacity: float)
signal charges_changed(remaining: int, per_attempt: int)
signal slow_changed(active: bool)
## A hit was applied. cost is 0.0 when recovery grace absorbed it.
signal hit_taken(cost: float)
## Hit-driven depletion spent one charge; the world is frozen until finish_emergency().
signal emergency_started(charges_remaining: int)
signal emergency_finished
## Hit-driven depletion with no charge left. The room attempt is over.
signal attempt_exhausted
signal attempt_started

const DEFAULT_SETTINGS: TimeSettings = preload("res://scripts/time/time_settings.tres")

## Tuning source. Read-only at runtime; edit the resource, not this node's copy.
@export var settings: TimeSettings = DEFAULT_SETTINGS
## When true the controller advances itself every physics tick (before gameplay
## nodes, see _ready). Tests and special drivers may disable it and call advance().
@export var auto_advance: bool = true

## Input intent: Space (or its InputMap action) is held. Set by the input owner.
var slow_requested: bool = false

var meter: float:
	get: return _meter
var capacity: float:
	get: return settings.capacity
var charges_remaining: int:
	get: return _charges
var charges_per_attempt: int:
	get: return settings.charges_per_attempt
var slow_active: bool:
	get: return _slow_active
var emergency_active: bool:
	get: return _emergency
var exhausted: bool:
	get: return _exhausted
## True while recovery grace makes hits free.
var protected: bool:
	get: return _grace_left > 0.0
## Multiply world deltas by this. 0.0 while an emergency freezes the world.
var world_scale: float:
	get: return _world_scale
## True while the repair owner reports an in-progress gesture (suppresses recharge).
var repair_gesture_active: bool:
	get: return _repair_gesture

var _meter: float = 0.0
var _charges: int = 0
var _slow_active := false
var _emergency := false
var _exhausted := false
var _grace_left := 0.0
var _recharge_wait := 0.0
var _world_scale := 1.0
var _repair_gesture := false


func _init() -> void:
	_meter = DEFAULT_SETTINGS.capacity
	_charges = DEFAULT_SETTINGS.charges_per_attempt


func _ready() -> void:
	if settings == null:
		settings = DEFAULT_SETTINGS
	# Advance before gameplay nodes so world_scale is valid for this physics tick.
	process_physics_priority = -100
	set_physics_process(auto_advance)
	begin_attempt()


func _physics_process(delta: float) -> void:
	advance(delta)


## Starts a fresh room attempt: full meter, full charges, no emergency/grace.
## Learned lessons and acquired tools live elsewhere and are unaffected.
func begin_attempt() -> void:
	_emergency = false
	_exhausted = false
	_grace_left = 0.0
	_recharge_wait = 0.0
	_repair_gesture = false
	_set_slow(false)
	_world_scale = 1.0
	_charges = settings.charges_per_attempt
	_set_meter(settings.capacity)
	charges_changed.emit(_charges, settings.charges_per_attempt)
	attempt_started.emit()


## Advances slow drain, recharge, grace and delays by REAL elapsed seconds.
## Does nothing to the meter while an emergency is active or the attempt is exhausted.
func advance(real_delta: float) -> void:
	if _emergency:
		_world_scale = 0.0
		_set_slow(false)
		return
	_world_scale = 1.0
	if _exhausted or not (real_delta > 0.0):
		_set_slow(false)
		return
	_grace_left = maxf(0.0, _grace_left - real_delta)
	var wants_slow := slow_requested and _meter > 0.0 and (_slow_active or _meter >= settings.slow_min_to_start)
	if wants_slow and settings.slow_drain_per_second > 0.0:
		var wanted := settings.slow_drain_per_second * real_delta
		var spent := minf(_meter, wanted)
		_set_meter(_meter - spent)
		# Average the tick that runs out so world time stays frame-rate independent.
		_world_scale = lerpf(1.0, settings.slow_scale, spent / wanted)
		_set_slow(_meter > 0.0)
		return
	elif wants_slow:
		_world_scale = settings.slow_scale
		_set_slow(true)
		return
	_set_slow(false)
	if _repair_gesture:
		return
	var recharge_time := real_delta
	if _recharge_wait > 0.0:
		var waited := minf(_recharge_wait, recharge_time)
		_recharge_wait -= waited
		recharge_time -= waited
	if recharge_time > 0.0 and _meter < settings.capacity:
		_set_meter(minf(settings.capacity, _meter + settings.recharge_per_second * recharge_time))


## Applies a hostile hit. Returns the time actually spent (0.0 when absorbed).
## A hit that leaves the meter at zero spends one charge and starts an emergency,
## or reports attempt_exhausted when no charge remains. Hits are ignored while an
## emergency is active or after exhaustion, so one burst cannot deplete twice.
func apply_hit(base_amount: float) -> float:
	if _emergency or _exhausted or not (base_amount > 0.0):
		return 0.0
	var cost := base_amount * settings.hit_multiplier
	if not (cost > 0.0):
		return 0.0
	if _grace_left > 0.0:
		hit_taken.emit(0.0)
		return 0.0
	var spent := minf(_meter, cost)
	_set_meter(_meter - spent)
	_recharge_wait = settings.recharge_delay_after_hit
	hit_taken.emit(spent)
	if _meter <= 0.0:
		_deplete()
	return spent


## Teaching hook: empties the meter and runs the SAME depletion path as a hit,
## spending a real charge (or exhausting the attempt). Ignores recovery grace so
## a scripted lesson cannot be silently absorbed. Returns false when an emergency
## is already active or the attempt is exhausted.
func force_depletion() -> bool:
	if _emergency or _exhausted:
		return false
	_set_meter(0.0)
	_deplete()
	return true


## Whether a voluntary spend of `amount` can be paid in full right now.
func can_afford(amount: float) -> bool:
	return not _emergency and not _exhausted and amount >= 0.0 and _meter + 0.000001 >= amount


## Atomic voluntary spend: pays in full and returns true, or changes nothing.
## Never starts an emergency, even when it leaves the meter at zero.
func try_spend(amount: float) -> bool:
	if not can_afford(amount):
		return false
	_set_meter(maxf(0.0, _meter - amount))
	return true


## Pays one repair checkpoint (settings.repair_cost_per_checkpoint) atomically.
## The repair owner restores condition only when this returns true.
func try_spend_repair_checkpoint() -> bool:
	return try_spend(settings.repair_cost_per_checkpoint)


## Repair owner reports an in-progress gesture. An idle open panel must pass false
## so recharge continues and the player is never stranded at zero.
func set_repair_gesture_active(active: bool) -> void:
	_repair_gesture = active


## Ends the active emergency after the world has been restored. Raises the meter to
## at least recovery_floor and grants recovery grace. Never refunds the charge.
func finish_emergency() -> void:
	if not _emergency:
		return
	_emergency = false
	_world_scale = 1.0
	_recharge_wait = 0.0
	_grace_left = settings.recovery_grace_seconds
	_set_meter(maxf(_meter, minf(settings.recovery_floor, settings.capacity)))
	emergency_finished.emit()


func _deplete() -> void:
	_set_slow(false)
	if _charges <= 0:
		_exhausted = true
		_world_scale = 1.0
		attempt_exhausted.emit()
		return
	_charges -= 1
	_emergency = true
	_world_scale = 0.0
	charges_changed.emit(_charges, settings.charges_per_attempt)
	emergency_started.emit(_charges)


func _set_meter(value: float) -> void:
	var clamped := clampf(value, 0.0, settings.capacity)
	if clamped == _meter:
		return
	_meter = clamped
	meter_changed.emit(_meter, settings.capacity)


func _set_slow(active: bool) -> void:
	if active == _slow_active:
		return
	_slow_active = active
	slow_changed.emit(active)
