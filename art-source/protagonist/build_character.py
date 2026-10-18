"""First silhouette trial. Run through project blender.py, never over hand edits.

Metres, +Z up, -Y forward in Blender; export yaw gives Godot +Y up, -Z front.
The saved file contains editable meshes and a separate review studio. No rig.
"""
import bpy
import bmesh
import math
import os
import json
from pathlib import Path
from mathutils import Vector

REPO = Path(os.environ['JAM_REPO'])
OUT = Path(os.environ['JAM_STATE_ROOT']) / 'exports/character-art'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
for collection in list(bpy.data.collections):
    bpy.data.collections.remove(collection)
character = bpy.data.collections.new('PROTAGONIST | editable, unrigged')
studio = bpy.data.collections.new('REVIEW STUDIO | excluded from GLB')
bpy.context.scene.collection.children.link(character)
bpy.context.scene.collection.children.link(studio)


def material(name, hex_color, roughness=.8, metallic=0):
    rgb = [int(hex_color[i:i+2], 16) / 255 for i in (0, 2, 4)]
    rgb = [v / 12.92 if v < .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_backface_culling = True
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    return mat


skin = material('01 | warm skin', 'BB947B')
hair = material('02 | dark chestnut hair', '3D302C')
shirt = material('03 | oatmeal work shirt', 'B4B0A0')
pants = material('04 | slate olive canvas', '626B64')
leather = material('05 | oxhide leather', '5C4635')
rubber = material('06 | boot soles and recesses', '292D2C')
brass = material('07 | aged brass hardware', 'A28E60', .48, .65)
ivory = material('08 | eyes and linen laces', 'CCC8AD')
lip = material('09 | lips and ear interior', '8C6253')


def mesh(name, verts, faces, mat, smooth=False, collection=character):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    data.materials.append(mat)
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    for p in data.polygons:
        p.use_smooth = smooth
    return obj


def loft(name, rings, mat, cap=True, smooth=False):
    n = len(rings[0])
    vertices = [v for row in rings for v in row]
    faces = [(j*n+i, j*n+(i+1)%n, (j+1)*n+(i+1)%n, (j+1)*n+i)
             for j in range(len(rings)-1) for i in range(n)]
    if cap:
        faces += [tuple(reversed(range(n))), tuple(range((len(rings)-1)*n, len(rings)*n))]
    return mesh(name, vertices, faces, mat, smooth)


def horizontal(name, sections, mat, n=16, smooth=False):
    # section: z, x-center, y-center, x-radius, y-radius
    rings = [[(x+rx*math.sin(2*math.pi*i/n), y-ry*math.cos(2*math.pi*i/n), z)
              for i in range(n)] for z, x, y, rx, ry in sections]
    return loft(name, rings, mat, smooth=smooth)


def tube(name, points, radii, mat, n=10, flatten=1, smooth=False):
    points = [Vector(p) for p in points]
    rings = []
    for j, p in enumerate(points):
        tangent = points[min(j+1, len(points)-1)] - points[max(j-1, 0)]
        tangent.normalize()
        ref = Vector((0, 1, 0)) if abs(tangent.y) < .9 else Vector((1, 0, 0))
        u = tangent.cross(ref).normalized()
        v = tangent.cross(u).normalized()
        rings.append([p+radii[j]*(u*math.cos(2*math.pi*i/n)+v*flatten*math.sin(2*math.pi*i/n)) for i in range(n)])
    return loft(name, rings, mat, smooth=smooth)


def ellipsoid(name, center, scale, mat, segments=24, rings=12, smooth=False):
    rows = []
    for j in range(rings+1):
        phi = .001+(math.pi-.002)*j/rings
        rows.append([(center[0]+scale[0]*math.sin(phi)*math.sin(2*math.pi*i/segments),
                      center[1]-scale[1]*math.sin(phi)*math.cos(2*math.pi*i/segments),
                      center[2]+scale[2]*math.cos(phi)) for i in range(segments)])
    return loft(name, rows, mat, smooth=smooth)


def panel(name, coords, depth, mat, bevel=.005):
    # Front-facing shaped leather/canvas panel, thickness extends toward +Y.
    verts = coords + [(x, y+depth, z) for x, y, z in coords]
    n = len(coords)
    faces = [tuple(range(n)), tuple(reversed(range(n, 2*n)))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    ob = mesh(name, verts, faces, mat)
    if bevel:
        mod = ob.modifiers.new('Soft manufactured edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        mod = ob.modifiers.new('Face weighted normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
    return ob


def band(name, points, width, mat, depth=.006):
    # Ribbon with thickness; appropriate for straps, not intersecting boxes.
    rings = []
    for j, p in enumerate(points):
        p = Vector(p)
        t = Vector(points[min(j+1,len(points)-1)]) - Vector(points[max(j-1,0)])
        # Width lies in the XZ plane for chest/back straps.
        side = Vector((t.z, 0, -t.x)).normalized()*width/2
        rings.append([p-side, p+side, p+side+Vector((0,depth,0)), p-side+Vector((0,depth,0))])
    return loft(name, rings, mat)


def join_objects(name, objects):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


# SHIRT. A continuous mesh: sleeves bridge genuine openings in the torso.
n = 24
sections = [(1.035,.155,.105), (1.09,.151,.109), (1.20,.166,.116),
            (1.31,.189,.116), (1.39,.205,.106), (1.455,.200,.091), (1.49,.075,.066)]
verts = []
for j, (z, rx, ry) in enumerate(sections):
    for i in range(n):
        theta = 2*math.pi*i/n
        zz = z-(.022*abs(math.sin(theta)) if j == 5 else 0)
        if j == 6:
            zz -= .027*max(math.cos(theta),0)
        verts.append((rx*math.sin(theta), -ry*math.cos(theta), zz))
faces = []
removed = {}
for j in range(len(sections)-1):
    for i in range(n):
        quad = (j*n+i, j*n+(i+1)%n, (j+1)*n+(i+1)%n, (j+1)*n+i)
        side = 1 if 4 <= i < 8 else (-1 if 16 <= i < 20 else 0)
        if side and j in (3,4):
            removed.setdefault(side, []).append(quad)
        else:
            faces.append(quad)
faces.append(tuple(reversed(range(n))))
for sign, quads in removed.items():
    edges = {}
    for q in quads:
        for a,b in zip(q, q[1:]+q[:1]):
            e = tuple(sorted((a,b)))
            edges[e] = edges.get(e,0)+1
    boundary = set(v for e,count in edges.items() if count == 1 for v in e)
    center = Vector((sign*.182, 0, 1.38))
    u, v = Vector((0,1,0)), Vector((sign*.78,0,.62))
    ordered = sorted(boundary, key=lambda i: math.atan2((Vector(verts[i])-center).dot(v),(Vector(verts[i])-center).dot(u)))
    angles = [math.atan2((Vector(verts[i])-center).dot(v),(Vector(verts[i])-center).dot(u)) for i in ordered]
    prev = ordered
    for x,z,r in [(.246,1.363,.087),(.285,1.305,.082),(.332,1.233,.073)]:
        current=[]
        for a in angles:
            current.append(len(verts))
            verts.append(Vector((sign*x,0,z))+r*(u*math.cos(a)+v*math.sin(a)))
        faces += [(prev[i],prev[(i+1)%len(prev)],current[(i+1)%len(prev)],current[i]) for i in range(len(prev))]
        prev=current
shirt_ob = mesh('Shirt | continuous shoulder and sleeve topology', verts, faces, shirt)

# Collar follows neck opening. Rolled cuffs are hollow rings with a return edge.
horizontal('Collar | bound crew neck',[(1.458,0,0,.076,.068),(1.478,0,0,.078,.069),(1.485,0,0,.073,.064)],shirt,24)
horizontal('Neck',[(1.435,0,.006,.066,.062),(1.49,0,.008,.062,.060),(1.55,0,.005,.064,.063)],skin,20,True)
for s,label in [(1,'L'),(-1,'R')]:
    tube('Sleeve roll.'+label,[(s*.319,0,1.254),(s*.331,0,1.237),(s*.350,0,1.211),(s*.349,0,1.210)],
         [.084,.087,.083,.068],shirt,12)
    arm = tube('Forearm.'+label,[(s*.342,0,1.223),(s*.371,-.003,1.178),(s*.398,-.008,1.132),
                    (s*.432,-.012,1.065),(s*.476,-.012,.994),(s*.489,-.013,.972)],
                    [.054,.056,.052,.043,.031,.031],skin,12,1.02,True)
    # Palm with relaxed, separate fingers. Voxel-unioned for coherent hand surface.
    hand_parts = [tube('Palm',[(s*.484,-.013,.987),(s*.510,-.015,.951),(s*.531,-.017,.914)],
                       [.031,.039,.033],skin,12,.63,True)]
    for k in range(4):
        yy = -.039+k*.016
        x0 = .514 + .007*k
        z0 = .926 - .004*k
        length = [.048,.062,.058,.047][k]
        hand_parts.append(tube('Finger',[(s*x0,yy,z0),(s*(x0+.020),yy-.003,z0-length*.48),
                  (s*(x0+.026),yy-.009,z0-length*.9),(s*(x0+.021),yy-.014,z0-length)],
                  [.010,.0095,.008,.0045],skin,8,1,True))
    hand_parts.append(tube('Thumb',[(s*.493,-.036,.959),(s*.482,-.054,.939),(s*.486,-.064,.917),
                                (s*.497,-.063,.910)],[.016,.014,.011,.006],skin,8,1,True))
    hand_ob=join_objects('Hand | relaxed fingers.'+label, hand_parts)
    mod=hand_ob.modifiers.new('Union palm and digits','REMESH')
    mod.mode='VOXEL'
    mod.voxel_size=.0032
    bpy.context.view_layer.objects.active=hand_ob
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=hand_ob.modifiers.new('Retain hand silhouette','DECIMATE')
    mod.ratio=.16
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in hand_ob.data.polygons: p.use_smooth=True

# TROUSERS. Pelvis and two shaped leg tubes are unioned into a single cloth mesh.
trouser_parts=[horizontal('Pelvis',[(.865,0,.012,.155,.108),(.920,0,.012,.183,.121),
                (1.01,0,.005,.172,.114),(1.055,0,0,.156,.107)],pants,20)]
for s,label in [(1,'L'),(-1,'R')]:
    trouser_parts.append(horizontal('Leg',[(.255,s*.180,.007,.075,.077),(.295,s*.182,.011,.084,.083),
        (.355,s*.181,.017,.100,.093),(.425,s*.174,.020,.105,.098),(.495,s*.160,.011,.086,.083),
        (.565,s*.145,-.005,.093,.091),(.660,s*.131,-.003,.098,.099),(.780,s*.116,.007,.110,.108),
        (.885,s*.100,.009,.112,.112),(.947,s*.096,.012,.102,.103)],pants,16))
trouser=join_objects('Trousers | continuous seat, crotch and legs',trouser_parts)
mod=trouser.modifiers.new('Unify trouser seams','REMESH')
mod.mode='VOXEL'
mod.voxel_size=.010
bpy.context.view_layer.objects.active=trouser
bpy.ops.object.modifier_apply(modifier=mod.name)
mod=trouser.modifiers.new('Canvas planes','DECIMATE')
mod.ratio=.12
bpy.ops.object.modifier_apply(modifier=mod.name)
for s,label in [(1,'L'),(-1,'R')]:
    horizontal('Trouser turnup.'+label,[(.245,s*.181,.006,.085,.085),(.251,s*.181,.006,.089,.089),
            (.296,s*.182,.006,.090,.089),(.302,s*.182,.006,.083,.081)],pants,16)
    x=s*.147
    panel('Shaped knee reinforcement.'+label,[(x-.065,-.096,.582),(x+.065,-.096,.582),
        (x+.066,-.093,.505),(x+.049,-.080,.447),(x-.054,-.080,.447),(x-.069,-.092,.505)],.007,pants,.004)
    # Boots: broad toe, shaped instep, tall shaft, distinct thick sole.
    horizontal('Boot upper.'+label,[(.042,s*.183,-.046,.079,.137),(.069,s*.183,-.050,.082,.140),
         (.102,s*.183,-.049,.080,.136),(.126,s*.183,-.033,.073,.117),(.162,s*.183,-.005,.061,.078),
         (.230,s*.183,.009,.057,.065),(.275,s*.183,.010,.061,.065)],leather,16)
    horizontal('Boot sole.'+label,[(0,s*.183,-.047,.083,.140),(.013,s*.183,-.049,.087,.144),
                               (.043,s*.183,-.049,.086,.143),(.052,s*.183,-.048,.083,.141)],rubber,16)
    # Front tongue and criss-cross linen laces, no microscopic eyelets.
    panel('Boot tongue.'+label,[(s*.183-.033,-.066,.255),(s*.183+.033,-.066,.255),
                (s*.183+.038,-.140,.113),(s*.183-.038,-.140,.113)],.006,leather,.003)
    laces=[]
    for j in range(5):
        z=.135+j*.022
        y=-.133+j*.0145
        laces.append(tube('Lace',[(s*.183-.029,y,z),(s*.183+.029,y+.010,z+.018)], [.003,.003],ivory,5))
        laces.append(tube('Lace',[(s*.183+.029,y,z),(s*.183-.029,y+.010,z+.018)], [.003,.003],ivory,5))
    join_objects('Boot laces.'+label,laces)

# WORK HARNESS: diagonal single strap over shoulder and behind back, bib pocket.
band('Harness | front shoulder to opposite waist',[(-.151,-.066,1.464),(-.139,-.112,1.409),
    (-.113,-.127,1.329),(-.045,-.132,1.236),(.045,-.126,1.139),(.123,-.108,1.063)],.041,leather)
band('Harness | back return', [(-.151,.058,1.464),(-.127,.109,1.396),(-.053,.125,1.294),
    (.036,.126,1.181),(.123,.096,1.063)],.041,leather,depth=-.008)
band('Harness | shoulder bridge',[(-.151,-.067,1.464),(-.155,0,1.478),(-.151,.060,1.464)],.041,leather)
panel('Canvas chest bib',[(-.125,-.135,1.333),(.110,-.135,1.333),(.121,-.125,1.116),
      (.095,-.126,1.094),(-.110,-.126,1.094),(-.129,-.125,1.116)],.015,pants,.009)
panel('Chest pocket',[(-.092,-.155,1.279),(.078,-.155,1.279),(.080,-.150,1.155),
                     (.063,-.151,1.138),(-.076,-.151,1.138),(-.093,-.151,1.156)],.012,shirt,.006)
band('Pocket mouth',[(-.087,-.162,1.267),(.074,-.162,1.267)],.010,leather,.004)
band('Pocket pen loop',[(-.073,-.168,1.272),(-.073,-.169,1.232)],.008,brass,.003)
horizontal('Belt | oval waist',[(1.028,0,0,.164,.115),(1.079,0,0,.164,.115)],leather,32)


def buckle(name,cx,y,z,w,h):
    points=[(cx-w/2,y,z-h/2),(cx+w/2,y,z-h/2),(cx+w/2,y,z+h/2),(cx-w/2,y,z+h/2),(cx-w/2,y,z-h/2)]
    obj=tube(name,points,[.006]*5,brass,6)
    tube(name+' | tongue',[(cx,y-.002,z-h/2),(cx,y-.002,z+h*.28)],[.003,.003],brass,6)
    return obj


buckle('Belt buckle',0,-.124,1.053,.071,.046)
buckle('Shoulder adjuster',-.134,-.135,1.406,.044,.036)
for x in [-.125,-.073,.078,.132]:
    y=-.115*math.sqrt(max(0,1-(x/.17)**2))-.008
    band('Belt keeper',[(x,y,1.024),(x,y,1.083)],.019,pants,.009)
for s,label in [(1,'L'),(-1,'R')]:
    # Rounded flap pouches extend at the hips, not rigid cubes.
    x=s*.209
    pouch=panel('Hip pouch.'+label,[(x-.051,-.052,1.022),(x+.051,-.052,1.022),
      (x+.057,-.065,.883),(x+.038,-.065,.859),(x-.042,-.065,.863),(x-.057,-.065,.884)],.083,leather,.012)
    panel('Pouch flap.'+label,[(x-.054,-.079,1.029),(x+.054,-.079,1.029),
              (x+.047,-.088,.976),(x,-.091,.963),(x-.047,-.088,.976)],.012,pants,.006)
    band('Pouch fastener.'+label,[(x,-.101,1.019),(x,-.105,.964)],.017,leather)
    ellipsoid('Pouch stud.'+label,(x,-.112,.977),(.006,.003,.006),brass,10,6)
    # Rear patch pockets.
    panel('Rear trouser pocket.'+label,[(s*.093-.053,.123,.993),(s*.093+.053,.123,.993),
          (s*.093+.048,.128,.901),(s*.093,.133,.883),(s*.093-.048,.128,.901)],-.008,pants,.004)
# Signature fan of long tool sleeves on the reference's right hip.
for j in range(3):
    x=-.107-j*.034
    z=.922-j*.012
    ob=panel('Hanging tool sleeve.%02d'%j,[(x-.016,-.150,1.032),(x+.015,-.150,1.032),
       (x+.021,-.159,z-.075),(x+.008,-.160,z-.089),(x-.017,-.160,z-.083)],.025,leather,.006)
    band('Tool sleeve loop.%02d'%j,[(x,-.169,1.061),(x,-.170,1.007)],.022,pants)

# HEAD. A continuous ring mesh with modeled jaw, cheekbones, sockets, nasal
# bridge/tip, muzzle and chin. Facial features deform the head itself.
profile=[(1.522,.034,.000,.045,.035),(1.535,.053,.002,.067,.048),(1.551,.071,.004,.077,.060),
 (1.573,.084,.008,.082,.078),(1.596,.092,.010,.083,.089),(1.620,.100,.011,.086,.100),
 (1.644,.107,.011,.087,.108),(1.668,.110,.012,.089,.112),(1.690,.108,.013,.090,.113),
 (1.711,.106,.014,.089,.112),(1.739,.108,.016,.092,.107),(1.764,.105,.018,.090,.099),
 (1.788,.090,.019,.078,.083),(1.808,.067,.019,.057,.060),(1.822,.030,.019,.025,.027),
 (1.826,.003,.019,.003,.003)]


def interpolate(z, data=profile):
    for a,b in zip(data,data[1:]):
        if a[0]<=z<=b[0]:
            t=(z-a[0])/(b[0]-a[0])
            return [a[k]*(1-t)+b[k]*t for k in range(1,len(a))]
    return data[-1][1:]


def gauss(v,mean,sigma): return math.exp(-.5*((v-mean)/sigma)**2)


def face_y(x,z):
    rx,cy,front,back=interpolate(z)
    y=cy-front*math.sqrt(max(0,1-(x/rx)**2))
    # strong nose, narrow bridge, separate alar width, defined chin
    y-=.023*gauss(x,0,.014)*gauss(z,1.650,.033)
    y-=.023*gauss(x,0,.020)*gauss(z,1.637,.010)
    y-=.010*gauss(abs(x),.020,.009)*gauss(z,1.633,.009)
    y-=.010*gauss(x,0,.039)*gauss(z,1.588,.016)
    y-=.011*gauss(x,0,.035)*gauss(z,1.546,.010)
    for s in [-1,1]:
        y+=.011*gauss(x,s*.048,.024)*gauss(z,1.680,.013)
        y-=.012*gauss(x,s*.048,.029)*gauss(z,1.704,.012)
        y-=.010*gauss(x,s*.073,.020)*gauss(z,1.649,.015)
    return y


rows=[]
zvalues=sorted(set([a[0] for a in profile]+[1.53+i*.006 for i in range(49)]))
for z in zvalues:
    if z>1.826: continue
    rx,cy,front,back=interpolate(z)
    row=[]
    for i in range(64):
        a=2*math.pi*i/64
        x=rx*math.sin(a)
        y=face_y(x,z) if math.cos(a)>=0 else cy-back*math.cos(a)
        row.append((x,y,z))
    rows.append(row)
head=loft('Head | editable facial surface',rows,skin,smooth=True)

# Almond eyes recessed into sockets. Iris is a shallow elliptical patch.
for s,label in [(1,'L'),(-1,'R')]:
    xc=s*.047
    outline=[]
    for i in range(24):
        a=2*math.pi*i/24
        x=xc+.022*math.cos(a)
        z=1.680+.0065*math.sin(a)+s*.055*(x-xc)
        outline.append((x,face_y(x,z)-.0035,z))
    center=(xc,face_y(xc,1.680)-.010,1.680)
    ev=[center]+outline
    mesh('Eye almond.'+label,ev,[(0,i+1,(i+1)%24+1) for i in range(24)],ivory,True)
    iris_y=center[1]-.001
    ellipsoid('Iris.'+label,(xc,iris_y,1.680),(.006,.002,.006),pants,16,8,True)
    ellipsoid('Pupil.'+label,(xc,iris_y-.002,1.680),(.0033,.001,.0045),rubber,12,8,True)
    # Fine eyelid rims, angular brows rather than painted facial markings.
    tube('Upper eyelid.'+label,outline[:13],[.0018]*13,skin,5,1,True)
    tube('Lower eyelid.'+label,outline[12:]+[outline[0]],[.0013]*13,skin,5,1,True)
    brow=[]
    for x,z in [(s*.022,1.706),(s*.043,1.711),(s*.065,1.708),(s*.078,1.700)]:
        brow.append((x,face_y(x,z)-.004,z))
    tube('Brow.'+label,brow,[.003,.004,.003,.001],hair,6,.65,True)
    # Ear rims and interior, attached at the jaw/temple.
    ellipsoid('Ear.'+label,(s*.108,.009,1.660),(.020,.019,.034),skin,16,12,True)
    ellipsoid('Ear concha.'+label,(s*.120,-.004,1.660),(.009,.014,.022),lip,12,8,True)
    tube('Ear helix.'+label,[(s*.119,-.013,1.640),(s*.127,-.012,1.666),
             (s*.120,-.009,1.682),(s*.109,-.011,1.680)], [.003,.004,.004,.003],skin,6,1,True)
    # Small nostril crease tucked below the modeled alar wing.
    x=s*.017
    ellipsoid('Nostril.'+label,(x,face_y(x,1.630)-.0007,1.629),(.005,.0015,.0021),lip,10,6,True)
# Lips share the underlying muzzle shape, with a shallow cupid's bow.
upper=[(-.030,1.589),(-.016,1.593),(-.007,1.595),(0,1.592),(.007,1.595),(.016,1.593),(.030,1.589)]
lower=[(-.030,1.588),(-.016,1.584),(0,1.582),(.016,1.584),(.030,1.588)]
for name,points,r in [('Upper lip',upper,.0028),('Lower lip',lower,.003)]:
    tube(name,[(x,face_y(x,z)-.002,z) for x,z in points],[r*.5]+[r]*(len(points)-2)+[r*.5],lip,6,.8,True)
tube('Mouth seam',[(x,face_y(x,1.588)-.0045,1.588) for x in [-.027,-.014,0,.014,.027]],
     [.0006,.0009,.001,.0009,.0006],leather,5,1,True)

# HAIR: one fitted cap with swept panel locks, a tied bun, loose side tendrils.
hair_rows=[]
for j in range(17):
    t=j/16
    row=[]
    for i in range(48):
        a=2*math.pi*i/48
        # Forehead hairline high in front, low at nape, temple peaks beside ears.
        bottom=1.635+.100*max(math.cos(a),0)**3
        bottom+=.018*gauss(abs(math.sin(a)),.92,.15)
        z=1.839-(1.839-bottom)*t
        rx,cy,front,back=interpolate(min(z-.012,1.826))
        x=(rx+.008)*math.sin(a)
        y=cy-(front+.009 if math.cos(a)>=0 else back+.012)*math.cos(a)
        if j==0:
            x=.002*math.sin(a)
            y=.019-.002*math.cos(a)
        row.append((x,y,z))
    hair_rows.append(row)
loft('Hair | fitted swept cap',hair_rows,hair,smooth=True)


def lock(name, points, widths, thick=.010):
    # Low ridged ribbon aligned to the scalp, with no tube-like crown spikes.
    rows=[]
    for j,point in enumerate(points):
        p=Vector(point)
        tangent=(Vector(points[min(j+1,len(points)-1)])-Vector(points[max(j-1,0)])).normalized()
        radial=(p-Vector((0,.022,1.727))).normalized()
        u=radial.cross(tangent).normalized()
        radial=tangent.cross(u).normalized()
        if radial.dot(p-Vector((0,.022,1.727)))<0: radial=-radial
        w=widths[j]
        rows.append([p-u*w-radial*.002,p-u*w*.6+radial*thick*.32,
            p+radial*thick*.55,p+u*w*.6+radial*thick*.32,p+u*w-radial*.002,p-radial*.003])
    return loft(name,rows,hair)


# Long sweeps converge at the tied crown, asymmetrical parted fringe.
for s in [-1,1]:
    for j in range(4):
        x=s*(.025+j*.022)
        lock('Swept crown lock.%s.%s'%(s,j),[(x,-.084+j*.009,1.758-j*.005),
            (s*(.045+j*.019),-.057+j*.009,1.810-j*.007),
            (s*(.059+j*.016),.010+j*.010,1.829-j*.008),
            (s*(.052+j*.011),.080,1.799-j*.010),(.019,.132,1.780)],
            [.011,.021,.022,.019,.006],.012)
lock('Fringe | left long sweep',[(-.018,-.080,1.813),(-.058,-.103,1.789),(-.081,-.107,1.749),
    (-.088,-.100,1.714),(-.105,-.072,1.690)], [.023,.026,.020,.014,.003],.016)
lock('Fringe | right parted sweep',[(.009,-.087,1.813),(.047,-.105,1.790),(.075,-.105,1.751),
    (.087,-.088,1.713)], [.021,.023,.016,.003],.014)
ellipsoid('Hair | tied bun',(-.011,.147,1.782),(.090,.077,.091),hair,16,10)
for j in range(6):
    a=2*math.pi*j/6
    lock('Bun twist.%02d'%j,[(.070*math.sin(a)-.011,.123,1.782+.070*math.cos(a)),
       (.085*math.sin(a+.30)-.011,.167,1.782+.083*math.cos(a+.30)),
       (.050*math.sin(a+.70)-.011,.206,1.782+.053*math.cos(a+.70))], [.022,.027,.009],.021)
band('Hair tie',[(-.075,.122,1.778),(-.047,.117,1.718),(.017,.119,1.706),(.064,.127,1.753)],.014,leather)
for s in [-1,1]:
    lock('Loose temple curl.%s'%s,[(s*.091,-.078,1.728),(s*.109,-.075,1.685),
         (s*.097,-.082,1.651),(s*.113,-.070,1.618),(s*.101,-.071,1.585)], [.009,.011,.008,.006,.0015],.009)
    lock('Loose nape curl.%s'%s,[(s*.060,.180,1.733),(s*.074,.178,1.686),
         (s*.063,.171,1.666),(s*.076,.162,1.642)], [.012,.010,.007,.001],.010)

# Keep hair masses together as a sensibly named editable part, with brows separate.
hair_objects=[ob for ob in character.objects if ob.data.materials[0]==hair and not ob.name.startswith('Brow')]
join_objects('Hair | swept cap, bun and loose locks',hair_objects)
# Apply manufactured-edge modifiers for deterministic GLB; all remain editable meshes.
for ob in list(character.objects):
    bpy.context.view_layer.objects.active=ob
    for mod in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    # The asset has a common feet-on-ground origin, metres, no armature.
    ob['asset_stage']='silhouette trial; awaiting visual review before rigging'
    ob['reference']='art/more/Pasted image (4).png'

bpy.ops.object.select_all(action='DESELECT')
for ob in character.objects:
    ob.select_set(True)
    # Blender's -Y front maps to glTF +Z. Yaw for Godot's -Z front on export.
    ob.rotation_euler.z += math.pi
bpy.context.view_layer.objects.active=head
bpy.ops.export_scene.gltf(filepath=str(REPO/'assets/characters/protagonist/protagonist.glb'),
    export_format='GLB',use_selection=True,export_yup=True,export_animations=False,
    export_extras=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
for ob in character.objects: ob.rotation_euler.z -= math.pi

# Studio, CPU Cycles only. Full-size orthographic reviews use the same framing.
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=40
scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED'
scene.render.threads=4
scene.render.resolution_x=900
scene.render.resolution_y=1100
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.world.color=(.18,.18,.18)
groundmat=material('Studio | charcoal', '353B3C')
mesh('Studio floor',[(-200,-200,-.006),(200,-200,-.006),(200,200,-.006),(-200,200,-.006)],[(0,1,2,3)],groundmat,collection=studio)


def area(name,position,power,size):
    data=bpy.data.lights.new(name,'AREA')
    data.energy=power
    data.shape='DISK'
    data.size=size
    ob=bpy.data.objects.new(name,data)
    studio.objects.link(ob)
    ob.location=position
    ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()


area('Key softbox',(-3,-4,6),420,4)
area('Fill softbox',(3,-2,3.5),230,3)
area('Hair rim',(1,3,4),500,3)
camera_data=bpy.data.cameras.new('Review camera')
camera=bpy.data.objects.new('Review camera',camera_data)
studio.objects.link(camera)
camera_data.type='ORTHO'
camera_data.ortho_scale=2.13
camera_data.lens=70
scene.camera=camera


def view(position,target=(0,0,.94)):
    camera.location=position
    camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()


view((3,-5,2.65))
# Save with character selected and studio hidden from the editing viewport.
for ob in studio.objects: ob.hide_set(True)
for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type=='VIEW_3D':
            a.spaces.active.region_3d.view_distance=3.1
            a.spaces.active.region_3d.view_location=(0,0,.94)
            a.spaces.active.region_3d.view_rotation=camera.rotation_euler.to_quaternion()
            a.spaces.active.shading.color_type='MATERIAL'
            a.spaces.active.clip_end=100
bpy.ops.wm.save_as_mainfile(filepath=str(REPO/'art-source/protagonist/protagonist.blend'))
for ob in studio.objects: ob.hide_set(False)
for name,position in [('front',(0,-6,.94)),('side',(6,0,.94)),('back',(0,6,.94)),('three-quarter',(3,-5,2.25))]:
    view(position)
    scene.render.filepath=str(OUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)
    print('REVIEW_RENDER',name,flush=True)
# Portrait provides useful face evidence beyond the required turnaround.
scene.render.resolution_x=900
scene.render.resolution_y=900
camera_data.ortho_scale=.57
view((2,-5,1.85),(0,0,1.65))
scene.render.filepath=str(OUT/'portrait.png')
bpy.ops.render.render(write_still=True)

depsgraph=bpy.context.evaluated_depsgraph_get()
triangles=0
vertices=0
mins=Vector((1e9,1e9,1e9)); maxs=-mins
used=set()
for ob in character.objects:
    data=ob.data
    data.calc_loop_triangles()
    triangles+=len(data.loop_triangles)
    vertices+=len(data.vertices)
    used.update(m.name for m in data.materials)
    for vert in data.vertices:
        p=ob.matrix_world@vert.co
        for i in range(3):
            mins[i]=min(mins[i],p[i]); maxs[i]=max(maxs[i],p[i])
stats={'mesh_objects':len(character.objects),'vertices':vertices,'triangles':triangles,
       'materials':len(used),'material_names':sorted(used),'bounds_min_m':list(mins),
       'bounds_max_m':list(maxs),'dimensions_m':list(maxs-mins), 'armatures':0,
       'animations':0,'units':'metres','blender_forward':'-Y','gltf_forward':'-Z',
       'origin':'common world origin on floor between boots',
       'stage':'first model trial; stop before rigging for human visual review'}
(OUT/'model-stats.json').write_text(json.dumps(stats,indent=2)+'\n')
print('CHARACTER_STATS',json.dumps(stats),flush=True)
