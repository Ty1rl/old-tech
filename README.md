# Some Assembly Required

**Old tech. Borrowed time.**

An ancient device has turned museum exhibits into monsters. Cut their connections,
strip their armor, and finish the exposed cores with cobbled-together old tech.
Slow time to line up attacks, repair your equipment under pressure, and rewind a
bad moment when your reserve runs out.

[Play in your browser](https://ty1rl.itch.io/some-assembly-required)

Made for [Ludum Dare 60](https://ldjam.com/events/ludum-dare/60), theme **Old Tech**.
The campaign crosses four museum areas and three bosses. Choose Easy or Hard;
**Skip tutorials** starts combat with all three tools, slow time and emergency rewinds.

## Controls

| Input | Action |
|---|---|
| WASD / mouse | Move / aim |
| 1, 2, 3 / Tab | Select / cycle collected tools |
| Left mouse | Draw and release the cutter, charge and release the flash, or hold the heat cone |
| Hold Space | Slow time |
| E | Open or close repair; movement and tool switching remain available |
| Wheel down / up | Choose an older / newer moment during emergency rewind |
| Enter / click | Confirm the recovery point |
| Escape | Pause or close repair |
| + / - | Zoom |

Hits, slow time and completed repair stages spend a rechargeable time reserve.
A depleting hit spends one of three emergency rewind charges. With no charges left,
retry the room with your equipment and learned tutorials. Voluntary slow time and
repair spending cannot kill you.

## Run locally

Use **Godot 4.7.2 Standard**, with the **Compatibility** renderer. No .NET runtime
is needed. Open `project.godot` and run, or from the repository root:

```sh
godot --path .
```

For encounter selection and testing shortcuts:

```sh
godot --path . -- --developer
```

F10 opens developer options in that mode. F7 cycles the diagnostic readout.
Developer options are hidden during normal play and in Web exports.

Settings includes independent Master, Music, Voice and Effects sliders.
New installs start Voice at 45%; saved levels are preserved. Music has an extra
6 dB of gain. Changes apply immediately and persist across launches.

## Build and upload

Install the matching **4.7.2 export templates** in Godot's export-template manager.
Run these commands from the repository root, using your Godot executable in place
of `godot` if it is named differently:

```sh
godot --headless --path . --editor --quit
mkdir -p build/web
godot --headless --path . --export-release "Web Threaded" build/web/index.html
(cd build/web && python3 -m zipfile -c ../some-assembly-required-web.zip *)
```

Upload `build/some-assembly-required-web.zip` to itch.io as an HTML Game. Keep
`index.html` at the ZIP root and every generated export file together. Enable
**Embed options > Frame options > SharedArrayBuffer support**, and keep
**Click to Play** enabled for browser audio activation.

For a Linux desktop build:

```sh
mkdir -p build/linux
godot --headless --path . --export-release "Linux Playtest" build/linux/SomeAssemblyRequired.x86_64
./build/linux/SomeAssemblyRequired.x86_64
```

Keep the desktop executable and its adjacent `.pck` together.

[Mechanics, source layout and checks](scenes/prototype/README.md) ·
[Browser hosting and audio verification](tools/browser/README.txt) ·
[Recorded dialogue and selection rules](audio/voice/README.txt)
