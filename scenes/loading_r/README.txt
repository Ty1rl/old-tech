Round R — SceneManager handoff (jam-5)

start_play(sandbox=false, difficulty=&"easy", skip_tutorials=false) -> bool
transports new_run, difficulty and the independent skip_tutorials boolean in
SceneManager.params. Legacy zero/one/two-argument callers work. Reload/restart and
encounter params remain intact; caller dictionary mutations cannot change an
accepted transition. Jam-7 owns checkbox/preference and calls this AFTER the story
intro completes/skips. No speculative campaign load/construction happens during
intro. Jam-4 owns consuming the flag and equipment/teaching skip semantics.

The measured cold pause was about 1 s of synchronous resource loading, under 1 ms
of instantiation, about 45 ms of ready/swap and about 592 ms waiting for the first
private-render draw. Imported model prefetch alone accounted for only 46 ms.
Whole-graph native threaded requests intermittently hung on this preload graph;
a dedicated serial worker completed normal starts but hung on quit during load.
Both were rejected. Their failure logs are retained in own state/development.

The final loader has NO worker threads. It loads dependency hints leaf-first on
the main thread, yielding after an 8 ms resource slice. Each individual resource
load remains indivisible. resource_steps.gd contains path hints for campaign and
sandbox. Retained references keep the weak cache hot until the root scene owns its
graph. Missing/changed hints do not replace root loading or alter gameplay: missing
paths are skipped and the final root load still resolves actual dependencies.
Regenerate hints after substantial dependency changes (build_resource_steps.py).
Other scene keys load normally after the loading panel is presented.

One authored loading panel sits above the existing fade. Its indeterminate bar
makes no invented percentage claim. Cancel and audio/main-loop updates remain
active between resource slices. cancel_transition()->bool accepts before preparing/
commit and restores scene processing, params, GameState and initiating focus/button.
Type/load failure restores the original scene, emits transition_failed(key,reason)
and shows Back; Back restores keyboard focus. Duplicates are rejected until done.
No pending worker can outlive cancellation or app quit. Window close cancels loading
before the existing AudioManager drain; exit wakes suspended transition states. Native Enter cancellation,
window close mid-load, failure, retry and different destinations are tested.

Instantiation/ready/rendering stay on the main thread. Feedback is drawn before
these stages. Only SceneTree swaps/disposes scenes, and the manager waits for its
scene_changed signal before publishing its corresponding event. Popups clear at
commit; the new scene stays disabled through the original, unextended fade and
resumes afterward. The ownership check runs after the last preparing yield.
AudioManager's lifetime event remains once per successful swap after ready; no
success event is emitted on cancellation/failure. No arena/audio/menu edits here.

last_transition_profile is a bounded value-only usec diagnostic, not a gameplay
clock. It records resource slices/largest resource/root load, instantiate, deferred
swap/ready, first-draw wait and intentional fades. Draw wait includes scheduling and
rendering; it is not pure shader/GPU duration. Story, campaign title, speech and
practice waits are excluded. Resource slicing trades total latency for responsive
feedback; remaining individual script loads and first rendering still pause.

Own state/exports/round-r holds baseline/final cold-warm JSON, raw frame gaps, full
logs, images and receipt. Cold means first campaign load in a fresh engine process;
OS/import/shader caches are untouched. Private graphics use Xvfb/Mesa llvmpipe,
not the host GPU. No quality cuts or shared cache deletion. Jam-1 still verifies
combined intro/audio/skip campaign behavior and host GPU performance on integration.

startup_baseline_r probes the original synchronous pipeline phases.
startup_profile_r uses public start_play and the real campaign, with no loader stub.
startup_r covers real starts/reload/encounter params, native Cancel, failure/retry.
startup_shutdown_r uses the real window-close/audio drain mid-load; exit verifies teardown.
Older checks should await is_transitioning() with a bounded timeout sufficient for
cold loading, rather than assuming a fixed subsecond frame count is enough.

References:
https://docs.godotengine.org/en/stable/classes/class_scenetree.html
https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html
https://github.com/godotengine/godot/issues/120827 (related engine failure report)
