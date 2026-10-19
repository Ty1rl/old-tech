class_name DialogueLibrary
extends Resource
## Event -> alternative recordings. Selection/playback belongs to AudioManager.
@export var clips: Dictionary = {}
## Exact words only when confirmed by the supplier; no guessed intro captions.
@export var transcripts: Dictionary[StringName, String] = {}
