"""Editable False Face sculpture, deform rig and explicitly selected GLB export.

Run with the project background blender.py. Existing manually edited .blend
files are protected by a hash receipt; open those directly instead of rebuilding.
"""
import bpy
import bmesh
import math
import os
import json
import hashlib
from pathlib import Path
from mathutils import Vector

ROOT = Path(os.environ['JAM_REPO'])
SOURCE = ROOT / 'art-source/enemies/false_face'
STATE = Path(os.environ['JAM_STATE_ROOT']) / 'exports/round-j'
PASS = json.loads((SOURCE / 'iteration.json').read_text())['pass']
OUT = STATE / f'pass-{PASS}'
OUT.mkdir(parents=True, exist_ok=True)
BLEND = SOURCE / 'false_face.blend'
GLB = ROOT / 'assets/enemies/false_face/false_face.glb'
STAMP = STATE / 'generated-source.json'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
if BLEND.exists() and (not STAMP.exists() or digest(BLEND) != json.loads(STAMP.read_text())['blend_sha256']):
    raise RuntimeError('Source has manual edits or no generation receipt; open/edit the .blend, do not rebuild over it.')
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
COL = bpy.data.collections.new('FALSE FACE | editable sculpture and rig')
bpy.context.scene.collection.children.link(COL)
groups = {}


def material(name, color, metallic=0, rough=.8, glow=0):
    rgb = [int(color[i:i+2], 16)/255 for i in (0, 2, 4)]
    rgb = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Roughness'].default_value = rough
    p.inputs['Emission Color'].default_value = (*rgb, 1)
    p.inputs['Emission Strength'].default_value = glow
    return m


skin = material('Pale wax / violet shadows', 'B6AAA3')
linen = material('Old ivory linen', 'C7B99B')
seam = material('Wrap edges / dirt', '776C59')
leather = material('Worn umber leather', '594331')
metal = material('Oxidized iron', '53575B', .65, .57)
edge = material('Polished hardware edges', '96917C', .65, .43)
orange = material('TARGET orange / enamel shield', 'E77927', .3, .6)
dark = material('Recesses', '282A2D')
blue = material('TARGET blue / exposed conduit', '237FF0', .16, .35, .35)
yellow = material('TARGET yellow / exposed core', 'FFD139', .32, .3, .45)


def mesh(name, verts, faces, mat, bone, group='Body', smooth=True, weights=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    bm = bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data); bm.free()
    for p in data.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, data); COL.objects.link(ob)
    data.materials.append(mat)
    if weights:
        for i, ws in enumerate(weights):
            for key, value in ws.items():
                vg = ob.vertex_groups.get(key) or ob.vertex_groups.new(name=key)
                vg.add([i], value, 'REPLACE')
    else:
        vg = ob.vertex_groups.new(name=bone)
        vg.add(list(range(len(verts))), 1, 'REPLACE')
    groups.setdefault(group, []).append(ob)
    return ob


def loft(name, rows, mat, bone, group='Body', weights=None, smooth=True):
    n = len(rows[0]); count = len(rows)
    faces = [(j*n+i, j*n+(i+1)%n, (j+1)*n+(i+1)%n, (j+1)*n+i)
             for j in range(count-1) for i in range(n)]
    faces += [tuple(reversed(range(n))), tuple(range((count-1)*n, count*n))]
    return mesh(name, [v for r in rows for v in r], faces, mat, bone, group, smooth,
                [w for row in weights for w in [row]*n] if weights else None)


def tube(name, points, radii, mat, bone, group='Body', n=12, flatten=1, weights=None):
    ps = list(map(Vector, points)); rows = []
    for j, p in enumerate(ps):
        axis = (ps[min(j+1,len(ps)-1)]-ps[max(j-1,0)]).normalized()
        ref = Vector((0,1,0)) if abs(axis.y) < .9 else Vector((1,0,0))
        u = axis.cross(ref).normalized(); v = axis.cross(u).normalized()
        rows.append([p+radii[j]*(u*math.cos(i*math.tau/n)+v*flatten*math.sin(i*math.tau/n)) for i in range(n)])
    return loft(name, rows, mat, bone, group, weights)


def ellipse(name, center, scale, mat, bone, group='Body', n=20, rings=10):
    rows = []
    for j in range(rings+1):
        a = .01+(math.pi-.02)*j/rings
        rows.append([(center[0]+scale[0]*math.sin(a)*math.cos(i*math.tau/n),
                      center[1]+scale[1]*math.sin(a)*math.sin(i*math.tau/n),
                      center[2]+scale[2]*math.cos(a)) for i in range(n)])
    return loft(name, rows, mat, bone, group)


