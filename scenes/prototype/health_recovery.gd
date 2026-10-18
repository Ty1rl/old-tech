extends RefCounted
# Only the latest wound can recover during a room. A new hit restarts the wait.
const WAIT := 5.0
const RATE := 12.0
var recoverable := 0.0
var quiet := 0.0
func reset() -> void:
	recoverable = 0
	quiet = 0
func damaged(amount: float) -> void:
	if amount <= 0: return
	recoverable = amount
	quiet = 0
func step(delta: float, health: float, maximum: float) -> float:
	if health <= 0: return health
	var old_quiet := quiet
	quiet += maxf(0,delta)
	var active := maxf(0,quiet-WAIT) - maxf(0,old_quiet-WAIT)
	var restored := minf(recoverable,minf(maximum-health,active*RATE))
	recoverable -= restored
	return health + restored
func capture_state() -> Dictionary:
	return {"recoverable":recoverable,"quiet":quiet}
func restore_state(data: Dictionary) -> void:
	recoverable = maxf(0,float(data.get("recoverable",0)))
	quiet = maxf(0,float(data.get("quiet",0)))
