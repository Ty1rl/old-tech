FALSE FACE / FRONT GUARD — ROUND J

false_face.blend is the editable source; assets/enemies/false_face/false_face.glb
is the explicit export. Both are new work based on the top-right False Face in
the shared creature lineup. No generated image textures or external resources.

Three focused visual passes
1. Lean human sculpture, oversize separated fingers, hunched neck, target parts.
2. Layered wraps, knuckles, harness rivets, enamel chips and embossed false face.
3. Longer exposed conduit, lowered shield, forearm bindings, scapular planes,
   integrated knees, narrower mask eyes and a downturned mouth. The final
   assembly correction moves the conduit coupling below the exposed core.
Close and exact ortho22 / pitch -55 / 1280x800 renders are retained per pass.

Asset contract
Metres, 2.22 m tall, feet at ground. Blender +Z up / -Y forward. The exporter
rotates only the common armature 180 degrees around Z before Y-up conversion;
the GLB is Godot +Y up / -Z forward at unit scale. Source yaw stays unchanged.
8 consolidated skinned mesh objects, 17,911 source triangles, 18 bones.
All vertices have normalized weights; arm and leg joint rings blend bones.
Body, Cloth, Harness and Hardware contain the organic silhouette and fixtures.
Cable_Blue, Core_Yellow, Shield_Orange and Shield_Rim are independent meshes.
Shield and conduit have dedicated bones. Hardware includes weighted couplings.
Hide both shield meshes and their shield-bone fixtures for a fully removed
shield. Hiding Cable_Blue independently demonstrates the cut route.

Idle is a 2-second breathing loop. Walk is a 1-second in-place articulated cycle.
ShieldOpen is a 1-second one-shot sample: the plate moves aside. The conduit
does not stretch to follow that sample. Hide Cable_Blue for the cut-open pose.
The import hook marks only Idle and Walk as looping. Mechanism visibility,
timing, travel speed and animation sampling remain under the runtime owner's
control. No process loop, physics, collision or gameplay logic is embedded.

Named bone-parented attachment markers (Godot rest coordinates, metres):
  CoreSocket    (0, 1.75, -0.49)
  CableStart    (0, 1.47, -0.48)
  CableEnd      (0, 1.32, -1.02)
  ShieldPivot   (0, 1.32, -1.10)
Exact imported values and bone/mesh names: assets/.../rig_contract.json.

Integration belongs to jam-1. This asset maps to front_guard but is not yet
connected to enemy.gd. Existing primitive hit geometry is not inferred from
these meshes: the current core point is (0,1.75,0), while this aperture sits
0.49 m forward. Runtime visual placement and existing hit tests must be aligned
during integration. The static conduit and simple walk are deliberately bounded;
there is no facial/finger rig, root motion, attack or death clip.

Editing and regeneration
Open the .blend directly to preserve manual edits. Meshes remain editable;
only the armature modifier is live. The generator checks the source hash in
own-state exports/round-j/generated-source.json before overwriting an existing
file. It refuses to replace manual edits or a source without that receipt.
iteration.json selects the retained construction pass. For a new revision,
review and explicitly archive the authored source before any rebuild.

Background build (no desktop, downloads or extra tools):
python3 ~/game-jams/projects/old-tech/blender.py --seat jam-6 --script /absolute/path/to/build_false_face.py --name false-face --timeout 180
Import through project check.py --seat jam-6 --suite import, then review:
python3 ~/game-jams/projects/old-tech/render.py --seat jam-6 --script res://scenes/enemy_preview/false_face/capture.gd --name false-face --timeout 60
Capture exits with structured checks and saves close/front/back, walk, open,
cut-open and gameplay-scale images. No prototype scenes/scripts are edited.

Review gallery, verification receipt and full logs:
~/game-jams/state/old-tech-jam-6/exports/round-j/review.html
~/game-jams/state/old-tech-jam-6/exports/round-j/verification.json