def ribbon(name, points, width, mat, bone, group='Cloth'):
    rows = []
    for j, p in enumerate(map(Vector, points)):
        t = Vector(points[min(j+1,len(points)-1)])-Vector(points[max(j-1,0)])
        u = Vector((t.z,0,-t.x)).normalized()*width/2
        rows.append([p-u,p+u,p+u+Vector((0,.012,0)),p-u+Vector((0,.012,0))])
    return loft(name, rows, mat, bone, group, smooth=False)


def band(name, cx, cy, z, rx, ry, width, mat, bone, group='Cloth', tilt=0):
    rows = []
    for dz in [-width/2, width/2]:
        rows.append([(cx+rx*math.cos(i*math.tau/32), cy+ry*math.sin(i*math.tau/32),
                      z+dz+tilt*math.cos(i*math.tau/32)) for i in range(32)])
    return loft(name, rows, mat, bone, group)


def disk(name, center, rx, rz, depth, mat, bone, group, bevel=.04):
    # Front/back rings and a convex face; front is Blender -Y.
    x,y,z = center; rows=[]
    for sy, factor in [(depth/2,.94),(depth*.3,1),(-depth*.25,1),(-depth/2,.94)]:
        rows.append([(x+rx*factor*math.cos(i*math.tau/40),y+sy,z+rz*factor*math.sin(i*math.tau/40)) for i in range(40)])
    return loft(name, rows, mat, bone, group, smooth=False)


# Lean torso: narrow waist, angled ribcage and raised scapulae, slumped neck.
sections = [(1.00,0,.04,.21,.15),(1.13,0,.06,.23,.16),(1.29,0,.05,.19,.13),
            (1.46,0,.04,.25,.17),(1.64,0,0,.34,.20),(1.78,0,.00,.38,.18),
            (1.89,0,-.02,.30,.14),(1.97,0,-.10,.13,.11)]
rows=[[(x+rx*math.cos(i*math.tau/24),y+ry*math.sin(i*math.tau/24),z) for i in range(24)] for z,x,y,rx,ry in sections]
loft('Continuous tapered ribcage',rows,skin,'chest',weights=[{'pelvis':1},{'pelvis':.8,'chest':.2},{'pelvis':.5,'chest':.5},{'pelvis':.2,'chest':.8}]+[{'chest':1}]*4)
ellipse('Wrapped bowed skull',(0,-.22,1.93),(.205,.21,.25),linen,'head','Cloth')
ellipse('Jaw beneath bindings',(0,-.34,1.79),(.13,.11,.11),skin,'head')
tube('Neck',[(0,-.08,1.84),(0,-.17,1.97)],[.13,.12],skin,'head')

