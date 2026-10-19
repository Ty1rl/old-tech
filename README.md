# Some Assembly Required

Our game for [Ludum Dare 60](https://ldjam.com/events/ludum-dare/60).

- **Theme:** Old Tech
- **Deadline:** Monday, October 19, 2026 at **5:00pm CDT** (America/Chicago; **22:00 UTC**).
- **Engine:** Godot **4.7.2 Standard**, using the Compatibility renderer.

Open `project.godot`, run the project, and choose **New Game**, then Easy or Hard.
The campaign crosses four museum areas and three bosses. Find the yellow flash
camera, orange heat bellows, and blue cutter as you progress.

WASD moves; mouse aims; 1–3 or Tab equips collected weapons. Hold Space to slow
time once introduced. E toggles repair; you can move and switch weapons while repairing.

Time replaces player health: hits, slow motion and repair checkpoints spend a
recharging meter. A depleting hit spends an emergency rewind charge. Scroll down
to choose an earlier moment, then click or press Enter to recover. No charges left
means retrying the room, keeping your equipment and learned tutorials.

**Testing shortcuts:** Encounter select on the menu/pause screen, or F10 in play.
Choose an area, encounter and optional boss phase. Required equipment is supplied.
Set `SceneManager.developer_tools` to `false` to hide these entrypoints.
See [mechanics, source layout and checks](scenes/prototype/README.md).

For browser audio testing, export **Web Threaded**. Its audio mixer runs on a
separate thread so rendering stalls do not interrupt streamed music. On itch.io,
enable **Embed options > Frame options > SharedArrayBuffer support** before
uploading the ZIP. Local hosting needs cross-origin isolation headers too.
The existing **Web** preset remains available without that hosting requirement.

Browser speech is prepared on the loading screen. Web Threaded streams effects
and music through Godot's mixer and limiter, with a 50 ms requested audio buffer.
The single-threaded Web preset keeps browser-native effects and a larger music
buffer. Desktop playback is unchanged.
