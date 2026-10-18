"""Procedural builder, Round J polish, and consolidated GLB exporter for jam-3 equipment models.

Builds and refines four independent props following ART-BRIEF.txt (Round H & Round J):
  1. ring_caster   (art/equipment/ring-caster-detail.png & art/character/ring-caster-hold.png)
  2. flash_camera  (art/equipment/flash-camera-detail.png & art/character/flash-camera-hold.png)
  3. heat_bellows  (art/equipment/heat-bellows-detail.png & art/character/heat-bellows-hold.png)
  4. time_device   (art/current-ideas/metronome-tape-clock-concept.png)

Round J upgrades:
  - Improved edge bevels, contours, and working-end detail on all four tools without altering scale.
  - Preserves all 38–90 individual editable mesh objects in each saved .blend source file.
  - Consolidates static exported GLB geometry by material while keeping moving/dynamic parts
    (Suspended_Saw_Ring, Handwheel_Crank, Accordion_Bellows, Lens_Glass_Element,
    Leather_Bellows_Chamber, Bellows_Linen_Band, Bellows_Scissor_Linkage,
    Metronome_Pendulum_Rod, Metronome_Pendulum_Weight, Hourglass_Violet_Bulbs,
    Metronome_Violet_Face) separately named, yielding 9–13 visible meshes per exported GLB.
  - Preserves Grip_R (root identity), Grip_L, and Emitter socket transforms identically.
"""
import bpy
import bmesh
import json
import math
import os
from pathlib import Path
from mathutils import Euler, Matrix, Vector

REPO = Path(os.environ["JAM_REPO"])
OUT_ROUND_J = Path(os.environ["JAM_STATE_ROOT"]) / "exports/round-j"
OUT_ART_I = Path(os.environ["JAM_STATE_ROOT"]) / "exports/art-i"
OUT_ROUND_J.mkdir(parents=True, exist_ok=True)
OUT_ART_I.mkdir(parents=True, exist_ok=True)

SRC_DIR = REPO / "art-source/equipment"
ASSET_DIR = REPO / "assets/equipment"
SRC_DIR.mkdir(parents=True, exist_ok=True)
ASSET_DIR.mkdir(parents=True, exist_ok=True)