# One continuous loft down each limb; joint rings blend adjacent bones.
for s, side in [(-1,'R'),(1,'L')]:
    shoulder=(s*.34,0,1.78); elbow=(s*.54,-.04,1.32); wrist=(s*.66,-.22,.88)
    points=[shoulder,(s*.43,.01,1.67),(s*.51,-.02,1.44),elbow,(s*.59,-.10,1.17),(s*.64,-.18,.98),wrist]
    up='upper_arm.'+side; low='forearm.'+side; hand='hand.'+side
    tube('Long arm '+side,points,[.145,.15,.11,.095,.12,.085,.07],skin,up,weights=[{up:1},{up:1},{up:.8,low:.2},{up:.45,low:.55},{low:1},{low:.8,hand:.2},{hand:1}])
    ellipse('Deltoid '+side,shoulder,(.16,.16,.18),skin,up)
    ellipse('Long palm '+side,(s*.68,-.25,.73),(.125,.095,.19),skin,hand)
    # Four articulated fingers with daylight between them and opposed thumb.
    for i in range(4):
        x=s*(.59+i*.060); z=.64+(.025 if i in [0,3] else 0)
        tube('Finger '+side+str(i),[(x,-.27,z),(x+s*.008,-.30,z-.12),(x,-.36,z-.18),(x-s*.008,-.38,z-.17)],
             [.033,.034,.027,.019],skin,hand,n=8)
        if PASS>=2:
            ellipse('Knuckle '+side+str(i),(x,-.31,z-.035),(.035,.023,.038),skin,hand,n=10,rings=5)
    tube('Opposed thumb '+side,[(s*.58,-.25,.79),(s*.51,-.30,.71),(s*.50,-.38,.65)],[.052,.042,.026],skin,hand,n=10)
    hip=(s*.16,.04,1.08); knee=(s*.28,-.18,.65); ankle=(s*.29,.01,.18)
    thigh='thigh.'+side; shin='shin.'+side; foot='foot.'+side
    tube('Bent leg '+side,[hip,(s*.22,-.04,.94),(s*.26,-.15,.75),knee,(s*.29,-.09,.51),(s*.29,0,.30),ankle],
         [.15,.16,.12,.115,.105,.07,.065],skin,thigh,weights=[{thigh:1},{thigh:1},{thigh:.8,shin:.2},{thigh:.45,shin:.55},{shin:1},{shin:.85,foot:.15},{foot:1}])
    if PASS < 3:
        ellipse('Patella '+side,(s*.28,-.27,.65),(.08,.045,.09),skin,shin)
    ellipse('Foot '+side,(s*.30,-.13,.11),(.115,.23,.10),skin,foot)
    for i in range(4):
        ellipse('Toe '+side+str(i),(s*(.225+i*.048),-.33,.085),(.028,.07,.045),skin,foot,n=10,rings=6)
    band('Ankle brace '+side,s*.29,.01,.23,.082,.087,.10,leather,shin,'Harness')
    band('Wrist brace '+side,s*.65,-.20,.94,.092,.097,.09,leather,low,'Harness',tilt=s*.025)
    if PASS>=2:
        for k in range(4):
            band('Calf linen '+side+str(k),s*.29,-.035,.31+k*.045,.087+k*.004,.092+k*.004,.052,linen,shin,tilt=.015*(-1)**k)
        band('Arm wrap '+side,s*.56,-.07,1.27,.112,.12,.115,linen,low,tilt=s*.035)
    if PASS>=3:
        for k in range(3):
            band('Forearm binding '+side+str(k),s*(.59+k*.018),-.11-k*.035,1.15-k*.060,.108-k*.01,.112-k*.012,.035,linen,low,tilt=s*.025)

# Tattered loincloth, shoulder harness and cinched waist.
band('Waist belt',0,.04,1.13,.242,.181,.09,leather,'pelvis','Harness')
for s in [-1,1]:
    ribbon('Shoulder sling '+str(s),[(s*.15,-.16,1.22),(s*.24,-.19,1.57),(s*.27,-.15,1.80),(s*.28,.05,1.92),(s*.23,.20,1.64),(s*.15,.19,1.20)],.065,leather,'chest','Harness')
    for z in [1.50,1.76]:
        disk('Harness rivet',(s*.24,-.205,z),.025,.025,.02,edge,'chest','Hardware')
for i in range(7):
    x=(i-3)*.062; bottom=.77+.07*math.sin(i*2.1)
    ob=mesh('Torn linen tab '+str(i),[(x-.04,-.15,1.11),(x+.04,-.15,1.11),(x+.045,-.18,bottom+.06),(x+.012,-.20,bottom),(x-.04,-.18,bottom+.03)],[(0,1,2,3,4)],linen,'pelvis','Cloth',False)
    sol=ob.modifiers.new('Cloth thickness','SOLIDIFY'); sol.thickness=.008
if PASS>=2:
    for k in range(6):
        band('Cranial diagonal binding '+str(k),0,-.22,1.78+k*.057,.209*math.sqrt(max(.12,1-((1.78+k*.057-1.93)/.26)**2)),.215*math.sqrt(max(.12,1-((1.78+k*.057-1.93)/.26)**2)),.048,linen if k%2 else seam,'head',tilt=.04*(-1)**k)
    ribbon('Crown binding',[(-.17,-.28,1.84),(-.14,-.26,2.09),(0,-.22,2.185),(.15,-.20,2.08),(.19,-.18,1.86)],.065,linen,'head')
    for s in [-1,1]:
        for k in range(3):
            tube('Rib ridge',[(s*.10,-.133,1.38+k*.09),(s*.22,-.14,1.42+k*.09),(s*.29,-.08,1.47+k*.09)],[.014,.016,.008],skin,'chest',n=6)
if PASS>=3:
    for s in [-1,1]:
        ellipse('Scapular plane '+str(s),(s*.19,.135,1.73),(.125,.075,.16),skin,'chest')
        ribbon('Scapular harness stitch '+str(s),[(s*.20,.204,1.48),(s*.245,.213,1.66),(s*.27,.168,1.81)],.014,seam,'chest','Harness')

