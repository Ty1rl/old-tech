extends Node

#const MUSIC: AudioStream = preload("")
#const CLICK: AudioStream = preload("")

var music_player := AudioStreamPlayer.new()
var click_player := AudioStreamPlayer.new()

func _init() -> void:
	#music_player.stream = MUSIC
	music_player.volume_linear = 0.2
	music_player.pitch_scale = 0.5
	
	#click_player.stream = CLICK
	click_player.volume_linear = 0.2
	click_player.pitch_scale = 0.5

func _ready() -> void:
	add_child(music_player)
	music_player.play()
	
	add_child(click_player)
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node) -> void:
	if node is Button:
		node.pressed.connect(_play_click_sound)

func _play_click_sound() -> void:
	click_player.pitch_scale = randf_range(0.5, 1.0)
	click_player.play()
