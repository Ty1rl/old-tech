extends SceneTree
## CPU-only presentation microbench, not Web FPS. Fixed workload and warm caches.
const Visual = preload("res://scenes/prototype/pattern_visual.gd")
const BASE_SOURCE_SHA := "0dd24e31bc0a7ad949332aea40f59e4f8c00ced38934ef3ba8a58d7410a945e6"
const BASELINE_SIGNATURES: Array[String] = [
	"c075fbaab9ace696310d6094ff1a8af13212d317499c3f8ee6e3d9d6ee2de077",
	"0202a1006c9896abb766394778038b6ec0442ac9a89fbf7b660393086a314528",
	"99f3b4c104afa325ab290bf2f852fd8b07ab1d246446e51ea90dacc063a980a0",
	"aa074b1eb67f71db491b88fa716ba82f1cc1f4c55d27d1a79609bdba6f8790ec",
	"c285ac76e36a1a3f1e4c39e118e149fda161b3c7c6c190073cb9c7927702ee54",
	"5e8220b2205168e2dba56119fd537eb7401320c5e8f58bd62345068be9113b5c",
	"71be2969103c1ae104b3b3e6808804184e1a9486b15422e040294fb1a40ee5d1",
	"33e4ee488a1d01cadfba6022758d9417d97b8ee33c84fff5de6987e54530302e",
	"526ce2c90c2af76882ab467099aa1c2efa4d0efea4f2816354c7ea55fc9a1aa5",
	"12081dead075c5196bb0e3ff7bc62f6a7e8d81d1c24c270ae7aeb07618cdeec8",
	"10998d2018c8e727f0ab33881bfe477ede50ee1141db7676076aca8a68fa54e7",
	"425756184ca2e61c7e43a0537f1feee323883cb144e837f93f7c98c5ddb4348b",
	"b887ba64758ee7638bda454c0ed318363af8a2cfbe390445fc632e435aac5f6c",
	"2fdb931f054f26cf6b88d0ff538bd3ba8ef00cc809367d3c6f9fa89c6083bdbe",
	"29ede27be4dc2411a98b1425af28187d5c5bb17a5ddeccf4a77b8f659b5e56b0",
	"faae37824adf9e378eb6ba80d7ff69fb376278aaad4b8be5396c6f4039176a27",
	"2fdedb76cf291f52bc4c5f3392f34082d940215e8d1c5e8776ee790155a7862c",
	"c4a30f39c1272c4d0cafb87f5b6e0bb3d8bedafa795fcd827179b0f41b41d952",
	"bb83690ef928d9c7f3132d103b694ec61aefad5918481986c77b068eaaf84c68",
	"a22a83f7317f6900107eba0103724106b6b338406f51aca4fa8944d39db88afc",
	"fa79d00ca90083272260059f29432ee83edb471f183b5f98049c9db2596c13e5",
	"2055d19243fd3ff25fbd051df2e2419ba4cc38ee3a55c7e1dc173880ddf245be",
	"857d3510ce7b7e0e54b9d9a0eb7ae39e23ee10c093558f37c8fb3685e3aa330b",
	"066fcd0d32149bee854afe0b8fe8a6d36435a7d541cc5fe4f2133aa6641c10e2",
	"c1f264742fb93c6e68b12e5e2e1d8e4a37364b19809f146dcd3d8818020af760",
	"7caad0e675c6a1c9a00954841e52efc09b98aad37c61b9a5028914baeff09722",
	"ac915948bc35ae5710908b92c147155138f65863faab880f212e5ff7f63fc990",
	"a7d6314dde88dccc48367b330216b44eb511c397859a071f0c35564714e635d7",
	"2b4fc6632b630e6cf6c83a309d2f824293fe1ac1e1d841f93048eeb370feda11",
	"970778f36dcb124d27bcbded70d2baaf4612bf82665f81fe76ddffea6138c136",
]
var checks := 0
var failures: Array[String] = []
var actors: Array[Node3D] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);printerr("FAIL: " + message)
func sample_values(node: Node, values: Array) -> void:
	if node is Node3D:
		values.append([node.visible,str(node.transform),str(node.global_transform)])
	if node is MeshInstance3D:
		values.append([node.mesh.get_class(),str(node.mesh.get_aabb())])
		var mat = node.material_override
		if mat is StandardMaterial3D:
			values.append([str(mat.albedo_color),mat.shading_mode,mat.no_depth_test,mat.transparency])
	if node is Label3D: values.append([node.text,str(node.modulate)])
	for child in node.get_children(): sample_values(child,values)
func snapshot() -> String:
	var values: Array = []
	for actor in actors: sample_values(actor,values)
	return JSON.stringify(values).sha256_text()
