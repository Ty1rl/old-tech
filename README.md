# Some Assembly Required

Our game for [Ludum Dare 60](https://ldjam.com/events/ludum-dare/60).

- **Theme:** Old Tech
- **Deadline:** Monday, October 19, 2026 at **5:00pm CDT** (America/Chicago; **22:00 UTC**).
- **Engine:** Godot **4.7.2 Standard**, using the Compatibility renderer.

Open `project.godot`, run the project, and choose **New Game**.
The campaign crosses four museum areas and three bosses. Equipment is found in
order: yellow flash camera, orange heat bellows, blue cutter, purple time device.

WASD moves; mouse aims; 1–4 or Tab equips collected tools. Hold Space to slow;
with the clock equipped, scroll down to rewind and release Space to commit.
Hold E to repair, release E to return. R retries the room; Escape pauses.

**Testing shortcuts:** Encounter select on the menu/pause screen, or F10 in play.
Choose an area, encounter and optional boss phase. Required equipment is supplied.
Set `SceneManager.developer_tools` to `false` to hide the testing entrypoints.
See [mechanics and controls](scenes/prototype/README.md) for the details.
