extends SceneTree
const Cover = preload("res://scenes/prototype/cover.gd")
const Presentation = preload("res://scenes/prototype/weapon_presentation.gd")
const BASELINE := "/home/mattlongname/game-jams/state/old-tech-jam-5/exports/round-n-wave2/baseline/weapon_presentation.gd"
class CountingCover extends Cover:
	var sweeps := 0
	func clip_segment(a: Vector3, b: Vector3, width: float = 0) -> Dictionary:
		sweeps += 1
		return super.clip_segment(a, b, width)
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func measure(program: GDScript, path: Array[Vector3], cover: RefCounted) -> int:
	var times: Array[int] = []
	for repeat in range(5):
		var start := Time.get_ticks_usec()
		for frame in range(80): program.stroke_display(path, cover)
		times.append(Time.get_ticks_usec() - start)
	times.sort()
	return times[2]
func run() -> void:
	var cover := CountingCover.new()
	cover.set_rectangles([Rect2(-12, -10, 3, 3), Rect2(9, -6, 3, 4), Rect2(-7, 8, 4, 2), Rect2(6, 8, 3, 2)])
	var path: Array[Vector3] = []
	for i in range(120):
		var angle := float(i) * TAU / 119
		path.append(Vector3(cos(angle) * 3.4, 0, sin(angle) * 3.4))
	var raw := path.duplicate()
	var shown := Presentation.stroke_display(path, cover)
	expect(cover.sweeps == 0, "Retains N1's optimized open-floor zero-sweep path")
	expect(raw == path and shown[0] == path[0] and shown[-1] == path[-1], "Raw data and display endpoints remain exact")
	for i in range(path.size()): expect(shown[i].distance_to(path[i]) <= Presentation.STROKE_DEVIATION + .00001, "Display deviation stays below one tenth of cutter radius")
	var corner: Array[Vector3] = [Vector3(-2,0,-2), Vector3(-2,0,2), Vector3(2,0,2)]
	expect(Presentation.stroke_display(corner, cover) == corner, "Intentional turns stay pinned")
	cover.set_rectangles([Rect2(-1, -1, 2, 2)])
	path.clear()
	for i in range(25): path.append(Vector3(float(i) / 4 - 3, 0, -1.72 + sin(i) * .001))
	shown = Presentation.stroke_display(path, cover, .7)
	expect(cover.sweeps > 0, "Exported cutter radius reaches near-cover safety tests")
	for i in range(shown.size() - 1): expect(not cover.clip_segment(shown[i], shown[i + 1], .7).blocked, "Custom-radius display cannot round into cover")
	var timing: Dictionary = {"baseline_available":false}
	# The saved N1 source is receipt evidence, not a production dependency.
	# All functional assertions above run without it on a fresh checkout.
	if FileAccess.file_exists(BASELINE):
		var baseline: GDScript = load(BASELINE)
		cover.set_rectangles([Rect2(100, 100, 2, 2)])
		expect(Presentation.stroke_display(raw, cover) == baseline.stroke_display(raw, cover), "N1 fast-path output is unchanged after extraction")
		var old_usec := measure(baseline, raw, cover)
		var new_usec := measure(Presentation, raw, cover)
		timing = {"baseline_available":true,"iterations_per_sample":80,"samples":5,"n1_median_usec":old_usec,"component_median_usec":new_usec,"relative_to_n1":float(new_usec)/maxi(1,old_usec)}
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"timing":timing}))
	quit(0 if failures.is_empty() else 1)
