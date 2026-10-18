extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func expect(value:bool,text:String)->void:
	checks+=1
	if not value:failures.append(text)
func run()->void:
	var scenes=root.get_node("SceneManager")
	var game=root.get_node("GameState")
	var menu=load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu);current_scene=menu
	await process_frame;await process_frame
	expect(menu.get_node_or_null("%PlayButton")!=null,"Main menu retains public unique Play button")
	expect(ProjectSettings.get_setting("application/config/name")=="Some Assembly Required","Game carries its new title")
	var picker=scenes.push_popup(&"Developer")
	await process_frame
	expect(picker.room_picker.item_count==4,"Encounter selector lists every museum area")
	expect(picker.phase_picker.disabled,"Normal encounters offer no invalid boss phases")
	picker.room_picker.select(1);picker._update_encounters()
	picker.encounter_picker.select(picker.encounter_picker.item_count-1);picker._update_phases()
	expect(picker.phase_picker.item_count==4,"Loop boss offers exactly three phases plus normal entrance")
	picker.room_picker.select(3);picker._update_encounters()
	picker.encounter_picker.select(picker.encounter_picker.item_count-1);picker._update_phases()
	expect(picker.phase_picker.item_count==5,"Final boss offers its four valid phases")
	picker.phase_picker.select(3)
	var fade:float=scenes.fade_duration
	scenes.fade_duration=.01
	picker._launch()
	for i in range(20):
		await create_timer(.05).timeout
		if not scenes.is_transitioning():break
	var arena=current_scene
	expect(arena.has_method("debug_start"),"Selector really transitions into the campaign")
	if arena.has_method("debug_start"):
		expect(arena.room_index==3 and arena.mode==&"pressure","Selected boss checkpoint starts without replaying tutorials")
		expect(arena.director.enemies.size()==1 and arena.director.enemies[0].phase==2,"Selected phase reaches a live boss")
		expect(arena.weapons.available_tools==[2,3,1],"Late encounter includes required equipment")
		scenes.push_popup(&"Developer")
		var before:Dictionary=arena.capture_state()
		arena._physics_process(.5)
		expect(arena.capture_state()==before,"Encounter selector freezes combat while choosing a destination")
		scenes.clear_popups()
		await process_frame
	scenes.fade_duration=fade
	if is_instance_valid(current_scene):current_scene.queue_free()
	await process_frame
	game.open_menu()
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