# Mechanical target parts. Core remains under head; shield covers it from front.
disk('Core iron collar',(0,-.405,1.75),.185,.185,.08,metal,'head','Hardware')
disk('Core brass lip',(0,-.455,1.75),.145,.145,.045,edge,'head','Hardware')
disk('Yellow aperture',(0,-.49,1.75),.116,.116,.025,yellow,'head','Core_Yellow')
disk('Core central pupil',(0,-.51,1.75),.033,.033,.014,orange,'head','Hardware')
# Last pass increases the exposed conduit length and lowers the shield just enough
# to read the head/shoulder gap at the prescribed steep gameplay camera pitch.
front = -1.10 if PASS>=3 else -.93
shield_z = 1.32 if PASS>=3 else 1.43
disk('Shield iron rim',(0,front,shield_z),.61,.79,.12,metal,'shield','Shield_Rim')
disk('Orange enamel shield',(0,front-.07,shield_z),.565,.745,.07,orange,'shield','Shield_Orange')
tube('Blue exposed flex conduit',[(0,-.48,1.47),(.055,-.63,1.43),(.055,front+.20,shield_z+.04),(0,front+.08,shield_z)],
     [.085,.088,.09,.09],blue,'conduit','Cable_Blue',n=16)
for y,z in [(-.48,1.47),(front+.09,shield_z)]:
    disk('Conduit coupling',(0,y,z),.125,.125,.075,metal,'head' if y==-.48 else 'shield','Hardware')
for s in [-1,1]:
    for dz in [-.42,.42]:
        x=s*.48
        ribbon('Shield clamp',[(x-s*.05,front-.12,shield_z+dz-.075),(x+s*.04,front-.14,shield_z+dz-.075),(x+s*.07,front+.07,shield_z+dz-.075)],.075,edge,'shield','Shield_Rim')
        disk('Shield rivet',(x,front-.125,shield_z+dz),.028,.028,.026,metal,'shield','Shield_Rim')
if PASS>=2:
    # Sparse chips follow the rim; the large color field stays readable at distance.
    for i in range(15):
        a=i*2.399
        x=.51*math.cos(a); z=shield_z+.67*math.sin(a)
        mesh('Enamel chip',[(x,front-.111,z),(x+.018,front-.111,z+.035),(x+.032,front-.111,z+.012)],[(0,1,2)],edge,'shield','Shield_Orange',False)
    # A face-like embossed brow and nose make the shield a false face, not a sign.
    for s in [-1,1]:
        tube('False brow',[(s*.07,front-.116,shield_z+.24),(s*.22,front-.13,shield_z+.28),(s*.32,front-.12,shield_z+.22)],[.022,.03,.015],orange,'shield','Shield_Orange',n=6)
        disk('False eye recess',(s*.20,front-.118,shield_z+.15),.08,.018 if PASS>=3 else .035,.012,dark,'shield','Shield_Orange')
    tube('Mask nose',[(0,front-.12,shield_z+.15),(0,front-.18,shield_z-.02),(0,front-.13,shield_z-.09)],[.045,.055,.025],orange,'shield','Shield_Orange',n=8)
    tube('Mask mouth',[(-.19,front-.12,shield_z-.29),(0,front-.135,shield_z-.26 if PASS>=3 else shield_z-.29),(.19,front-.12,shield_z-.29)],[.016,.021,.016],dark,'shield','Shield_Orange',n=6)

# Deforming armature, with individually movable target mechanisms.
data=bpy.data.armatures.new('FalseFaceRig'); rig=bpy.data.objects.new('FalseFaceRig',data); COL.objects.link(rig)
bpy.context.view_layer.objects.active=rig; rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
spec=[('root',(0,0,0),(0,0,.25),None),('pelvis',(0,.04,1.02),(0,.04,1.30),'root'),
      ('chest',(0,.04,1.30),(0,-.03,1.87),'pelvis'),('head',(0,-.03,1.87),(0,-.24,2.12),'chest'),
      ('shield',(0,front,shield_z),(0,front,shield_z+.28),'root'),
      ('conduit',(0,-.48,1.47),(0,front+.08,shield_z),'head')]
for s,side in [(-1,'R'),(1,'L')]:
    spec += [('upper_arm.'+side,(s*.34,0,1.78),(s*.54,-.04,1.32),'chest'),
             ('forearm.'+side,(s*.54,-.04,1.32),(s*.66,-.22,.88),'upper_arm.'+side),
             ('hand.'+side,(s*.66,-.22,.88),(s*.68,-.28,.61),'forearm.'+side),
             ('thigh.'+side,(s*.16,.04,1.08),(s*.28,-.18,.65),'pelvis'),
             ('shin.'+side,(s*.28,-.18,.65),(s*.29,.01,.18),'thigh.'+side),
             ('foot.'+side,(s*.29,.01,.18),(s*.30,-.33,.085),'shin.'+side)]
