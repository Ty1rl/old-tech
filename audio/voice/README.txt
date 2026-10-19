SUPPLIED DIALOGUE — Some Assembly Required
40 current recordings supplied by Matt. Game copies are compressed MP3s.
Round S replaces intro/time_meter and adds tutorial.pickup. Original hashes,
encoded hashes and encoding settings: audio/encoding.json and supplied-round-s.json.
Original uploads remain in shared storage/Git history; new drop originals also
have byte-identical copies in new_audio/archive/round-s. No gain normalization.

EVENTS.tsv maps each recording, event, intended trigger and upload filename.
Its transcript column and library.tres transcripts dictionary contain exact words
for confirmed Round S/T uploads. Intro and pickup wording were confirmed by
Matt; time-meter wording comes from the shared brief. Older titles are not
verified transcripts. Rows with the same protagonist event are alternatives.

Intro is explicitly presented after New Game/difficulty confirmation, never by
AudioManager on menu entry. tutorial.time_meter belongs to its own staged damage
lesson before shooting; lesson(shot) no longer queues it automatically.
tutorial.pickup is the walk cue; campaign requests it without blocking movement.
AudioManager only plays speech; it never freezes movement or constructs lessons.

One Voice player uses -6dB node gain;protagonist reactions get another -2dB.
The separate user Voice setting applies to all speech. World/music duck by8dB
while speech plays. Menu music alone gets a6dB increase.
Native and Web Threaded use Stream playback for speech,music and combat effects.
Legacy Web uses browser Sample speech/effects prepared on the loading screen.
Music remains streamed. Pause assignments occur only at transitions.

Speech lifetime contract: say/play_intro return whether a request was accepted.
Only accepted requests receive speech_finished(event, interrupted): false for
natural completion; true for skip/stop/restart/scene exit/unavailable audio/quit.
Queued accepted speech is included in is_speaking and instruction_busy; stop
cancels the whole batch. Missing/muted requests return false and do not block.
Pause holds speech until resume or explicit cancellation. Consumers distinguish
completion from cancellation instead of treating every terminal as success.

PROTAGONIST SELECTION
Eight event categories,two recordings each. EVENTS.tsv lists the supplied labels
and gameplay triggers. There is no separate player-death or idle recording.

Gameplay offers recent events to scripts/audio/protagonist_voice.gd;AudioManager
owns playback and the shared cooldown. Competing events are resolved together.
- Keep60 seconds of initial quiet and at least20 seconds after teaching.
- Leave at least150 seconds between protagonist lines. After four lines in a run,
  extend the interval to300 seconds;four is a target,not a permanent silence cap.
- Favor unheard families:repair,combat,recovery,and room/boss milestones. Within
  them,favor unheard categories. Boss victory outranks coincident room completion.
- Reserve early combat opportunities for the first ordinary repair for up to120
  seconds of active gameplay. Repeated combat cannot claim every opening;it waits
  five minutes between combat-family reactions. No required repair means no
  indefinite silence.
- Repairs can speak during pressure,recovery and room-exit periods,never tutorial
  practice. An open repair remains relevant if its cooldown ends while repairing.
- Event opportunities expire after six seconds. Do not deliver old damage,kill
  or repair remarks when their context is gone. Tutorials and scene changes clear
  pending opportunities;actual playback alone consumes coverage and cooldown.
- Five safe,stationary minutes can use Let's keep moving from the room-clear
  alternatives. Other context-specific lines are not used as idle filler.
- The first alternative is randomized for new profiles. Each category then
  alternates,and its next choice is saved in the existing settings file's
  voice_variants section. New runs reset coverage,not clip history. Rewinds never
  restore speech counts or spent speech opportunities.

The selector uses active real time,not slowed simulation time. It does not queue
speech behind tutorials or interrupt narration,boss speech,or another reaction.
Focused checks:protagonist_voice (selection),audio_s (recordings/wiring/history),
audio_speech_r (speech lifetime),audio_u (browser audio policy).

Round T adds tutorial.movement and tutorial.tool_switch and replaces tutorial.rewind.
Exact supplied words: EVENTS.tsv/library.transcripts. One-generation provenance
and the previous rewind encoding/event row: supplied-round-t.json. Raw copies
are in shared audio/archive/round-t; prior game generation is retained in Git.
Campaign owns movement -> pickup and tool-switch -> item-lesson timing. Rewind
confirmation precedes the separate tutorial.rewind_charges statement.