func advance(tick: int, changing: bool, pose: bool, count: int) -> void:
	var state := tick if changing else 0
	for i in count:
		var v = actors[i]
		v.sync(state%16,state%7==6,state%3==2,state%2,9.0-tick/60.0,state%4,&"windup" if state%5==4 else &"approach",state%11!=10)
		if pose: v.pose(tick/60.0,.8,&"approach",.2)
func bench(count: int, scenario: String) -> Dictionary:
	for warm in 64: advance(warm,scenario=="changing",scenario=="moving",count)
	var samples: Array[float] = []
	for batch in 81:
		var started := Time.get_ticks_usec()
		for step in 16: advance(batch*16+step,scenario=="changing",scenario=="moving",count)
		samples.append((Time.get_ticks_usec()-started)/16000.0) # ms per 32/8/1-actor batch
	samples.sort()
	var spikes := 0
	var median := samples[samples.size()/2]
	for sample in samples:
		if sample > median*2: spikes += 1
	return {"actors":count,"scenario":scenario,"samples":samples.size(),"iterations_per_sample":16,"median_ms":median,"p95_ms":samples[int(samples.size()*.95)],"worst_ms":samples[-1],"spikes_over_2x_median":spikes}
func run() -> void:
	root.size = Vector2i(1280,800)
	var out := OS.get_environment("XDG_CACHE_HOME").get_base_dir().path_join("exports/round-v")
	DirAccess.make_dir_recursive_absolute(out)
	var started := Time.get_ticks_usec()
	for i in 32:
		var visual = Visual.new()
		root.add_child(visual)
		visual.position = Vector3((i%8)*5,0,(i/8)*5)
		var mode: StringName = [&"pair",&"loop",&"zigzag"][i%3]
		visual.build(mode,i==0,&"sequence_boss" if i==0 else mode)
		actors.append(visual)
	var spawn_ms := (Time.get_ticks_usec()-started)/1000.0
	# Warm immutable geometry/material resources before timed loops.
	var measurements: Array = []
	for count in [1,8,32]:
		for scenario in ["unchanged","changing","moving"]: measurements.append(bench(count,scenario))
	# Discrete-state transitions, timer-only calls, turns, death and restore.
	var signatures: Array[String] = []
	for step in 30:
		for i in actors.size():
			var v = actors[i]
			v.rotation.y = step*.17
			v.sync(step%16,step%7==6,step%3==2,step%2,1.0+step,step%4,&"windup" if step%5==4 else &"recover",step%11!=10)
			v.pose(step*.31,0.0 if step%4==0 else .8,&"recover",.5)
			var once: Array = [];sample_values(v,once)
			v.sync(step%16,step%7==6,step%3==2,step%2,999.0,step%4,&"windup" if step%5==4 else &"recover",step%11!=10)
			var twice: Array = [];sample_values(v,twice)
			expect(once==twice,"Repeated state with timer change preserves every rendered property")
		signatures.append(snapshot())
	# Fresh node after prior units have cached many states: spawn state must apply.
	var fresh = Visual.new();root.add_child(fresh);fresh.build(&"pair",true,&"sequence_boss")
	fresh.sync(0,false,false,1,0,0,&"windup",true)
	expect(fresh.valves[1].material_override==fresh.lit_valve and fresh.valves[0].material_override==fresh.dim_valve,"New unit receives independent initial target state")
	actors[0].sync(0,false,false,0,0,0,&"recover",true)
	expect(fresh.valves[1].material_override==fresh.lit_valve,"Another unit state update cannot mutate this target material")
	fresh.free()
	# build() must invalidate state even when called with the previous sync inputs.
	var rebuilt = Visual.new();root.add_child(rebuilt);rebuilt.build(&"loop",false,&"loop")
	rebuilt.sync(1,true,true,1,0,1,&"recover",false)
	rebuilt.build(&"pair",true,&"sequence_boss")
	rebuilt.sync(1,true,true,1,0,1,&"recover",false)
	expect(not rebuilt.core.visible and not rebuilt.valves[-1].visible,"Build invalidates any previous sync state")
	rebuilt.free()
	var source_sha := FileAccess.get_sha256("res://scenes/prototype/pattern_visual.gd")
	var baseline := source_sha==BASE_SOURCE_SHA
	expect(signatures==BASELINE_SIGNATURES,"All exact-base visual-state fingerprints match (no external fixture required)")
	var report := {"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"source_sha256":source_sha,"stage":"before" if baseline else "after","renderer":"headless Dummy; CPU microbench only","resolution":[1280,800],"seed":"deterministic index/step sequence, no RNG","cache":"32 actors built;64 warm iterations per scenario; immutable resources warm","spawn_ms":spawn_ms,"measurements":measurements,"signatures":signatures}
	var file := FileAccess.open(out.path_join("before.json" if baseline else "after.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	for actor in actors: actor.free()
	actors.clear()
	await process_frame
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