for name,head,tail,parent in spec:
    b=data.edit_bones.new(name); b.head=head; b.tail=tail
    if parent: b.parent=data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
rig.select_set(False)
meshes=[]
for group, objects in groups.items():
    # Apply only cloth thickness before combining; keep all mesh vertices editable.
    for ob in objects:
        bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]; bpy.ops.object.join()
    ob=objects[0]; ob.name=group
    ob.parent=rig
    mod=ob.modifiers.new('Deform / normalized skin weights','ARMATURE'); mod.object=rig
    meshes.append(ob)

def socket(name, bone, point):
    ob=bpy.data.objects.new(name,None); COL.objects.link(ob)
    ob.empty_display_type='ARROWS'; ob.empty_display_size=.10
    ob.parent=rig; ob.parent_type='BONE'; ob.parent_bone=bone
    bpy.context.view_layer.update()
    from mathutils import Matrix
    ob.matrix_world=Matrix.Translation(point)
    return ob

socket('CoreSocket','head',(0,-.49,1.75))
socket('CableStart','head',(0,-.48,1.47))
socket('CableEnd','shield',(0,front+.08,shield_z))
socket('ShieldPivot','shield',(0,front,shield_z))

rig.animation_data_create()
for clip,length in [('Idle',60),('Walk',30),('ShieldOpen',30)]:
    action=bpy.data.actions.new(clip); rig.animation_data.action=action
    for frame in range(1,length+2):
        t=(frame-1)/length; phase=math.tau*t
        for pb in rig.pose.bones:
            pb.rotation_mode='XYZ'; pb.rotation_euler=(0,0,0); pb.location=(0,0,0)
        rig.pose.bones['chest'].rotation_euler.x=.018*math.sin(phase)
        if clip=='Walk':
            for side,sign in [('L',1),('R',-1)]:
                swing=math.sin(phase)*sign
                rig.pose.bones['thigh.'+side].rotation_euler.x=.20*swing
                rig.pose.bones['shin.'+side].rotation_euler.x=.24*max(0,-swing)
                rig.pose.bones['upper_arm.'+side].rotation_euler.x=-.14*swing
                rig.pose.bones['forearm.'+side].rotation_euler.x=.055*max(0,swing)
        if clip=='ShieldOpen':
            # Baked visual sample only. Integrator owns mechanism timing.
            rig.pose.bones['shield'].location.x=.98*t
            rig.pose.bones['shield'].rotation_euler.y=1.10*t
        for pb in rig.pose.bones:
            pb.keyframe_insert('rotation_euler',frame=frame,group=pb.name)
            pb.keyframe_insert('location',frame=frame,group=pb.name)
    track=rig.animation_data.nla_tracks.new(); track.name=clip
    strip=track.strips.new(clip,1,action); strip.action_frame_start=1; strip.action_frame_end=length+1
    track.mute=True
rig.animation_data.action=None
for pb in rig.pose.bones:
    pb.rotation_euler=(0,0,0); pb.location=(0,0,0)
bpy.context.scene.frame_set(1)
bpy.context.scene.render.fps=30
bpy.context.view_layer.update()

# Explicit export: no cameras/lights, metre units, yaw only on the shared root.
bpy.context.scene.unit_settings.system='METRIC'
bpy.ops.object.select_all(action='DESELECT')
for ob in COL.objects: ob.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
rig.rotation_euler.z=math.pi
bpy.context.view_layer.update()
for track in rig.animation_data.nla_tracks: track.mute=False
bpy.ops.export_scene.gltf(filepath=str(GLB),export_format='GLB',use_selection=True,
    export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',
    export_force_sampling=True,export_skins=True,export_all_influences=False)
rig.rotation_euler.z=0
for track in rig.animation_data.nla_tracks: track.mute=True
triangles=sum(sum(len(p.vertices)-2 for p in ob.data.polygons) for ob in meshes)
bad_weights=sum(1 for ob in meshes for v in ob.data.vertices if abs(sum(g.weight for g in v.groups)-1)>.001)
result={'pass':PASS,'mesh_objects':len(meshes),'triangles':triangles,'bones':len(data.bones),
        'bad_weights':bad_weights,'blend_sha256':digest(BLEND),'glb_sha256':digest(GLB),
        'clips':['Idle','Walk','ShieldOpen'],'height_m':2.22,'forward':'Godot -Z',
        'shield_front_blender_y':front,'shield_height_m':shield_z}
(OUT/'model.json').write_text(json.dumps(result,indent=2)+'\n')
STAMP.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
assert bad_weights==0