def srgb_to_linear(hex_color: str):
    rgb = [int(hex_color[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [v / 12.92 if v < 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]


def make_palette():
    specs = [
        ("01 | forged iron", "3A3F42", 0.58, 0.60, None),
        ("02 | dark charcoal", "202426", 0.76, 0.22, None),
        ("03 | weathered walnut", "6B4C35", 0.70, 0.0, None),
        ("04 | oxhide leather", "543B2B", 0.76, 0.0, None),
        ("05 | oatmeal linen", "B5AEA0", 0.84, 0.0, None),
        ("06 | slate olive", "5E685E", 0.64, 0.26, None),
        ("07 | aged brass", "A88C58", 0.40, 0.76, None),
        ("08 | wound copper", "B86B43", 0.38, 0.82, None),
        ("09 | porcelain ivory", "D8D2C3", 0.36, 0.0, None),
        ("10 | brushed steel", "A2A9AD", 0.34, 0.85, None),
        ("11 | red switch", "B03A2E", 0.52, 0.05, None),
        ("12 | accent cyan", "60DBDE", 0.26, 0.05, ("60DBDE", 0.48)),
        ("13 | accent yellow", "F0D77B", 0.26, 0.05, ("F0D77B", 0.45)),
        ("14 | accent orange", "ED9966", 0.28, 0.05, ("ED9966", 0.50)),
        ("15 | accent violet", "BA9CE9", 0.30, 0.05, ("BA9CE9", 0.46)),
    ]
    mats = {}
    for name, hex_col, rough, metal, emit in specs:
        lin = srgb_to_linear(hex_col)
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*lin, 1.0)
        mat.use_backface_culling = True
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emit is not None:
            e_lin = srgb_to_linear(emit[0])
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = (*e_lin, 1.0)
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emit[1]
        key = name.split("|")[1].strip().replace(" ", "_")
        mats[key] = mat
    return mats


class PropBuilder:
    def __init__(self, collection, mats):
        self.collection = collection
        self.mats = mats

    def add_mesh(self, name: str, verts, faces, mat, smooth: bool = False):
        data = bpy.data.meshes.new(name)
        data.from_pydata([tuple(v) for v in verts], [], faces)
        data.update()
        bm = bmesh.new()
        bm.from_mesh(data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(data)
        bm.free()
        for poly in data.polygons:
            poly.use_smooth = smooth
        data.update()
        obj = bpy.data.objects.new(name, data)
        self.collection.objects.link(obj)
        data.materials.append(mat)
        return obj

    def add_empty(self, name: str, location):
        obj = bpy.data.objects.new(name, None)
        obj.empty_display_type = "PLAIN_AXES"
        obj.empty_display_size = 0.06
        obj.location = Vector(location)
        obj.rotation_euler = (0.0, 0.0, 0.0)
        self.collection.objects.link(obj)
        return obj

    def loft(self, name: str, rings, mat, cap: bool = True, smooth: bool = False, closed_loop: bool = False):
        n = len(rings[0])
        verts = [Vector(v) for ring in rings for v in ring]
        faces = []
        rmax = len(rings) if closed_loop else len(rings) - 1
        for j in range(rmax):
            jn = (j + 1) % len(rings)
            for i in range(n):
                inext = (i + 1) % n
                faces.append((j * n + i, j * n + inext, jn * n + inext, jn * n + i))
        if cap and not closed_loop:
            faces.append(tuple(reversed(range(n))))
            last = (len(rings) - 1) * n
            faces.append(tuple(range(last, last + n)))
        return self.add_mesh(name, verts, faces, mat, smooth=smooth)

    def beveled_box(
        self,
        name: str,
        center,
        size,
        mat,
        bevel: float = 0.005,
        segments: int = 2,
        rot_euler=(0.0, 0.0, 0.0),
        smooth: bool = False,
    ):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        sx, sy, sz = size
        for v in bm.verts:
            v.co.x *= sx
            v.co.y *= sy
            v.co.z *= sz
        if bevel > 0.0:
            bmesh.ops.bevel(
                bm,
                geom=list(bm.edges),
                offset=min(bevel, min(sx, sy, sz) * 0.34),
                segments=segments,
                profile=0.5,
                affect="EDGES",
            )
        rot_mat = Euler(rot_euler, "XYZ").to_matrix()
        cvec = Vector(center)
        for v in bm.verts:
            v.co = rot_mat @ v.co + cvec
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        data = bpy.data.meshes.new(name)
        bm.to_mesh(data)
        bm.free()
        for poly in data.polygons:
            poly.use_smooth = smooth
        data.update()
        obj = bpy.data.objects.new(name, data)
        self.collection.objects.link(obj)
        data.materials.append(mat)
        return obj

    def cylinder_along(
        self,
        name: str,
        p0,
        p1,
        r0: float,
        r1: float = None,
        mat=None,
        segments: int = 16,
        rings_between: int = 1,
        bevel_cap: float = 0.0035,
        smooth: bool = True,
    ):
        if r1 is None:
            r1 = r0
        p0 = Vector(p0)
        p1 = Vector(p1)
        axis = p1 - p0
        length = axis.length
        direction = axis.normalized() if length > 1e-6 else Vector((0, 0, 1))
        ref = Vector((0, 0, 1)) if abs(direction.z) < 0.9 else Vector((1, 0, 0))
        u = direction.cross(ref).normalized()
        v = direction.cross(u).normalized()

        profile = []
        if bevel_cap > 0.0 and length > bevel_cap * 3.0 and r0 > bevel_cap * 2.0 and r1 > bevel_cap * 2.0:
            profile.append((0.0, max(0.001, r0 - bevel_cap)))
            profile.append((bevel_cap / length, r0))
            for k in range(1, rings_between):
                t = k / float(rings_between)
                profile.append((t, r0 + (r1 - r0) * t))
            profile.append((1.0 - bevel_cap / length, r1))
            profile.append((1.0, max(0.001, r1 - bevel_cap)))
        else:
            for k in range(rings_between + 1):
                t = k / float(rings_between)
                profile.append((t, r0 + (r1 - r0) * t))

        rings = []
        for t, rad in profile:
            c = p0.lerp(p1, t)
            ring = [
                c + rad * (u * math.cos(2.0 * math.pi * i / segments) + v * math.sin(2.0 * math.pi * i / segments))
                for i in range(segments)
            ]
            rings.append(ring)
        return self.loft(name, rings, mat, cap=True, smooth=smooth)

    def tube_curve(
        self,
        name: str,
        points,
        radii,
        mat,
        segments: int = 12,
        flatten: float = 1.0,
        up_hint=None,
        cap: bool = True,
        smooth: bool = True,
    ):
        pts = [Vector(p) for p in points]
        if isinstance(radii, (int, float)):
            radii = [float(radii)] * len(pts)
        rings = []
        for j, p in enumerate(pts):
            tangent = pts[min(j + 1, len(pts) - 1)] - pts[max(j - 1, 0)]
            tangent = tangent.normalized() if tangent.length > 1e-6 else Vector((0, -1, 0))
            if up_hint is not None:
                ref = Vector(up_hint)
            else:
                ref = Vector((0, 0, 1)) if abs(tangent.z) < 0.9 else Vector((1, 0, 0))
            u = tangent.cross(ref).normalized()
            v = tangent.cross(u).normalized()
            r = radii[j]
            rings.append(
                [
                    p + r * (u * math.cos(2.0 * math.pi * i / segments) + v * flatten * math.sin(2.0 * math.pi * i / segments))
                    for i in range(segments)
                ]
            )
        return self.loft(name, rings, mat, cap=cap, smooth=smooth)

    def gear(
        self,
        name: str,
        center,
        normal,
        outer_r: float,
        inner_r: float,
        thickness: float,
        teeth: int,
        mat,
    ):
        c = Vector(center)
        nvec = Vector(normal).normalized()
        ref = Vector((0, 0, 1)) if abs(nvec.z) < 0.9 else Vector((1, 0, 0))
        u = nvec.cross(ref).normalized()
        v = nvec.cross(u).normalized()
        steps = teeth * 4
        rings = []
        for z_off in (-thickness * 0.5, thickness * 0.5):
            ring = []
            for i in range(steps):
                ang = 2.0 * math.pi * i / steps
                rad = outer_r if (i % 4 in (1, 2)) else inner_r
                ring.append(c + nvec * z_off + rad * (u * math.cos(ang) + v * math.sin(ang)))
            rings.append(ring)
        return self.loft(name, rings, mat, cap=True, smooth=False)


def horseshoe_point_and_tangent(t: float, sign: float):
    ang = t * math.pi * 0.82
    cx = sign * (0.045 + 0.195 * math.sin(ang * 0.95))
    cy = -0.185 - 0.365 * t
    dt = 0.02
    t1 = min(1.0, t + dt)
    t0 = max(0.0, t - dt)
    nx = sign * (0.045 + 0.195 * math.sin(t1 * math.pi * 0.82 * 0.95)) - sign * (
        0.045 + 0.195 * math.sin(t0 * math.pi * 0.82 * 0.95)
    )
    ny = -0.365 * (t1 - t0)
    yaw = math.atan2(ny, nx) + math.pi * 0.5
    return cx, cy, yaw


def build_ring_caster(b: PropBuilder, m: dict):
    """1. Ring Caster (art/equipment/ring-caster-detail.png & art/character/ring-caster-hold.png)."""
    # Unchanged socket contract
    b.add_empty("Grip_R", (0.0, 0.0, 0.0))
    b.add_empty("Grip_L", (0.165, -0.35, -0.035))
    b.add_empty("Emitter", (0.0, -0.49, 0.015))

    # 1. Turned wooden main handle (with contoured swell & rounded pommel)
    handle_pts = [
        (0.0, 0.21, -0.055),
        (0.0, 0.195, -0.050),
        (0.0, 0.165, -0.041),
        (0.0, 0.120, -0.029),
        (0.0, 0.075, -0.018),
        (0.0, 0.025, -0.006),
        (0.0, -0.03, 0.006),
        (0.0, -0.08, 0.016),
    ]
    handle_r = [0.017, 0.035, 0.040, 0.0445, 0.043, 0.0405, 0.043, 0.046]
    b.tube_curve("Handle_Wood_Core", handle_pts, handle_r, m["weathered_walnut"], segments=18, smooth=True)

    b.cylinder_along("Handle_Pommel_Band", (0.0, 0.175, -0.045), (0.0, 0.155, -0.039), 0.043, 0.044, m["forged_iron"], segments=18)
    b.cylinder_along("Handle_Pommel_Pin", (0.0, 0.216, -0.057), (0.0, 0.195, -0.051), 0.0085, 0.0085, m["aged_brass"], segments=12)

    for idx, t in enumerate((0.02, -0.015, -0.05)):
        z_c = -0.005 + (-t) * 0.22
        b.cylinder_along(
            f"Handle_Leather_Strap_{idx+1}",
            (0.0, t + 0.014, z_c - 0.003),
            (0.0, t - 0.014, z_c + 0.003),
            0.048,
            0.049,
            m["oxhide_leather"],
            segments=18,
        )
        b.beveled_box(f"Strap_Buckle_{idx+1}", (0.0, t, z_c + 0.048), (0.022, 0.016, 0.010), m["aged_brass"], bevel=0.0025)

    # Forged iron neck bracket joining handle to gearbox & horseshoe
    b.beveled_box("Neck_Iron_Collar", (0.0, -0.095, 0.022), (0.115, 0.075, 0.095), m["forged_iron"], bevel=0.007)
    b.beveled_box("Neck_Top_Plate", (0.0, -0.105, 0.072), (0.125, 0.085, 0.018), m["aged_brass"], bevel=0.0035)

    # 2. Cassette & Clockwork Gearbox Housing with open-top recessed cassette window
    gx, gy = 0.015, -0.145
    b.beveled_box("Gearbox_Main_Chassis", (gx, gy, 0.074), (0.175, 0.185, 0.082), m["forged_iron"], bevel=0.007)
    b.beveled_box("Gearbox_Cassette_Bed", (gx, gy, 0.116), (0.148, 0.156, 0.008), m["dark_charcoal"], bevel=0.002)

    b.beveled_box("Cassette_Bezel_Left", (gx + 0.072, gy, 0.125), (0.016, 0.164, 0.014), m["brushed_steel"], bevel=0.0025)
    b.beveled_box("Cassette_Bezel_Right", (gx - 0.072, gy, 0.125), (0.016, 0.164, 0.014), m["brushed_steel"], bevel=0.0025)
    b.beveled_box("Cassette_Bezel_Rear", (gx, gy + 0.074, 0.125), (0.130, 0.016, 0.014), m["brushed_steel"], bevel=0.0025)
    b.beveled_box("Cassette_Bezel_Front", (gx, gy - 0.074, 0.125), (0.130, 0.016, 0.014), m["brushed_steel"], bevel=0.0025)

    for r_idx, y_pos in enumerate((-0.112, -0.178)):
        b.cylinder_along(f"Tape_Pack_{r_idx+1}", (gx, y_pos, 0.118), (gx, y_pos, 0.128), 0.029, 0.029, m["oxhide_leather"], segments=18)
        b.cylinder_along(f"Tape_Hub_{r_idx+1}", (gx, y_pos, 0.120), (gx, y_pos, 0.131), 0.014, 0.014, m["porcelain_ivory"], segments=14)
        b.cylinder_along(f"Tape_Spindle_{r_idx+1}", (gx, y_pos, 0.120), (gx, y_pos, 0.135), 0.005, 0.005, m["aged_brass"], segments=10)
    b.beveled_box("Tape_Bridge_Ribbon", (gx - 0.025, gy, 0.123), (0.006, 0.068, 0.007), m["oxhide_leather"], bevel=0.001)
    b.beveled_box("Cassette_Corner_Tape", (gx - 0.066, -0.212, 0.098), (0.042, 0.046, 0.056), m["oatmeal_linen"], bevel=0.004)

    btn_specs = [
        ("Transport_Btn_Rew", -0.105, m["dark_charcoal"]),
        ("Transport_Btn_Rec", -0.140, m["red_switch"]),
        ("Transport_Btn_Play", -0.175, m["dark_charcoal"]),
    ]
    for bname, by, bmat in btn_specs:
        b.beveled_box(bname, (-0.082, by, 0.088), (0.036, 0.028, 0.024), bmat, bevel=0.0035, rot_euler=(0.0, -0.25, 0.0))

    gear_specs = [
        ("Clockwork_Gear_L1", (0.106, -0.122, 0.088), (1, 0, 0), 0.026, 0.020, 12),
        ("Clockwork_Gear_L2", (0.106, -0.168, 0.084), (1, 0, 0), 0.020, 0.015, 10),
        ("Clockwork_Gear_R1", (-0.076, -0.122, 0.056), (-1, 0, 0), 0.022, 0.017, 11),
        ("Clockwork_Gear_R2", (-0.076, -0.162, 0.056), (-1, 0, 0), 0.018, 0.014, 10),
    ]
    for gname, gpos, gnorm, gor, gir, gteeth in gear_specs:
        b.gear(gname, gpos, gnorm, gor, gir, 0.010, gteeth, m["aged_brass"])

    # Spoked handwheel crank on the left rear of the gearbox (+X in Blender)
    wheel_x, wheel_y, wheel_z = 0.138, -0.145, 0.075
    b.cylinder_along("Handwheel_Shaft", (0.095, wheel_y, wheel_z), (wheel_x + 0.012, wheel_y, wheel_z), 0.016, 0.012, m["forged_iron"], segments=12)
    rim_rings = []
    n_rim, n_sec = 20, 8
    R_wheel, r_tube = 0.068, 0.009
    for i in range(n_rim):
        ang = 2.0 * math.pi * i / n_rim
        cy = wheel_y + R_wheel * math.cos(ang)
        cz = wheel_z + R_wheel * math.sin(ang)
        ring = []
        for k in range(n_sec):
            pang = 2.0 * math.pi * k / n_sec
            rad_out = r_tube * math.cos(pang)
            x_out = r_tube * math.sin(pang)
            ring.append((wheel_x + x_out, cy + rad_out * math.cos(ang), cz + rad_out * math.sin(ang)))
        rim_rings.append(ring)
    b.loft("Handwheel_Rim", rim_rings, m["forged_iron"], cap=False, smooth=True, closed_loop=True)
    for sp in range(5):
        sang = 2.0 * math.pi * sp / 5.0
        b.cylinder_along(
            f"Handwheel_Spoke_{sp+1}",
            (wheel_x, wheel_y, wheel_z),
            (wheel_x, wheel_y + (R_wheel - 0.005) * math.cos(sang), wheel_z + (R_wheel - 0.005) * math.sin(sang)),
            0.006,
            0.005,
            m["forged_iron"],
            segments=6,
        )
    ky = wheel_y + R_wheel * math.cos(2.6)
    kz = wheel_z + R_wheel * math.sin(2.6)
    b.cylinder_along("Handwheel_Wood_Knob", (wheel_x + 0.006, ky, kz), (wheel_x + 0.062, ky, kz), 0.012, 0.016, m["weathered_walnut"], segments=12)

    # Porcelain high-voltage insulators & throw switch ahead of gearbox
    insulator_positions = [(-0.042, -0.242, 0.082), (-0.008, -0.258, 0.082), (-0.052, -0.275, 0.082)]
    for idx, ipos in enumerate(insulator_positions):
        b.cylinder_along(
            f"Porcelain_Insulator_{idx+1}",
            (ipos[0], ipos[1], ipos[2] - 0.015),
            (ipos[0], ipos[1], ipos[2] + 0.032),
            0.014,
            0.011,
            m["porcelain_ivory"],
            segments=12,
            rings_between=2,
        )
        b.cylinder_along(
            f"Insulator_Pin_{idx+1}",
            (ipos[0], ipos[1], ipos[2] + 0.030),
            (ipos[0], ipos[1], ipos[2] + 0.044),
            0.004,
            0.004,
            m["aged_brass"],
            segments=8,
        )
    b.cylinder_along("Throw_Switch_Lever", (-0.032, -0.248, 0.105), (-0.055, -0.215, 0.158), 0.004, 0.004, m["forged_iron"], segments=8)
    b.cylinder_along("Throw_Switch_Knob", (-0.052, -0.218, 0.153), (-0.058, -0.212, 0.165), 0.011, 0.011, m["dark_charcoal"], segments=10)

    # 3. Heavy Forged Iron Horseshoe / Arched Frame with sculpted beveled profile
    for side_name, sign in (("Right", -1.0), ("Left", 1.0)):
        arm_rings = []
        arm_steps = 16
        for s in range(arm_steps + 1):
            t = s / float(arm_steps)
            cx, cy, yaw = horseshoe_point_and_tangent(t, sign)
            cz = 0.015
            ux, uy = math.cos(yaw), math.sin(yaw)
            w, h, c_bevel = 0.035, 0.037, 0.0075
            sec_offsets = [
                (-w, -h + c_bevel),
                (-w + c_bevel, -h),
                (w - c_bevel, -h),
                (w, -h + c_bevel),
                (w, h - c_bevel),
                (w - c_bevel, h),
                (-w + c_bevel, h),
                (-w, h - c_bevel),
            ]
            ring = [(cx + ux * ox, cy + uy * ox, cz + oz) for ox, oz in sec_offsets]
            arm_rings.append(ring)
        b.loft(f"Horseshoe_Arm_{side_name}", arm_rings, m["forged_iron"], cap=True, smooth=False)

        for b_idx, bt in enumerate((0.26, 0.62)):
            bx, by, byaw = horseshoe_point_and_tangent(bt, sign)
            b.beveled_box(
                f"Horseshoe_Clamp_{side_name}_{b_idx+1}",
                (bx, by, 0.015),
                (0.078, 0.032, 0.082),
                m["aged_brass"] if b_idx == 1 else m["forged_iron"],
                bevel=0.0045,
                rot_euler=(0.0, 0.0, byaw),
            )

        tip_x, tip_y, tip_yaw = horseshoe_point_and_tangent(0.94, sign)
        b.beveled_box(
            f"Coil_Insulator_Block_{side_name}",
            (tip_x, tip_y, 0.015),
            (0.086, 0.052, 0.096),
            m["porcelain_ivory"],
            bevel=0.0065,
            rot_euler=(0.0, 0.0, tip_yaw),
        )

        coil_p0 = Vector((sign * 0.190, -0.545, 0.015))
        coil_p1 = Vector((sign * 0.172, -0.605, 0.015))
        b.cylinder_along(
            f"Copper_Coil_{side_name}",
            coil_p0,
            coil_p1,
            0.044,
            0.043,
            m["wound_copper"],
            segments=16,
            rings_between=4,
            smooth=True,
        )
        for r_i in range(4):
            rt = (r_i + 0.5) / 4.0
            rp0 = coil_p0.lerp(coil_p1, max(0.0, rt - 0.07))
            rp1 = coil_p0.lerp(coil_p1, min(1.0, rt + 0.07))
            b.cylinder_along(f"Coil_Rib_{side_name}_{r_i+1}", rp0, rp1, 0.0468, 0.0468, m["wound_copper"], segments=16)

        # Heavy dark iron magnetic pole shoe + stepped steel flux jaw + cyan emitter slot
        b.beveled_box(
            f"Pole_Shoe_{side_name}",
            (sign * 0.165, -0.622, 0.015),
            (0.084, 0.040, 0.094),
            m["dark_charcoal"],
            bevel=0.006,
            rot_euler=(0.0, 0.0, -sign * 0.28),
        )
        b.beveled_box(
            f"Pole_Flux_Jaw_{side_name}",
            (sign * 0.132, -0.620, 0.015),
            (0.022, 0.034, 0.078),
            m["brushed_steel"],
            bevel=0.003,
            rot_euler=(0.0, 0.0, -sign * 0.28),
        )
        b.beveled_box(
            f"Pole_Cyan_Emitter_{side_name}",
            (sign * 0.122, -0.618, 0.015),
            (0.010, 0.028, 0.066),
            m["accent_cyan"],
            bevel=0.002,
            rot_euler=(0.0, 0.0, -sign * 0.28),
        )

    b.cylinder_along(
        "Support_Grip_Pad_L",
        (0.145, -0.31, -0.022),
        (0.185, -0.40, -0.022),
        0.028,
        0.028,
        m["oxhide_leather"],
        segments=12,
    )

    rx_mid, ry_mid, ryaw_mid = horseshoe_point_and_tangent(0.38, -1.0)
    b.beveled_box(
        "Arch_Indicator_Plate",
        (rx_mid, ry_mid, 0.053),
        (0.028, 0.148, 0.009),
        m["brushed_steel"],
        bevel=0.0025,
        rot_euler=(0.0, 0.0, ryaw_mid),
    )
    b.beveled_box(
        "Arch_Cyan_Channel",
        (rx_mid, ry_mid, 0.056),
        (0.006, 0.125, 0.006),
        m["accent_cyan"],
        bevel=0.001,
        rot_euler=(0.0, 0.0, ryaw_mid),
    )
    for n_i, bt in enumerate((0.22, 0.38, 0.54)):
        nx, ny, _ = horseshoe_point_and_tangent(bt, -1.0)
        b.cylinder_along(
            f"Arch_Cyan_Node_{n_i+1}",
            (nx, ny, 0.055),
            (nx, ny, 0.065),
            0.0095,
            0.0075,
            m["accent_cyan"],
            segments=10,
        )

    cable_pts = []
    for bt in (0.15, 0.35, 0.55, 0.75, 0.90):
        kx, ky, kyaw = horseshoe_point_and_tangent(bt, 1.0)
        cable_pts.append((kx + math.cos(kyaw) * 0.038, ky + math.sin(kyaw) * 0.038, 0.032))
    b.tube_curve("High_Voltage_Conduit", cable_pts, 0.007, m["oxhide_leather"], segments=8)

    # 4. Suspended Reusable Saw/Cutter Ring (working end at Emitter)
    disc_center = Vector((0.0, -0.49, 0.015))
    outer_r = 0.139
    root_r = 0.123
    inner_r = 0.025
    teeth = 24
    steps = teeth * 3
    thick = 0.0075

    verts = []
    faces = []
    for z_sign in (-1.0, 1.0):
        z_val = disc_center.z + z_sign * thick * 0.5
        for i in range(steps):
            ang = 2.0 * math.pi * i / steps
            mod = i % 3
            r = root_r if mod == 0 else (outer_r if mod == 1 else root_r + 0.005)
            verts.append((disc_center.x + r * math.cos(ang), disc_center.y + r * math.sin(ang), z_val))
        for i in range(steps):
            ang = 2.0 * math.pi * i / steps
            verts.append((disc_center.x + inner_r * math.cos(ang), disc_center.y + inner_r * math.sin(ang), z_val))

    top_outer = steps * 2
    top_inner = steps * 3
    for i in range(steps):
        inext = (i + 1) % steps
        faces.append((i, steps + i, steps + inext, inext))
        faces.append((top_outer + i, top_outer + inext, top_inner + inext, top_inner + i))
        faces.append((i, inext, top_outer + inext, top_outer + i))
        faces.append((steps + i, top_inner + i, top_inner + inext, steps + inext))
    b.add_mesh("Suspended_Saw_Ring", verts, faces, m["brushed_steel"], smooth=False)

    # Machined raised hub flange ring around the central arbor hole (joined into Suspended_Saw_Ring on export)
    collar_rings = []
    for z_off, rad in ((-0.006, 0.042), (-0.006, 0.026), (0.006, 0.026), (0.006, 0.042)):
        collar_rings.append(
            [(disc_center.x + rad * math.cos(2.0 * math.pi * i / 20), disc_center.y + rad * math.sin(2.0 * math.pi * i / 20), disc_center.z + z_off) for i in range(20)]
        )
    b.loft("Suspended_Saw_Ring_Collar", collar_rings, m["brushed_steel"], cap=False, smooth=False, closed_loop=True)

    for side_sign in (-1.0, 1.0):
        arc_pts = []
        for k in range(9):
            ang = -0.38 + 0.76 * (k / 8.0)
            r_arc = 0.148
            arc_pts.append(
                (
                    disc_center.x + side_sign * r_arc * math.cos(ang),
                    disc_center.y + r_arc * math.sin(ang),
                    disc_center.z,
                )
            )
        b.tube_curve(f"Magnetic_Flux_Arc_{'R' if side_sign < 0 else 'L'}", arc_pts, 0.0032, m["accent_cyan"], segments=8)


def build_flash_camera(b: PropBuilder, m: dict):
    """2. Flash Camera (art/equipment/flash-camera-detail.png & art/character/flash-camera-hold.png)."""
    cx = 0.21
    b.add_empty("Grip_R", (0.0, 0.0, 0.0))
    b.add_empty("Grip_L", (0.42, 0.0, 0.0))
    b.add_empty("Emitter", (cx, -0.395, 0.025))

    # 1. Dual Vertical Wrapped Grips (Grip_R at x=0.0, Grip_L at x=0.42)
    for gname, gx in (("Right", 0.0), ("Left", 0.42)):
        p_bot = Vector((gx + (0.015 if gx == 0.0 else -0.015), 0.0, -0.085))
        p_top = Vector((gx - (0.012 if gx == 0.0 else -0.012), -0.01, 0.115))
        b.cylinder_along(f"Grip_{gname}_Core", p_bot, p_top, 0.031, 0.033, m["oxhide_leather"], segments=18, rings_between=3)
        for b_i, t in enumerate((0.25, 0.50, 0.72)):
            bp0 = p_bot.lerp(p_top, t - 0.08)
            bp1 = p_bot.lerp(p_top, t + 0.08)
            b.cylinder_along(
                f"Grip_{gname}_Wrap_{b_i+1}",
                bp0,
                bp1,
                0.0345,
                0.035,
                m["oatmeal_linen"] if b_i != 1 else m["oxhide_leather"],
                segments=18,
            )
        cap_p0 = p_top - (p_top - p_bot).normalized() * 0.015
        cap_p1 = p_top + (p_top - p_bot).normalized() * 0.018
        b.cylinder_along(f"Grip_{gname}_Top_Cap", cap_p0, cap_p1, 0.034, 0.028, m["forged_iron"], segments=18)
        btn_p0 = cap_p1
        btn_p1 = cap_p1 + (p_top - p_bot).normalized() * 0.014
        b.cylinder_along(f"Grip_{gname}_Button", btn_p0, btn_p1, 0.013, 0.012, m["aged_brass"], segments=14)

    # 2. Heavy Under-Slung U-Bracket Frame connecting both grips
    u_pts = [
        (0.015, 0.0, -0.085),
        (0.055, -0.01, -0.118),
        (0.130, -0.015, -0.125),
        (0.210, -0.015, -0.125),
        (0.290, -0.015, -0.125),
        (0.365, -0.01, -0.118),
        (0.405, 0.0, -0.085),
    ]
    b.tube_curve("Under_Bracket_Bar", u_pts, 0.022, m["forged_iron"], segments=12, flatten=0.75, smooth=False)
    b.beveled_box("Under_Bracket_Center_Block", (cx, -0.015, -0.122), (0.115, 0.055, 0.044), m["forged_iron"], bevel=0.0055)
    for bx in (cx - 0.038, cx, cx + 0.038):
        b.cylinder_along(f"Bracket_Hex_Bolt_{bx:.3f}", (bx, -0.048, -0.122), (bx, 0.018, -0.122), 0.008, 0.008, m["aged_brass"], segments=6)

    # 3. Rear Box Camera Housing, Corner Brackets & Side Junction Packs
    b.beveled_box("Camera_Rear_Housing", (cx, 0.015, 0.035), (0.275, 0.165, 0.245), m["slate_olive"], bevel=0.008)
    b.beveled_box("Camera_Rear_Iron_Frame", (cx, -0.055, 0.035), (0.292, 0.038, 0.262), m["forged_iron"], bevel=0.0065)
    b.beveled_box("Camera_Back_Rim", (cx, 0.092, 0.035), (0.285, 0.024, 0.254), m["forged_iron"], bevel=0.0055)
    b.beveled_box("Camera_Back_Plate", (cx, 0.102, 0.035), (0.245, 0.016, 0.215), m["dark_charcoal"], bevel=0.004)
    b.beveled_box("Camera_Top_Frame_Bar", (cx, 0.018, 0.156), (0.286, 0.158, 0.014), m["forged_iron"], bevel=0.0035)

    b.beveled_box("Side_Junction_Box", (cx + 0.148, 0.02, 0.045), (0.042, 0.105, 0.165), m["slate_olive"], bevel=0.0055)
    b.beveled_box("Side_Cloth_Tape_Wrap", (cx + 0.150, 0.02, 0.035), (0.046, 0.112, 0.048), m["oatmeal_linen"], bevel=0.0035)
    cable_pts = [
        (cx + 0.112, 0.015, 0.182),
        (cx + 0.155, 0.020, 0.175),
        (cx + 0.168, 0.022, 0.135),
        (cx + 0.155, 0.020, 0.095),
    ]
    b.tube_curve("Flash_HV_Cable", cable_pts, 0.007, m["dark_charcoal"], segments=8)

    for idx, ix in enumerate((cx - 0.075, cx - 0.015)):
        b.cylinder_along(
            f"Top_Porcelain_Insulator_{idx+1}",
            (ix, 0.005, 0.155),
            (ix, 0.005, 0.212),
            0.022,
            0.016,
            m["porcelain_ivory"],
            segments=16,
            rings_between=3,
        )
        b.cylinder_along(f"Top_Insulator_Term_{idx+1}", (ix, 0.005, 0.210), (ix, 0.005, 0.228), 0.007, 0.007, m["aged_brass"], segments=10)
    b.beveled_box("Top_Switch_Arm", (cx - 0.045, 0.005, 0.224), (0.075, 0.014, 0.008), m["aged_brass"], bevel=0.002, rot_euler=(0.0, -0.15, 0.0))

    b.beveled_box("Top_Capacitor_Box", (cx + 0.068, 0.015, 0.182), (0.095, 0.115, 0.056), m["slate_olive"], bevel=0.0055)
    b.beveled_box("Top_Capacitor_Tape", (cx + 0.068, 0.015, 0.183), (0.034, 0.120, 0.060), m["oatmeal_linen"], bevel=0.0035)
    b.cylinder_along(
        "Flash_Charge_Indicator",
        (cx + 0.088, -0.040, 0.180),
        (cx + 0.088, -0.052, 0.180),
        0.011,
        0.009,
        m["accent_yellow"],
        segments=12,
    )

    # 4. Accordion Pleated Bellows & Front Metal Standard Frame
    bellows_rings = []
    pleats = 6
    for p in range(pleats * 2 + 1):
        t = p / float(pleats * 2)
        y_pos = -0.065 - t * 0.195
        is_peak = (p % 2 == 1)
        taper = 1.0 - 0.15 * t
        wx = (0.112 if is_peak else 0.092) * taper
        wz = (0.105 if is_peak else 0.086) * taper
        cz = 0.028
        c_bev = 0.012
        ring = [
            (cx - wx, y_pos, cz - wz + c_bev),
            (cx - wx + c_bev, y_pos, cz - wz),
            (cx + wx - c_bev, y_pos, cz - wz),
            (cx + wx, y_pos, cz - wz + c_bev),
            (cx + wx, y_pos, cz + wz - c_bev),
            (cx + wx - c_bev, y_pos, cz + wz),
            (cx - wx + c_bev, y_pos, cz + wz),
            (cx - wx, y_pos, cz + wz - c_bev),
        ]
        bellows_rings.append(ring)
    b.loft("Accordion_Bellows", bellows_rings, m["dark_charcoal"], cap=True, smooth=False)

    fy = -0.268
    b.beveled_box("Front_Standard_Top", (cx, fy, 0.125), (0.215, 0.024, 0.022), m["forged_iron"], bevel=0.0045)
    b.beveled_box("Front_Standard_Bot", (cx, fy, -0.068), (0.215, 0.026, 0.024), m["forged_iron"], bevel=0.0045)
    b.beveled_box("Front_Sight_Bracket", (cx, fy - 0.006, 0.144), (0.062, 0.018, 0.022), m["aged_brass"], bevel=0.003)
    for sx in (cx - 0.096, cx + 0.096):
        b.beveled_box(f"Front_Standard_Post_{sx:.2f}", (sx, fy, 0.028), (0.022, 0.024, 0.210), m["forged_iron"], bevel=0.0045)
        for rz in (-0.068, 0.122):
            b.beveled_box(
                f"Guide_Rail_{sx:.2f}_{rz:.2f}",
                (sx, -0.165, rz),
                (0.016, 0.215, 0.016),
                m["forged_iron"],
                bevel=0.0035,
            )

    # 5. Machined Smooth-Turned Compound Brass Lens Housing & Optical Dome (working end at Emitter)
    lz = 0.025
    b.cylinder_along("Lens_Base_Flange", (cx, -0.260, lz), (cx, -0.292, lz), 0.091, 0.089, m["aged_brass"], segments=28, smooth=True)
    b.cylinder_along("Lens_Mid_Ring", (cx, -0.290, lz), (cx, -0.344, lz), 0.079, 0.077, m["aged_brass"], segments=28, smooth=True)
    b.cylinder_along("Lens_Front_Bezel_Outer", (cx, -0.342, lz), (cx, -0.386, lz), 0.087, 0.084, m["aged_brass"], segments=28, smooth=True)
    b.cylinder_along("Lens_Aperture_Shadow_Ring", (cx, -0.372, lz), (cx, -0.389, lz), 0.069, 0.065, m["dark_charcoal"], segments=28, smooth=True)
    b.cylinder_along("Lens_Inner_Brass_Retainer", (cx, -0.382, lz), (cx, -0.391, lz), 0.061, 0.059, m["aged_brass"], segments=28, smooth=True)

    for lx in (cx - 0.085, cx + 0.085):
        b.beveled_box(f"Lens_Trunnion_Lug_{lx:.2f}", (lx, -0.348, lz), (0.024, 0.034, 0.032), m["aged_brass"], bevel=0.0045)
    b.beveled_box("Lens_Shutter_Plate", (cx, -0.355, lz - 0.078), (0.068, 0.042, 0.012), m["forged_iron"], bevel=0.0025, rot_euler=(0.25, 0.0, 0.0))

    dome_profile = [
        (-0.384, 0.057),
        (-0.391, 0.048),
        (-0.396, 0.032),
        (-0.399, 0.014),
    ]
    dome_rings = [
        [(cx + r_d * math.cos(2.0 * math.pi * i / 28), y_d, lz + r_d * math.sin(2.0 * math.pi * i / 28)) for i in range(28)]
        for y_d, r_d in dome_profile
    ]
    b.loft("Lens_Glass_Element", dome_rings, m["accent_yellow"], cap=True, smooth=True)


def build_heat_bellows(b: PropBuilder, m: dict):
    """3. Heat Bellows (art/equipment/heat-bellows-detail.png & art/character/heat-bellows-hold.png)."""
    b.add_empty("Grip_R", (0.0, 0.0, 0.0))
    b.add_empty("Grip_L", (0.0, -0.37, -0.075))
    b.add_empty("Emitter", (0.0, -0.60, 0.105))

    # 1. Rear Pistol Grip (Grip_R), Red Trigger & Padded Shoulder Brace
    grip_p0 = Vector((0.0, 0.045, -0.095))
    grip_p1 = Vector((0.0, -0.020, 0.055))
    b.cylinder_along("Rear_Pistol_Grip", grip_p0, grip_p1, 0.029, 0.031, m["oxhide_leather"], segments=16, rings_between=2)
    b.cylinder_along(
        "Rear_Grip_Linen_Wrap",
        grip_p0.lerp(grip_p1, 0.28),
        grip_p0.lerp(grip_p1, 0.68),
        0.033,
        0.033,
        m["oatmeal_linen"],
        segments=16,
    )
    b.cylinder_along("Rear_Grip_Pommel", grip_p0 - Vector((0, -0.008, 0.016)), grip_p0 + Vector((0, -0.004, 0.008)), 0.033, 0.034, m["forged_iron"], segments=8)

    b.beveled_box("Trigger_Lever", (0.0, -0.052, 0.022), (0.018, 0.024, 0.052), m["red_switch"], bevel=0.0045, rot_euler=(-0.22, 0.0, 0.0))
    b.beveled_box("Rear_Receiver_Frame", (0.0, 0.015, 0.078), (0.095, 0.145, 0.068), m["forged_iron"], bevel=0.0065)

    b.beveled_box("Stock_Bar", (0.0, 0.115, 0.082), (0.048, 0.115, 0.046), m["forged_iron"], bevel=0.0055)
    b.beveled_box("Stock_Canvas_Wrap", (0.0, 0.125, 0.082), (0.054, 0.058, 0.052), m["oatmeal_linen"], bevel=0.0045)
    b.beveled_box("Stock_Shoulder_Pad", (0.0, 0.182, 0.078), (0.068, 0.036, 0.135), m["dark_charcoal"], bevel=0.0085)

    # 2. Upper Slotted Rotary Blower / Turbine Drum
    b.cylinder_along("Turbine_Drum_Body", (0.0, 0.085, 0.188), (0.0, -0.075, 0.188), 0.088, 0.084, m["slate_olive"], segments=22, rings_between=2)
    b.cylinder_along("Turbine_Rear_Cone", (0.0, 0.112, 0.188), (0.0, 0.085, 0.188), 0.062, 0.088, m["forged_iron"], segments=22)
    for s_i in range(9):
        ang = -1.1 + 2.2 * (s_i / 8.0)
        sx = 0.086 * math.sin(ang)
        sz = 0.188 + 0.086 * math.cos(ang)
        b.beveled_box(
            f"Turbine_Vent_Slot_{s_i+1}",
            (sx, 0.032, sz),
            (0.014, 0.052, 0.010),
            m["dark_charcoal"],
            bevel=0.002,
            rot_euler=(0.0, ang, 0.0),
        )

    # 3. Concertina Pleated Oxhide Leather Bellows & Linen Strap (kept separate on export)
    bellows_rings = []
    folds = 5
    for f in range(folds * 2 + 1):
        t = f / float(folds * 2)
        y_pos = -0.055 - t * 0.315
        is_ridge = (f % 2 == 1)
        wx = (0.099 if is_ridge else 0.076) * (0.92 + 0.16 * t)
        wz = (0.097 if is_ridge else 0.074) * (0.90 + 0.18 * t)
        cz = 0.115 - 0.010 * t
        ring = []
        n_b = 16
        for i in range(n_b):
            ang = 2.0 * math.pi * i / n_b
            ca, sa = math.cos(ang), math.sin(ang)
            sx = math.copysign(abs(ca) ** 0.65, ca) * wx
            sz = math.copysign(abs(sa) ** 0.65, sa) * wz
            ring.append((sx, y_pos, cz + sz))
        bellows_rings.append(ring)
    b.loft("Leather_Bellows_Chamber", bellows_rings, m["oxhide_leather"], cap=True, smooth=False)

    strap_rings = []
    for y_s in (-0.155, -0.195):
        ring = []
        for i in range(16):
            ang = 2.0 * math.pi * i / 16
            ca, sa = math.cos(ang), math.sin(ang)
            sx = math.copysign(abs(ca) ** 0.65, ca) * 0.105
            sz = math.copysign(abs(sa) ** 0.65, sa) * 0.103
            ring.append((sx, y_s, 0.112 + sz))
        strap_rings.append(ring)
    b.loft("Bellows_Linen_Band", strap_rings, m["oatmeal_linen"], cap=True, smooth=False)

    # 4. Side Scissor Linkage Bars, Geared Pivot Hubs & Brass Pins
    for side_name, sign in (("Right", -1.0), ("Left", 1.0)):
        lx = sign * 0.112
        b.cylinder_along(
            f"Scissor_Linkage_Hub_{side_name}",
            (lx - sign * 0.015, -0.075, 0.088),
            (lx + sign * 0.018, -0.075, 0.088),
            0.044,
            0.044,
            m["forged_iron"],
            segments=16,
        )
        b.cylinder_along(
            f"Linkage_Hub_Brass_Pin_{side_name}",
            (lx, -0.075, 0.088),
            (lx + sign * 0.028, -0.075, 0.088),
            0.018,
            0.016,
            m["aged_brass"],
            segments=12,
        )
        b.beveled_box(
            f"Scissor_Upper_Bar_{side_name}",
            (lx, -0.055, 0.138),
            (0.020, 0.115, 0.028),
            m["forged_iron"],
            bevel=0.0045,
            rot_euler=(1.12, 0.0, 0.0),
        )
        b.beveled_box(
            f"Scissor_Lower_Bar_{side_name}",
            (lx, -0.225, 0.068),
            (0.022, 0.305, 0.030),
            m["forged_iron"],
            bevel=0.0045,
            rot_euler=(-0.13, 0.0, 0.0),
        )
        b.beveled_box(
            f"Top_Frame_Strut_{side_name}",
            (sign * 0.088, -0.215, 0.188),
            (0.022, 0.335, 0.024),
            m["forged_iron"],
            bevel=0.0045,
            rot_euler=(-0.15, 0.0, 0.0),
        )
        b.beveled_box(
            f"Front_Cheek_Plate_{side_name}",
            (lx, -0.375, 0.105),
            (0.024, 0.046, 0.155),
            m["forged_iron"],
            bevel=0.0055,
        )
        for rz in (0.048, 0.158):
            b.cylinder_along(
                f"Cheek_Brass_Pin_{side_name}_{rz:.2f}",
                (lx, -0.375, rz),
                (lx + sign * 0.018, -0.375, rz),
                0.012,
                0.011,
                m["aged_brass"],
                segments=10,
            )

    # 5. Forward Vertical Support Foregrip (Grip_L at (0.0, -0.37, -0.075))
    b.beveled_box("Foregrip_Mount_Block", (0.0, -0.37, 0.002), (0.088, 0.072, 0.028), m["forged_iron"], bevel=0.0045)
    fg_p0 = Vector((0.0, -0.37, -0.155))
    fg_p1 = Vector((0.0, -0.37, -0.005))
    b.cylinder_along("Foregrip_Leather_Body", fg_p0, fg_p1, 0.030, 0.031, m["oxhide_leather"], segments=16, rings_between=2)
    b.cylinder_along(
        "Foregrip_Linen_Wrap",
        fg_p0.lerp(fg_p1, 0.30),
        fg_p0.lerp(fg_p1, 0.68),
        0.033,
        0.033,
        m["oatmeal_linen"],
        segments=16,
    )
    b.cylinder_along("Foregrip_Hex_Base", fg_p0 - Vector((0, 0, 0.020)), fg_p0 + Vector((0, 0, 0.005)), 0.035, 0.035, m["forged_iron"], segments=6)

    # 6. Flared Rectangular Sheet-Metal Heater Hood, Brass Heat-Shield Baffle, Orange Coils & Grille
    def rect_ring(y_val, hx, hz, cz=0.105, c_bev=0.020):
        return [
            (-hx, y_val, cz - hz + c_bev),
            (-hx + c_bev, y_val, cz - hz),
            (hx - c_bev, y_val, cz - hz),
            (hx, y_val, cz - hz + c_bev),
            (hx, y_val, cz + hz - c_bev),
            (hx - c_bev, y_val, cz + hz),
            (-hx + c_bev, y_val, cz + hz),
            (-hx, y_val, cz + hz - c_bev),
        ]

    hood_rings = [
        rect_ring(-0.370, 0.108, 0.088),
        rect_ring(-0.420, 0.122, 0.096),
        rect_ring(-0.588, 0.169, 0.123),
        rect_ring(-0.598, 0.166, 0.120),
        rect_ring(-0.584, 0.154, 0.110),
        rect_ring(-0.455, 0.112, 0.086),
    ]
    b.loft("Flared_Heater_Hood", hood_rings, m["forged_iron"], cap=True, smooth=False)
    b.beveled_box("Hood_Throat_Reflector", (0.0, -0.468, 0.105), (0.228, 0.014, 0.176), m["dark_charcoal"], bevel=0.002)

    # Inner brass heat-shield baffle frame inside the flared mouth (working-end polish)
    baffle_rings = [
        rect_ring(-0.545, 0.148, 0.105, c_bev=0.014),
        rect_ring(-0.574, 0.155, 0.111, c_bev=0.014),
        rect_ring(-0.574, 0.146, 0.103, c_bev=0.014),
        rect_ring(-0.545, 0.140, 0.098, c_bev=0.014),
    ]
    b.loft("Hood_Brass_Baffle", baffle_rings, m["aged_brass"], cap=False, smooth=False, closed_loop=True)

    for c_idx, cz in enumerate((0.052, 0.105, 0.158)):
        b.cylinder_along(
            f"Heater_Ceramic_Core_{c_idx+1}",
            (-0.132, -0.525, cz),
            (0.132, -0.525, cz),
            0.011,
            0.011,
            m["porcelain_ivory"],
            segments=10,
        )
        for k in range(9):
            kx0 = -0.116 + k * 0.026
            kx1 = kx0 + 0.018
            b.cylinder_along(
                f"Heater_Orange_Coil_{c_idx+1}_{k+1}",
                (kx0, -0.525, cz),
                (kx1, -0.525, cz),
                0.0195,
                0.0195,
                m["accent_orange"],
                segments=12,
            )

    for g_idx, gz in enumerate((0.025, 0.065, 0.105, 0.145, 0.185)):
        b.cylinder_along(
            f"Grille_Horiz_Bar_{g_idx+1}",
            (-0.156, -0.578, gz),
            (0.156, -0.578, gz),
            0.0048,
            0.0048,
            m["forged_iron"],
            segments=8,
        )
    for v_idx, vx in enumerate((-0.078, 0.0, 0.078)):
        b.cylinder_along(
            f"Grille_Vert_Bar_{v_idx+1}",
            (vx, -0.581, 0.002),
            (vx, -0.581, 0.208),
            0.0048,
            0.0048,
            m["forged_iron"],
            segments=8,
        )


def build_time_device(b: PropBuilder, m: dict):
    """4. Time Device / Clock (art/current-ideas/metronome-tape-clock-concept.png)."""
    cx = 0.115
    b.add_empty("Grip_R", (0.0, 0.0, 0.0))
    b.add_empty("Grip_L", (0.23, -0.01, 0.0))
    b.add_empty("Emitter", (cx, -0.095, 0.075))

    # 1. Lower Wooden & Slate-Teal Cassette Base Box
    b.beveled_box("Clock_Lower_Wood_Case", (cx, 0.0, 0.0), (0.215, 0.155, 0.135), m["weathered_walnut"], bevel=0.0075)
    b.beveled_box("Clock_Front_Slate_Plate", (cx, -0.074, 0.0), (0.192, 0.018, 0.115), m["slate_olive"], bevel=0.0045)
    b.beveled_box("Clock_Tape_Window_Recess", (cx + 0.018, -0.080, 0.002), (0.118, 0.012, 0.064), m["dark_charcoal"], bevel=0.003)
    b.beveled_box("Clock_Tape_Window_Bezel", (cx + 0.018, -0.083, 0.002), (0.124, 0.006, 0.070), m["brushed_steel"], bevel=0.002)

    for fx in (cx - 0.078, cx + 0.078):
        for fy in (-0.052, 0.052):
            b.cylinder_along(f"Clock_Foot_{fx:.2f}_{fy:.2f}", (fx, fy, -0.076), (fx, fy, -0.064), 0.014, 0.016, m["dark_charcoal"], segments=12)

    for r_i, rx in enumerate((cx - 0.012, cx + 0.048)):
        b.cylinder_along(f"Clock_Reel_Pack_{r_i+1}", (rx, -0.076, 0.002), (rx, -0.085, 0.002), 0.024, 0.024, m["oxhide_leather"], segments=16)
        b.cylinder_along(f"Clock_Reel_Hub_{r_i+1}", (rx, -0.078, 0.002), (rx, -0.088, 0.002), 0.012, 0.012, m["porcelain_ivory"], segments=12)
        b.cylinder_along(f"Clock_Reel_Core_{r_i+1}", (rx, -0.080, 0.002), (rx, -0.090, 0.002), 0.005, 0.005, m["dark_charcoal"], segments=10)

    b.beveled_box("Clock_Fader_Frame", (cx - 0.066, -0.080, 0.002), (0.036, 0.014, 0.096), m["slate_olive"], bevel=0.0035)
    b.beveled_box("Clock_Fader_Slot", (cx - 0.066, -0.084, 0.002), (0.008, 0.010, 0.072), m["dark_charcoal"], bevel=0.001)
    b.beveled_box("Clock_Fader_Knob", (cx - 0.066, -0.090, 0.022), (0.024, 0.018, 0.018), m["brushed_steel"], bevel=0.0035)

    tape_pts = [
        (cx - 0.025, -0.086, -0.015),
        (cx - 0.055, -0.092, -0.048),
        (cx + 0.005, -0.094, -0.058),
        (cx + 0.055, -0.092, -0.045),
        (cx + 0.035, -0.086, -0.015),
    ]
    b.tube_curve("Clock_Tape_Ribbon", tape_pts, 0.005, m["oxhide_leather"], segments=8, flatten=0.35, up_hint=(0, 1, 0))

    # 2. Upper Truncated Pyramidal Metronome Tower with Base Plinth & Tapered Flush Violet Face
    b.beveled_box("Metronome_Base_Moulding", (cx + 0.019, 0.0, 0.068), (0.166, 0.144, 0.012), m["aged_brass"], bevel=0.003)
    pyr_rings = [
        [
            (cx - 0.058, -0.068, 0.066),
            (cx + 0.096, -0.068, 0.066),
            (cx + 0.096, 0.068, 0.066),
            (cx - 0.058, 0.068, 0.066),
        ],
        [
            (cx - 0.016, -0.038, 0.245),
            (cx + 0.054, -0.038, 0.245),
            (cx + 0.054, 0.038, 0.245),
            (cx - 0.016, 0.038, 0.245),
        ],
    ]
    b.loft("Metronome_Wood_Pyramid", pyr_rings, m["weathered_walnut"], cap=True, smooth=False)
    b.beveled_box("Metronome_Top_Cap", (cx + 0.019, 0.0, 0.250), (0.076, 0.082, 0.016), m["weathered_walnut"], bevel=0.0045)

    face_rings = [
        [
            (cx - 0.038, -0.071, 0.074),
            (cx + 0.076, -0.071, 0.074),
            (cx + 0.076, -0.062, 0.074),
            (cx - 0.038, -0.062, 0.074),
        ],
        [
            (cx - 0.004, -0.043, 0.236),
            (cx + 0.042, -0.043, 0.236),
            (cx + 0.042, -0.034, 0.236),
            (cx - 0.004, -0.034, 0.236),
        ],
    ]
    b.loft("Metronome_Violet_Face", face_rings, m["accent_violet"], cap=True, smooth=False)
    b.beveled_box(
        "Metronome_Scale_Bar",
        (cx + 0.019, -0.059, 0.155),
        (0.016, 0.009, 0.148),
        m["aged_brass"],
        bevel=0.002,
        rot_euler=(-0.168, 0.0, 0.0),
    )
    # Graduated brass tempo tick marks across the scale bar
    for t_i in range(5):
        tz = 0.095 + t_i * 0.030
        ty = -0.069 + (tz - 0.074) * 0.172
        b.beveled_box(f"Metronome_Tick_{t_i+1}", (cx + 0.019, ty, tz), (0.032, 0.006, 0.004), m["aged_brass"], bevel=0.001)

    b.cylinder_along(
        "Metronome_Pendulum_Rod",
        (cx + 0.019, -0.068, 0.078),
        (cx + 0.072, -0.095, 0.215),
        0.004,
        0.0035,
        m["brushed_steel"],
        segments=8,
    )
    b.beveled_box(
        "Metronome_Pendulum_Weight",
        (cx + 0.055, -0.088, 0.175),
        (0.022, 0.016, 0.028),
        m["aged_brass"],
        bevel=0.0035,
        rot_euler=(-0.18, -0.36, 0.0),
    )

    # 3. Side Hourglass Capsule on Right Shoulder (-X relative to cx in Blender)
    hx, hy = cx - 0.062, 0.0
    b.cylinder_along("Hourglass_Bot_Cap", (hx, hy, 0.072), (hx, hy, 0.088), 0.032, 0.032, m["aged_brass"], segments=16)
    b.cylinder_along("Hourglass_Top_Cap", (hx, hy, 0.205), (hx, hy, 0.222), 0.032, 0.032, m["aged_brass"], segments=16)
    for p_i in range(3):
        pang = 2.0 * math.pi * p_i / 3.0 + 0.4
        px = hx + 0.026 * math.cos(pang)
        py = hy + 0.026 * math.sin(pang)
        b.cylinder_along(f"Hourglass_Pillar_{p_i+1}", (px, py, 0.086), (px, py, 0.207), 0.0035, 0.0035, m["aged_brass"], segments=8)
    hg_profile = [
        (0.088, 0.022),
        (0.108, 0.0245),
        (0.132, 0.016),
        (0.146, 0.0055),
        (0.160, 0.016),
        (0.184, 0.0245),
        (0.205, 0.022),
    ]
    hg_rings = [
        [(hx + rad * math.cos(2.0 * math.pi * i / 18), hy + rad * math.sin(2.0 * math.pi * i / 18), hz) for i in range(18)]
        for hz, rad in hg_profile
    ]
    b.loft("Hourglass_Violet_Bulbs", hg_rings, m["accent_violet"], cap=True, smooth=True)

    # 4. Left Side Brass Winding Key & Untwisted Leather Hand Strap + Right Grip Handle
    b.cylinder_along("Winding_Key_Shaft", (cx + 0.105, 0.0, 0.028), (cx + 0.142, 0.0, 0.028), 0.012, 0.009, m["aged_brass"], segments=12)
    for wing_z in (-0.020, 0.020):
        b.cylinder_along(
            f"Winding_Key_Wing_{wing_z:.2f}",
            (cx + 0.138, -0.006, 0.028 + wing_z),
            (cx + 0.148, 0.006, 0.028 + wing_z),
            0.014,
            0.014,
            m["aged_brass"],
            segments=12,
        )
    strap_pts = [
        (cx + 0.106, -0.01, 0.016),
        (cx + 0.128, -0.01, -0.008),
        (cx + 0.132, -0.01, -0.036),
        (cx + 0.122, -0.01, -0.056),
        (cx + 0.106, -0.01, -0.060),
    ]
    b.tube_curve("Left_Leather_Strap", strap_pts, 0.010, m["oxhide_leather"], segments=10, flatten=0.45, up_hint=(0, 1, 0))
    b.cylinder_along("Right_Grip_Handle", (0.0, 0.0, -0.052), (0.0, 0.0, 0.048), 0.018, 0.018, m["oxhide_leather"], segments=14)


def setup_studio_and_render(prop_name: str, prop_coll, mats: dict, views: list):
    studio = bpy.data.collections.new("REVIEW STUDIO | excluded from GLB")
    bpy.context.scene.collection.children.link(studio)
    b_studio = PropBuilder(studio, mats)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = False
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.world.color = (0.16, 0.17, 0.18)

    ground_mat = bpy.data.materials.new("Studio | charcoal floor")
    ground_mat.use_nodes = True
    bsdf = ground_mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.05, 0.055, 0.06, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.88
    b_studio.add_mesh(
        "Studio_Floor",
        [(-50, -50, -0.32), (50, -50, -0.32), (50, 50, -0.32), (-50, 50, -0.32)],
        [(0, 1, 2, 3)],
        ground_mat,
    )

    def add_area_light(lname, pos, target, power, size):
        ldata = bpy.data.lights.new(lname, "AREA")
        ldata.energy = power
        ldata.shape = "DISK"
        ldata.size = size
        lobj = bpy.data.objects.new(lname, ldata)
        studio.objects.link(lobj)
        lobj.location = Vector(pos)
        lobj.rotation_euler = (Vector(target) - lobj.location).to_track_quat("-Z", "Y").to_euler()

    center = views[0]["target"]
    add_area_light("Key_Light", (-1.8, -2.4, 2.6), center, 165.0, 2.2)
    add_area_light("Fill_Light", (2.2, -1.5, 1.6), center, 95.0, 2.0)
    add_area_light("Rim_Light", (0.6, 2.4, 2.2), center, 195.0, 1.8)

    cam_data = bpy.data.cameras.new("Review_Camera")
    cam_obj = bpy.data.objects.new("Review_Camera", cam_data)
    studio.objects.link(cam_obj)
    cam_data.type = "ORTHO"
    scene.camera = cam_obj

    for ob in studio.objects:
        ob.hide_set(True)
    blend_path = SRC_DIR / f"{prop_name}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    for ob in studio.objects:
        ob.hide_set(False)

    rendered_files = []
    for v in views:
        cam_data.ortho_scale = v["ortho_scale"]
        cam_obj.location = Vector(v["pos"])
        cam_obj.rotation_euler = (Vector(v["target"]) - cam_obj.location).to_track_quat("-Z", "Y").to_euler()
        out_file = OUT_ROUND_J / f"{prop_name}-{v['suffix']}.png"
        scene.render.filepath = str(out_file)
        bpy.ops.render.render(write_still=True)
        # Copy to art-i as well
        (OUT_ART_I / f"{prop_name}-{v['suffix']}.png").write_bytes(out_file.read_bytes())
        rendered_files.append(str(out_file))
        print("EQUIPMENT_RENDER", prop_name, v["suffix"], flush=True)

    return blend_path, rendered_files


DYNAMIC_GROUPS = {
    "ring_caster": {
        "Suspended_Saw_Ring": ("Suspended_Saw_Ring", "Suspended_Saw_Ring_Collar"),
        "Handwheel_Crank": ("Handwheel_Shaft", "Handwheel_Rim", "Handwheel_Spoke_"),
    },
    "flash_camera": {
        "Accordion_Bellows": ("Accordion_Bellows",),
        "Lens_Glass_Element": ("Lens_Glass_Element",),
    },
    "heat_bellows": {
        "Leather_Bellows_Chamber": ("Leather_Bellows_Chamber",),
        "Bellows_Linen_Band": ("Bellows_Linen_Band",),
        "Bellows_Scissor_Linkage": ("Scissor_Linkage_Hub_", "Scissor_Upper_Bar_", "Scissor_Lower_Bar_"),
    },
    "time_device": {
        "Metronome_Pendulum_Rod": ("Metronome_Pendulum_Rod",),
        "Metronome_Pendulum_Weight": ("Metronome_Pendulum_Weight",),
        "Hourglass_Violet_Bulbs": ("Hourglass_Violet_Bulbs",),
        "Metronome_Violet_Face": ("Metronome_Violet_Face",),
    },
}


def classify_export_group(prop_name: str, obj, orig_name: str) -> str:
    for group_name, prefixes in DYNAMIC_GROUPS.get(prop_name, {}).items():
        for pref in prefixes:
            if orig_name == pref or orig_name.startswith(pref):
                return group_name
    mat_name = obj.data.materials[0].name if obj.data.materials else "01 | forged iron"
    mat_slug = mat_name.split("|")[-1].strip().title().replace(" ", "_")
    return f"{prop_name.title().replace('_', '')}_{mat_slug}"


def export_consolidated_glb_with_identity_root(prop_name: str, prop_coll) -> dict:
    """Consolidate static meshes by material while keeping dynamic parts separate; keep .blend editable."""
    rot_z180 = Matrix.Rotation(math.pi, 4, "Z")
    export_coll = bpy.data.collections.new("TEMP_GLB_EXPORT")
    bpy.context.scene.collection.children.link(export_coll)

    orig_obj_names = {}
    orig_mesh_names = {}
    for ob in prop_coll.objects:
        orig_obj_names[ob] = ob.name
        ob.name = f"__src__{ob.name}"
        if ob.type == "MESH" and ob.data and ob.data not in orig_mesh_names:
            orig_mesh_names[ob.data] = ob.data.name
            ob.data.name = f"__src__{ob.data.name}"

    grouped_meshes = {}
    source_mesh_count = 0
    sockets_blender = {}
    sockets_godot = {}
    temp_objects = []
    temp_meshes = []

    for ob in prop_coll.objects:
        orig_name = orig_obj_names[ob]
        if ob.type == "MESH":
            source_mesh_count += 1
            gname = classify_export_group(prop_name, ob, orig_name)
            grouped_meshes.setdefault(gname, []).append(ob)
        elif ob.type == "EMPTY":
            loc = ob.location
            sockets_blender[orig_name] = [round(loc.x, 4), round(loc.y, 4), round(loc.z, 4)]
            sockets_godot[orig_name] = [round(-loc.x, 4), round(loc.z, 4), round(loc.y, 4)]
            emp = bpy.data.objects.new(orig_name, None)
            emp.empty_display_type = "PLAIN_AXES"
            emp.empty_display_size = 0.06
            emp.location = Vector((-loc.x, -loc.y, loc.z))
            emp.rotation_euler = (0.0, 0.0, 0.0)
            export_coll.objects.link(emp)
            temp_objects.append(emp)

    triangles = 0
    vertices = 0
    used_mats = set()
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))

    for gname, obj_list in sorted(grouped_meshes.items()):
        bm = bmesh.new()
        mat = obj_list[0].data.materials[0]
        used_mats.add(mat.name)
        for src_ob in obj_list:
            me = src_ob.data
            for v in me.vertices:
                p = src_ob.matrix_world @ v.co
                for i in range(3):
                    mins[i] = min(mins[i], p[i])
                    maxs[i] = max(maxs[i], p[i])
            bm_part = bmesh.new()
            bm_part.from_mesh(me)
            bmesh.ops.transform(bm_part, matrix=rot_z180 @ src_ob.matrix_world, verts=bm_part.verts)
            # Append into combined bmesh preserving face smoothness
            vert_offset = len(bm.verts)
            for v in bm_part.verts:
                bm.verts.new(v.co)
            bm.verts.ensure_lookup_table()
            for f in bm_part.faces:
                new_f = bm.faces.new([bm.verts[vert_offset + v.index] for v in f.verts])
                new_f.smooth = f.smooth
            bm_part.free()

        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        comb_data = bpy.data.meshes.new(gname)
        bm.to_mesh(comb_data)
        bm.free()
        comb_data.materials.append(mat)
        comb_data.update()
        comb_data.calc_loop_triangles()
        triangles += len(comb_data.loop_triangles)
        vertices += len(comb_data.vertices)

        comb_obj = bpy.data.objects.new(gname, comb_data)
        comb_obj.location = (0.0, 0.0, 0.0)
        comb_obj.rotation_euler = (0.0, 0.0, 0.0)
        export_coll.objects.link(comb_obj)
        temp_objects.append(comb_obj)
        temp_meshes.append(comb_data)

    bpy.ops.object.select_all(action="DESELECT")
    for tob in temp_objects:
        tob.select_set(True)
    bpy.context.view_layer.objects.active = temp_objects[0]

    glb_path = ASSET_DIR / f"{prop_name}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
        export_extras=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )

    exported_mesh_names = [tob.name for tob in temp_objects if tob.type == "MESH"]

    # Clean up temporary consolidated export objects so .blend stays 100% unmerged and editable
    for tob in temp_objects:
        bpy.data.objects.remove(tob, do_unlink=True)
    for tme in temp_meshes:
        bpy.data.meshes.remove(tme, do_unlink=True)
    bpy.data.collections.remove(export_coll)

    for ob, oname in orig_obj_names.items():
        ob.name = oname
    for me, mname in orig_mesh_names.items():
        me.name = mname

    return {
        "prop": prop_name,
        "glb": str(glb_path),
        "source_editable_mesh_objects": source_mesh_count,
        "exported_glb_mesh_objects": len(exported_mesh_names),
        "exported_glb_mesh_names": exported_mesh_names,
        "vertices": vertices,
        "triangles": triangles,
        "materials": len(used_mats),
        "material_names": sorted(used_mats),
        "bounds_min_blender_m": [round(v, 4) for v in mins],
        "bounds_max_blender_m": [round(v, 4) for v in maxs],
        "dimensions_m": [round(v, 4) for v in (maxs - mins)],
        "sockets_blender_m": sockets_blender,
        "sockets_godot_m": sockets_godot,
    }


