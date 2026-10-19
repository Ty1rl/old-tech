SUPPLIED DIALOGUE — Some Assembly Required
38 current recordings supplied by Matt. Game copies are compressed MP3s.
Round S replaces intro/time_meter and adds tutorial.pickup. Original hashes,
encoded hashes and encoding settings: audio/encoding.json and supplied-round-s.json.
Original uploads remain in shared storage/Git history; new drop originals also
have byte-identical copies in new_audio/archive/round-s. No gain normalization.

EVENTS.tsv maps each recording, event, intended trigger and upload filename.
Its transcript column and library.tres transcripts dictionary contain exact words
only for the three Round S uploads. Intro and pickup wording were confirmed by
Matt; time-meter wording comes from the shared brief. Older titles are not
verified transcripts. Rows with the same protagonist event are alternatives.

Intro is explicitly presented after New Game/difficulty confirmation, never by
AudioManager on menu entry. tutorial.time_meter belongs to its own staged damage
lesson before shooting; lesson(shot) no longer queues it automatically.
tutorial.pickup is the walk cue; campaign requests it without blocking movement.
AudioManager only plays speech; it never freezes movement or constructs lessons.

One Voice player, original -3dB node gain and separate user Voice volume remain.
World/music duck by8dB during speech. Menu music alone gets a6dB increase; other
music contexts/effects/Voice levels are unchanged. Voice/Music stay Stream mode;
Web pause assignments occur only at transitions, not every frame.

Speech lifetime contract: say/play_intro return whether a request was accepted.
Only accepted requests receive speech_finished(event, interrupted): false for
natural completion; true for skip/stop/restart/scene exit/unavailable audio/quit.
Queued accepted speech is included in is_speaking and instruction_busy; stop
cancels the whole batch. Missing/muted requests return false and do not block.
Pause holds speech until resume or explicit cancellation. Consumers distinguish
completion from cancellation instead of treating every terminal as success.

Protagonist: eight events, two recordings each, selected round-robin at playback
start; rejection never advances a variant. Seven ordinary reactions use priority1
and a shared18-second cooldown, do not queue, and never interrupt teaching.
Boss defeat uses priority2 at its gameplay trigger and may queue behind teaching.
Campaign allows incidental reactions only during pressure combat; acquire/demo/
practice/exit and emergency/menu/pause suppress them. Room-clear is an explicit
campaign milestone request; it still competes with the global bark cooldown.
The focused Round S audit/verification lives in jam-6 state/exports/round-s.
