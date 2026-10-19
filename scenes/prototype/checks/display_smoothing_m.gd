extends SceneTree
const Presentation=preload("res://scenes/prototype/weapon_presentation.gd")
const Cover=preload("res://scenes/prototype/cover.gd")
const Tuning=preload("res://scenes/prototype/tuning.gd")
class CountingCover extends Cover:
	var sweeps:=0
	func clip_segment(start:Vector3,finish:Vector3,radius:float=0)->Dictionary:
		sweeps+=1
		return super.clip_segment(start,finish,radius)
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
func run()->void:
	var cover:=CountingCover.new()
	cover.set_rectangles([Rect2(100,100,2,2)])
	var raw:Array[Vector3]=[]
	for i in range(120):
		var angle:=float(i)*TAU/119
		raw.append(Vector3(cos(angle)*3.4,0,sin(angle)*3.4))
	var saved:Array[Vector3]=raw.duplicate()
	var shown:=Presentation.stroke_display(raw,cover)
	expect(cover.sweeps==0,"Open-floor display smoothing performs no expensive cover sweeps")
	expect(raw==saved,"Display smoothing never mutates authoritative hit samples")
	expect(shown[0]==raw[0] and shown[-1]==raw[-1],"Display endpoints remain exact")
	for i in range(raw.size()):expect(shown[i].distance_to(raw[i])<=Presentation.STROKE_DEVIATION+.00001,"Smoothing remains within cut tolerance")
	cover.set_rectangles([Rect2(-1,-1,2,2)])
	raw.clear()
	for i in range(25):
		var x:float=float(i)/4-3
		raw.append(Vector3(x,0,-1.41+sin(x)*.005))
	cover.sweeps=0
	shown=Presentation.stroke_display(raw,cover)
	expect(cover.sweeps>0,"Near-cover curves retain exact collision sweeps")
	for i in range(shown.size()-1):
		expect(not cover.clip_segment(shown[i],shown[i+1],Tuning.RING.radius).blocked,"Smoothed clear path cannot cross cover")
	var corner:Array[Vector3]=[Vector3(-3,0,-3),Vector3(-3,0,3),Vector3(3,0,3)]
	expect(Presentation.stroke_display(corner,cover)==corner,"Intentional right-angle turns remain pinned")
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