def build_single_prop(prop_name: str, builder_fn, views: list):
    blend_existing = SRC_DIR / f"{prop_name}.blend"
    if blend_existing.is_file():
        bpy.ops.wm.open_mainfile(filepath=str(blend_existing))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)

    bpy.context.preferences.filepaths.save_version = 0
    prop_coll = bpy.data.collections.new(f"EQUIPMENT | {prop_name}")
    bpy.context.scene.collection.children.link(prop_coll)
    mats = make_palette()
    builder = PropBuilder(prop_coll, mats)

    builder_fn(builder, mats)
    stats = export_consolidated_glb_with_identity_root(prop_name, prop_coll)
    blend_path, renders = setup_studio_and_render(prop_name, prop_coll, mats, views)
    stats["blend"] = str(blend_path)
    stats["renders"] = renders
    return stats


def main():
    prop_configs = [
        (
            "ring_caster",
            build_ring_caster,
            [
                {"suffix": "angle1", "pos": (-1.45, -1.55, 1.25), "target": (0.0, -0.26, 0.03), "ortho_scale": 0.92},
                {"suffix": "angle2", "pos": (1.55, 1.25, 1.05), "target": (0.0, -0.26, 0.03), "ortho_scale": 0.92},
            ],
        ),
        (
            "flash_camera",
            build_flash_camera,
            [
                {"suffix": "angle1", "pos": (-1.35, -1.65, 1.05), "target": (0.21, -0.14, 0.03), "ortho_scale": 0.72},
                {"suffix": "angle2", "pos": (1.75, 1.35, 0.95), "target": (0.21, -0.14, 0.03), "ortho_scale": 0.72},
            ],
        ),
        (
            "heat_bellows",
            build_heat_bellows,
            [
                {"suffix": "angle1", "pos": (-1.55, -1.45, 0.95), "target": (0.0, -0.24, 0.07), "ortho_scale": 0.88},
                {"suffix": "angle2", "pos": (1.55, 1.25, 0.95), "target": (0.0, -0.24, 0.07), "ortho_scale": 0.88},
            ],
        ),
        (
            "time_device",
            build_time_device,
            [
                {"suffix": "angle1", "pos": (-1.15, -1.65, 0.85), "target": (0.115, -0.01, 0.08), "ortho_scale": 0.48},
                {"suffix": "angle2", "pos": (1.45, 1.25, 0.85), "target": (0.115, -0.01, 0.08), "ortho_scale": 0.48},
            ],
        ),
    ]

    all_stats = {}
    for prop_name, fn, views in prop_configs:
        all_stats[prop_name] = build_single_prop(prop_name, fn, views)

    stats_text = json.dumps(all_stats, indent=2) + "\n"
    (OUT_ROUND_J / "blender-stats.json").write_text(stats_text)
    (OUT_ART_I / "blender-stats.json").write_text(stats_text)
    print("ALL_EQUIPMENT_STATS", json.dumps(all_stats), flush=True)


if __name__ == "__main__":
    main()
