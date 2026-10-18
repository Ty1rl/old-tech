"""Round J creature authoring. Existing sources are opened before refinement.

No gameplay dependencies. Flat materials and editable anatomy/cloth meshes;
one shared anatomical vocabulary, not scaled player assets. The two review
iterations are selected in own state/exports/round-j/enemy-settings.json.
"""
import bpy, bmesh, os, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix
sys.dont_write_bytecode=True
REPO=Path(os.environ['JAM_REPO'])
OUT=Path(os.environ['JAM_STATE_ROOT'])/'exports/round-j'
OUT.mkdir(parents=True,exist_ok=True)
SETTINGS=json.loads((OUT/'enemy-settings.json').read_text()) if (OUT/'enemy-settings.json').exists() else {'models':['patient'],'iteration':1}
SOURCE=REPO/'art-source/enemies'
ASSETS=REPO/'assets/enemies'
BODY=None
PART=None
M={}


def mat(name,color,metallic=0,emission=0):
    rgb=[int(color[i:i+2],16)/255 for i in (0,2,4)]
    rgb=[v/12.92 if v<.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*rgb,1);m.use_backface_culling=True
    bsdf=m.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(*rgb,1)
    bsdf.inputs['Roughness'].default_value=.78;bsdf.inputs['Metallic'].default_value=metallic
    if emission:
        bsdf.inputs['Emission Color'].default_value=(*rgb,1);bsdf.inputs['Emission Strength'].default_value=emission
    return m


def mesh(name,verts,faces,material,region='auto',body='A',collection=None,smooth=True):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.materials.append(M[material])
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    ob=bpy.data.objects.new(name,data);(collection or BODY).objects.link(ob)
    for p in data.polygons:p.use_smooth=smooth
    ob['region']=region;ob['body']=body;ob['surface']=material
    return ob


def loft(name,rows,material,**kw):
    n=len(rows[0]);verts=[v for r in rows for v in r]
    faces=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(rows)-1) for i in range(n)]
    faces+=[tuple(reversed(range(n))),tuple(range((len(rows)-1)*n,len(rows)*n))]
    return mesh(name,verts,faces,material,**kw)


def rings(name,sections,material,n=16,**kw):
    # z, centre x/y, radius x/y; a real lofted surface with anatomical changes.
    rows=[[(x+rx*math.sin(i*2*math.pi/n),y-ry*math.cos(i*2*math.pi/n),z) for i in range(n)] for z,x,y,rx,ry in sections]
    return loft(name,rows,material,**kw)


def tube(name,points,radii,material,n=10,flat=1,**kw):
    rows=[]
    for j,p in enumerate(points):
        p=Vector(p);t=(Vector(points[min(j+1,len(points)-1)])-Vector(points[max(j-1,0)])).normalized()
        ref=Vector((0,1,0)) if abs(t.y)<.9 else Vector((0,0,1))
        u=t.cross(ref).normalized();v=t.cross(u).normalized()
        rows.append([p+radii[j]*(u*math.cos(i*2*math.pi/n)+flat*v*math.sin(i*2*math.pi/n)) for i in range(n)])
    return loft(name,rows,material,**kw)


def sphere(name,center,scale,material,n=20,r=12,**kw):
    rows=[]
    for j in range(r+1):
        a=.002+(math.pi-.004)*j/r
        rows.append([(center[0]+scale[0]*math.sin(a)*math.sin(i*2*math.pi/n),center[1]-scale[1]*math.sin(a)*math.cos(i*2*math.pi/n),center[2]+scale[2]*math.cos(a)) for i in range(n)])
    return loft(name,rows,material,**kw)


def strap(name,points,width,material='Leather',**kw):
    rows=[]
    for j,p in enumerate(points):
        p=Vector(p);side=Vector((width/2,0,0));thick=Vector((0,.005,0))
        rows.append([p-side,p+side,p+side+thick,p-side+thick])
    return loft(name,rows,material,smooth=False,**kw)


def hoop(name,center,rx,ry,width,material,**kw):
    z=center[2]
    return rings(name,[(z-width/2,center[0],center[1],rx,ry),(z,center[0],center[1],rx+.003,ry+.003),(z+width/2,center[0],center[1],rx,ry)],material,24,**kw)


def circle(name,center,radius,thickness,material,plane='XY',**kw):
    pts=[]
    for i in range(33):
        a=i*2*math.pi/32
        p=Vector((radius*math.cos(a),radius*math.sin(a),0)) if plane=='XY' else Vector((radius*math.cos(a),0,radius*math.sin(a)))
        pts.append(Vector(center)+p)
    return tube(name,pts,[thickness]*len(pts),material,8,**kw)


def apply(ob,mod):
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.modifier_apply(modifier=mod.name)


def join(name,objects):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();objects[0].name=name
    return objects[0]


def body_form(label,bulk=False,offset=0,scale=1,skin_budget=7800):
    """Continuous skin from anatomical lofts, unioned once; accessories stay editable."""
    before=set(BODY.objects)
    if not bulk:
        hip,knee,ankle=.82,.43,.11;hipx,kneex,anklex=.09,.12,.15
        shoulder=(.225,.02,1.43);elbow=(.35,-.035,1.08);wrist=(.410,-.11,.62)
        head_y,head_z=-.29,1.66
        sections=[(.77,0,.035,.14,.10),(.88,0,.035,.15,.11),(1.02,0,.04,.13,.10),
            (1.14,0,.045,.16,.105),(1.27,0,.045,.215,.13),(1.39,0,.04,.26,.135),
            (1.48,0,.01,.24,.12),(1.53,0,-.055,.085,.073)]
    else:
        hip,knee,ankle=.65,.35,.10;hipx,kneex,anklex=.22,.255,.285
        shoulder=(.415,.025,1.40);elbow=(.595,-.03,.99);wrist=(.675,-.13,.51)
        head_y,head_z=-.22,1.55
        sections=[(.56,0,.02,.28,.25),(.69,0,-.05,.38,.40),(.84,0,-.075,.47,.49),
            (1.03,0,-.08,.49,.51),(1.21,0,-.04,.46,.45),(1.37,0,.005,.44,.30),
            (1.48,0,-.015,.34,.22),(1.53,0,-.05,.11,.09)]
    parts=[rings('Torso anatomical loft',sections,'Skin',24)]
    # Neck follows the forward-hunched spine and meets the jaw.
    parts.append(tube('Hunched neck',[(0,-.05,1.49),(0,head_y+.09,head_z-.065),(0,head_y+.01,head_z-.025)],[.085,.075,.075],'Skin',16))
    headrows=[]
    for j in range(25):
        t=j/24;a=.01+(math.pi-.02)*t
        z=head_z+.15*math.cos(a);rx=.112*math.sin(a)
        row=[]
        for i in range(40):
            theta=i*2*math.pi/40;x=rx*math.sin(theta)
            y=head_y-.108*math.sin(a)*math.cos(theta)
            if math.cos(theta)>0:
                # Angular brow, narrow nasal ridge and hollow cheeks, modeled in skin.
                y-=.027*math.exp(-.5*(x/.018)**2)*math.exp(-.5*((z-(head_z-.005))/.026)**2)
                y+=.012*math.exp(-.5*((abs(x)-.058)/.020)**2)*math.exp(-.5*((z-(head_z-.045))/.025)**2)
                y-=.008*math.exp(-.5*((z-(head_z+.03))/.012)**2)
            row.append((x,y,z))
        headrows.append(row)
    parts.append(loft('Head anatomical surface',headrows,'Skin'))
    for s,side in [(1,'L'),(-1,'R')]:
        # Deltoid/triceps, exposed elbow, long tendon forearm: no capsule primitives.
        upper=.102 if not bulk else .158;fore=.059 if not bulk else .112
        points=[(s*(shoulder[0]-.04),shoulder[1],shoulder[2]),(s*(shoulder[0]+.035),.025,shoulder[2]-.08),
                (s*(elbow[0]-.025),elbow[1]+.01,elbow[2]+.10),(s*elbow[0],elbow[1],elbow[2]),
                (s*(elbow[0]+.015),elbow[1]-.005,elbow[2]-.08),(s*wrist[0],wrist[1]+.02,wrist[2]+.13),(s*wrist[0],wrist[1],wrist[2])]
        # Inner arms of Conjoined will be moved forward after the common form is built.
        parts.append(tube('Arm anatomy',points,[upper*.88,upper,upper*.72,fore*.80,fore,fore*.72,fore*.57],'Skin',14))
        handx=s*(wrist[0]+.012);handz=wrist[2]-.11
        parts.append(tube('Long palm',[(s*wrist[0],wrist[1],wrist[2]+.01),(handx,wrist[1]-.025,handz+.04),(handx,wrist[1]-.035,handz-.01)],
            [.038 if not bulk else .055,.051 if not bulk else .076,.044 if not bulk else .064],'Skin',12,.66))
        for k in range(4):
            dx=(k-1.5)*(.023 if not bulk else .033)
            x=handx+dx;z=handz+.005-abs(k-1.5)*.008
            length=[.105,.145,.14,.11][k]*(1.05 if bulk else 1)
            parts.append(tube('Finger tendon',[(x,wrist[1]-.04,z),(x+s*.006,wrist[1]-.05,z-length*.62),
                   (x+s*.004,wrist[1]-.08,z-length*.92),(x,wrist[1]-.09,z-length)],
                   [.015 if not bulk else .022,.013 if not bulk else .019,.011 if not bulk else .014,.007 if not bulk else .010],'Skin',8))
        parts.append(tube('Thumb',[(handx-s*.032,wrist[1]-.01,handz+.09),(handx-s*.065,wrist[1]-.045,handz+.035),
                (handx-s*.058,wrist[1]-.07,handz-.005)],[.023,.018,.009],'Skin',10))
        thigh=.087 if not bulk else .14;calf=.060 if not bulk else .10
        parts.append(rings('Leg anatomy',[(ankle,s*anklex,.015,.040 if not bulk else .06,.046 if not bulk else .07),
                (ankle+.12,s*anklex,.025,calf*.74,calf*.78),(knee-.07,s*kneex,.035,calf,calf),
                (knee,s*kneex,-.005,calf*.78,calf*.86),(knee+.10,s*hipx,.015,thigh*.83,thigh*.88),
                (hip-.05,s*hipx,.025,thigh,thigh),(hip+.065,s*hipx,.03,thigh*.91,thigh*.92)],'Skin',16))
        fw=.061 if not bulk else .09;fl=.115 if not bulk else .14
        parts.append(rings('Bare foot',[(0,s*anklex,-.055,fw*.94,fl),(.025,s*anklex,-.060,fw,fl),
            (.06,s*anklex,-.045,fw*.94,fl*.88),(ankle+.035,s*anklex,.015,fw*.65,fl*.40)],'Skin',16))
    skin=join(label+'_Skin',parts)
    rem=skin.modifiers.new('Unify anatomical surfaces','REMESH');rem.mode='VOXEL';rem.voxel_size=.008 if not bulk else .011
    apply(skin,rem)
    relax=skin.modifiers.new('Keep skin transitions coherent','SMOOTH');relax.factor=.23;relax.iterations=2;apply(skin,relax)
    skin.data.calc_loop_triangles();dec=skin.modifiers.new('Keep silhouette within working budget','DECIMATE')
    dec.ratio=min(.9,skin_budget/max(1,len(skin.data.loop_triangles)));apply(skin,dec)
    for p in skin.data.polygons:p.use_smooth=True

    # Head wraps form a continuous spiraling linen ribbon around the cranium.
    rows=[]
    for i in range(100):
        a=i*2*math.pi/32;z=head_z+.045+.055*i/99
        x=.113*math.cos(a);y=head_y+.113*math.sin(a)
        rows.append([(x,y,z-.017),(x*1.01,head_y+(y-head_y)*1.01,z+.017),
                     (x*.97,head_y+(y-head_y)*.97,z+.017),(x*.97,head_y+(y-head_y)*.97,z-.017)])
    loft('Head winding',rows,'Wrap',body=label,region='head')
    # Sunken, dark eyes and a downturned mouth: no doll-like eyeballs or colored decoys.
    for s in [-1,1]:
        x=s*.044;z=head_z+.017
        hit,p,n,index=skin.ray_cast(Vector((x,-2,z)),Vector((0,1,0)))
        y=p.y-.001 if hit else head_y-.105
        sphere('Sunken eye',(x,y,z),(.020,.0035,.007),'Recess',16,6,region='head',body=label)
    tube('Mouth crease',[(-.030,head_y-.092,head_z-.073),(0,head_y-.100,head_z-.080),(.030,head_y-.092,head_z-.073)],
        [.001,.0025,.001],'Recess',6,region='head',body=label)
    for s,side in [(1,'L'),(-1,'R')]:
        for j in range(3):
            z=wrist[2]+.045+j*.038;x=s*wrist[0]
            hoop('Forearm linen',(x,wrist[1]+.012,z),(.043 if not bulk else .066),(.042 if not bulk else .068),.023,'Wrap',region='forearm.'+side,body=label)
        # Leather shoulder harness and broad waist brace.
        strap('Shoulder harness',[(s*.115,-.09,.90),(s*(.14 if not bulk else .27),-.115,1.19),
            (s*(.19 if not bulk else .35),-.09,1.43),(s*(.20 if not bulk else .35),.07,1.49),
            (s*.13,.15,.94)],.032 if not bulk else .055,body=label,region='torso')
    hoop('Waist brace',(0,.03,.885 if not bulk else .69),.16 if not bulk else .39,.12 if not bulk else .40,.045,'Leather',body=label,region='pelvis')
    # Ragged cloth panels, one coherent skirt surface with irregular lower edge.
    n=20;rows=[]
    for level in range(3):
        row=[]
        for i in range(n):
            a=i*2*math.pi/n;radius=(.157+level*.014) if not bulk else (.31+level*.03)
            z=(.88 if not bulk else .67)-level*(.095 if not bulk else .065)
            if level==2:z-=.035*(1+math.sin(i*2.7))
            row.append((radius*math.sin(a),.025-(.123+level*.015 if not bulk else .31)*math.cos(a),z))
        rows.append(row)
    loft('Torn waist cloth',rows,'Cloth',body=label,region='pelvis',smooth=False)
    # One braced shin and foot; the other remains anatomical and wrapped.
    s=1;x=s*anklex
    strap('Shin splint',[(x,-.071,ankle+.05),(s*kneex,-.082,knee+.03)],.055 if not bulk else .085,'Metal',region='shin.L',body=label)
    for z in [ankle+.08,knee-.02]:
        hoop('Splint fastener',(x,.01,z),.066 if not bulk else .10,.077 if not bulk else .12,.027,'Leather',region='shin.L',body=label)
    for z in [ankle+.06,ankle+.10]:hoop('Ankle wrap',(-anklex,.015,z),.045 if not bulk else .067,.055 if not bulk else .08,.024,'Wrap',region='shin.R',body=label)
    # All body-local forms are transformed together, including authored bone coordinates.
    created=[ob for ob in BODY.objects if ob not in before]
    for ob in created:
        ob['body']=label
        for v in ob.data.vertices:v.co=Vector((offset,0,0))+v.co*scale
    def p(v):return Vector((offset,0,0))+Vector(v)*scale
    spec={'label':label,'bulk':bulk,'offset':offset,'scale':scale,
        'hip':p((0,.025,hip)),'chest':p((0,.025,1.38 if not bulk else 1.35)),
        'neck':p((0,-.055,1.51)),'head':p((0,head_y,head_z-.085)),
        'head_tip':p((0,head_y-.005,head_z+.12)),
        'shoulder':{side:p((s*shoulder[0],shoulder[1],shoulder[2])) for s,side in [(1,'L'),(-1,'R')]},
        'elbow':{side:p((s*elbow[0],elbow[1],elbow[2])) for s,side in [(1,'L'),(-1,'R')]},
        'wrist':{side:p((s*wrist[0],wrist[1],wrist[2])) for s,side in [(1,'L'),(-1,'R')]},
        'hand':{side:p((s*(wrist[0]+.012),wrist[1]-.035,wrist[2]-.17)) for s,side in [(1,'L'),(-1,'R')]},
        'leg_hip':{side:p((s*hipx,.025,hip)) for s,side in [(1,'L'),(-1,'R')]},
        'knee':{side:p((s*kneex,-.005,knee)) for s,side in [(1,'L'),(-1,'R')]},
        'ankle':{side:p((s*anklex,.015,ankle)) for s,side in [(1,'L'),(-1,'R')]}}
    return spec


def mechanism(kind):
    if kind=='patient':
        circle('Chest mechanism bezel',(0,-.118,1.25),.147,.023,'Brass',plane='XZ',region='chest')
        sphere('Chest mechanism recess',(0,-.124,1.25),(.12,.016,.12),'Recess',24,8,region='chest')
        for s in [-1,1]:
            tube('Core feed pipe',[(s*.115,-.125,1.31),(s*.150,-.10,1.47),(s*.13,.015,1.65),(s*.10,.015,1.72)],
                 [.014]*4,'Metal',10,region='torso')
        circle('Raised core collar',(0,0,1.73),.24,.022,'Brass',region='root')
        part=bpy.data.objects.new('YellowCore',None);PART.objects.link(part);part.location=(0,0,1.75)
        ob=sphere('YellowCore_Lens',(0,0,0),(.224,.224,.090),'Yellow',32,16,collection=PART,region='static')
        ob.parent=part
        part['marker_godot']=[0,1.75,0]
        part['art_adaptation']='chest drum feeds raised upward-facing lens, matching existing core marker exactly'
    elif kind=='conjoined':
        part=bpy.data.objects.new('BlueConnector',None);PART.objects.link(part);part.location=(0,0,.85)
        ob=tube('BlueConnector_Hose',[(-.4,0,0),(-.25,.025,-.015),(0,.035,-.018),(.25,.025,-.015),(.4,0,0)],
            [.125,.13,.13,.13,.125],'Blue',20,collection=PART,region='static');ob.parent=part
        for x in [-.40,.40]:
            ob=tube('Hose ferrule',[(x-.025,0,0),(x+.025,0,0)],[.145,.145],'Metal',20,collection=PART,region='static');ob.parent=part
        part['endpoints_godot']=[[-.4,.85,0],[.4,.85,0]]
        for name,x in [('CableStart',.4),('CableEnd',-.4)]:
            anchor=bpy.data.objects.new(name,None);PART.objects.link(anchor);anchor.parent=part;anchor.location=(x,0,0)
    else:
        part=bpy.data.objects.new('OrangePlate',None);PART.objects.link(part);part.location=(0,-.95,.12)
        # Broad front panel plus a swept mantle, so orange remains readable from above.
        rows=[];n=24
        for k in range(5):
            t=k/4;row=[]
            for i in range(n):
                a=i*2*math.pi/n
                x=.7175*math.sin(a)*(1-.06*t)
                z=.50+.50*math.cos(a)*(1-.06*t)
                y=-.070+(.07 if k==0 else .12)*t
                row.append((x,y,z))
            rows.append(row)
        cover=loft('OrangePlate_Front',rows,'Orange',collection=PART,region='static');cover.parent=part
        verts=[(-.62,.03,.94),(.62,.03,.94),(.48,.50,1.25),(-.48,.50,1.25),(-.60,.065,.91),(.60,.065,.91),(.46,.51,1.22),(-.46,.51,1.22)]
        mantle=mesh('OrangePlate_UpperMantle',verts,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],'Orange',collection=PART,region='static')
        bevel=mantle.modifiers.new('Soft metal edges','BEVEL');bevel.width=.045;bevel.segments=2;apply(mantle,bevel);mantle.parent=part
        for x in [-.59,.59]:
            ob=tube('Plate edge brace',[(x,-.075,.12),(x,-.075,.9),(x*.82,.48,1.22)],[.019]*3,'Metal',8,collection=PART,region='static');ob.parent=part
        for s in [-1,1]:
            tube('Cover standoff',[(s*.35,-.28,1.15),(s*.59,-.91,1.03)],[.035,.035],'Leather',10,region='chest')
        part['marker_origin_godot']=[0,.12,-.95]
        part['reference_radius']=.7
        part['art_adaptation']='front envelope matches current plate; an upper mantle adds overhead visibility'


def refine_anatomy(specs,kind):
    """Second bounded pass: clear fingers, gaunt facial planes and a seated core."""
    if bpy.context.scene.get('mesh_revision',0)>=2:return
    for spec in specs:
        label=spec['label'];scale=spec['scale'];offset=spec['offset'];bulk=spec['bulk']
        skin=next(o for o in BODY.objects if o.type=='MESH' and o.get('body')==label and o.get('surface')=='Skin')
        bm=bmesh.new();bm.from_mesh(skin.data)
        remove=[]
        for v in bm.verts:
            for s,side in [(1,'L'),(-1,'R')]:
                wrist=spec['wrist'][side]
                if v.co.z<wrist.z-.075*scale and abs(v.co.x-wrist.x)<(.12 if bulk else .09)*scale:
                    remove.append(v);break
        bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(skin.data);bm.free()
        # Taper the trimmed wrist boundary inside the new palm overlap. The
        # finger geometry remains explicit, with clear gaps, rather than voxel-fused.
        for v in skin.data.vertices:
            for sign,side in [(1,'L'),(-1,'R')]:
                wrist=spec['wrist'][side]
                if wrist.z-.080*scale<v.co.z<wrist.z-.055*scale and abs(v.co.x-wrist.x)<.10*scale:
                    t=max(0,min(1,(wrist.z-.055*scale-v.co.z)/(.020*scale)))
                    cx=wrist.x+sign*.012*scale;cy=wrist.y-.030*scale
                    v.co.x=cx+(v.co.x-cx)*(1-.30*t);v.co.y=cy+(v.co.y-cy)*(1-.30*t)
        bpy.context.scene['wrist_overlap_revision']=1
        for s,side in [(1,'L'),(-1,'R')]:
            wrist=spec['wrist'][side];hx=wrist.x+s*.012*scale;hy=wrist.y-.030*scale
            width=(.062 if bulk else .046)*scale
            rings('Rebuilt long palm',[(wrist.z-.03*scale,hx,hy,width*.70,.025*scale),
                (wrist.z-.095*scale,hx,hy,width,.027*scale),(wrist.z-.135*scale,hx,hy,width*.9,.025*scale)],
                'Skin',12,body=label,region='hand.'+side)
            for k in range(4):
                x=hx+(k-1.5)*(.034 if bulk else .025)*scale;z=wrist.z-.125*scale
                length=[.105,.155,.145,.115][k]*scale
                tube('Separated knuckle and finger',[(x,hy-.006*scale,z),(x+s*.004*scale,hy-.014*scale,z-length*.50),
                    (x+s*.002*scale,hy-.040*scale,z-length*.88),(x,hy-.052*scale,z-length)],
                    [(.015 if bulk else .0115)*scale,(.014 if bulk else .0105)*scale,.008*scale,.0048*scale],
                    'Skin',8,body=label,region='hand.'+side)
            tube('Hooked thumb',[(hx-s*width*.65,hy+.008*scale,wrist.z-.075*scale),
                (hx-s*width*1.30,hy-.020*scale,wrist.z-.125*scale),
                (hx-s*width*1.15,hy-.040*scale,wrist.z-.165*scale)],
                [.019*scale,.014*scale,.006*scale],'Skin',10,body=label,region='hand.'+side)
        head=spec['head']+Vector((0,0,.085*scale));head_y=head.y
        for v in skin.data.vertices:
            if v.co.z<.015*scale:v.co.z=0
            local=(v.co-Vector((offset,0,0)))/scale
            dz=(v.co.z-head.z)/scale
            if v.co.y<head_y-.035*scale and -.14<dz<.13:
                jaw=math.exp(-.5*((dz+.085)/.035)**2)
                v.co.x=offset+(v.co.x-offset)*(1-.12*jaw)
                nose=.010*math.exp(-.5*((v.co.x-offset)/(.020*scale))**2)*math.exp(-.5*(dz/.03)**2)
                v.co.y-=nose*scale
        for s in [-1,1]:
            points=[head+Vector((s*x,y,z))*scale for x,y,z in [(.018,-.101,.045),(.043,-.111,.046),(.071,-.098,.032)]]
            tube('Heavy brow plane',points,[.005*scale,.010*scale,.003*scale],'Skin',8,body=label,region='head')
        for ob in BODY.objects:
            if ob.type=='MESH' and ob.get('body')==label and ob.get('surface')=='Recess':
                for v in ob.data.vertices:
                    dz=(v.co.z-head.z)/scale
                    if dz>-.015:
                        cx=offset+(.044 if v.co.x>offset else -.044)*scale
                        v.co.x=cx+(v.co.x-cx)*1.35;v.co.y-=.003*scale
    if kind=='patient':
        rings('Spinal core housing',[(1.46,0,.035,.145,.13),(1.53,0,.035,.178,.17),
            (1.65,0,.025,.19,.18),(1.72,0,0,.21,.20)],'Metal',24,region='root')
        for z in [1.53,1.59,1.65]:hoop('Housing compression ring',(0,.025,z),.188,.18,.018,'Brass',region='root')
    bpy.context.scene['mesh_revision']=2


def new_scene(kind):
    global BODY,PART,M
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):bpy.data.collections.remove(c)
    for a in list(bpy.data.actions):bpy.data.actions.remove(a)
    for m in list(bpy.data.materials):bpy.data.materials.remove(m)
    BODY=bpy.data.collections.new('BODY | editable anatomy');PART=bpy.data.collections.new('PARTS | independently removable')
    bpy.context.scene.collection.children.link(BODY);bpy.context.scene.collection.children.link(PART)
    colors={'Skin':('ADA59A',0),'Wrap':('A79B83',0),'Leather':('514234',0),'Cloth':('746957',0),'Metal':('59605F',.55),
        'Brass':('7D7155',.55),'Recess':('30312E',0),'Yellow':('FFD340',.1),'Blue':('258AF1',.05),'Orange':('D96A29',.15)}
    M={name:mat(name,color,metal, .45 if name in ['Yellow','Blue','Orange'] else 0) for name,(color,metal) in colors.items()}
    if kind=='patient':specs=[body_form('A')]
    elif kind=='conjoined':
        specs=[body_form('A',offset=-.58,scale=.96,skin_budget=6000),body_form('B',offset=.58,scale=.87,skin_budget=5600)]
        # Forward inner forearms clear the blue span rather than passing through it.
        for ob in BODY.objects:
            spec=specs[0 if ob['body']=='A' else 1];direction=1 if ob['body']=='A' else -1
            for v in ob.data.vertices:
                inner=(v.co.x-spec['offset'])*direction
                if inner>.23*spec['scale'] and .3<v.co.z<1.28:
                    fade=max(0,min(1,(1.38-v.co.z)/.18))
                    v.co.y-=.20*min(1,inner/(.35*spec['scale']))*fade
        for spec in specs:
            side='L' if spec['label']=='A' else 'R'
            for key in ['elbow','wrist','hand']:spec[key][side].y-=.20
    else:specs=[body_form('A',bulk=True,skin_budget=9500)]
    mechanism(kind)
    bpy.context.scene['creature_kind']=kind
    bpy.context.scene['body_specs']=json.dumps([{k:({a:list(b) for a,b in v.items()} if isinstance(v,dict) else list(v) if isinstance(v,Vector) else v) for k,v in s.items()} for s in specs])
    bpy.context.scene['mesh_revision']=1
    return specs


def studio(kind,iteration):
    scene=bpy.context.scene
    old=bpy.data.collections.get('REVIEW | excluded')
    if old:
        for ob in list(old.objects):bpy.data.objects.remove(ob,do_unlink=True)
        bpy.data.collections.remove(old)
    c=bpy.data.collections.new('REVIEW | excluded');scene.collection.children.link(c)
    floor=mesh('Review ground',[(-100,-100,-.007),(100,-100,-.007),(100,100,-.007),(-100,100,-.007)],[(0,1,2,3)],'Recess',collection=c)
    for name,pos,power,size in [('Key',(-3,-4,6),500,4),('Fill',(4,-1,3),240,3),('Rim',(1,4,4),550,3)]:
        d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size
        ob=bpy.data.objects.new(name,d);c.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((0,0,.9))-ob.location).to_track_quat('-Z','Y').to_euler()
    d=bpy.data.cameras.new('Review camera');cam=bpy.data.objects.new('Review camera',d);c.objects.link(cam);d.type='ORTHO'
    scene.camera=cam;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=SETTINGS.get('samples',24);scene.cycles.use_denoising=False
    scene.render.threads_mode='FIXED';scene.render.threads=4;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
    scene.world.color=(.16,.16,.16);scene.view_settings.view_transform='AgX'
    target=Vector((0,0,.92));width=2.35 if kind!='conjoined' else 2.95
    views=['three-quarter','front','overhead'] if iteration==1 else ['three-quarter','back','overhead','walk']
    directory=OUT/('iteration-%02d'%iteration)/kind;directory.mkdir(parents=True,exist_ok=True)
    rig=next((o for o in BODY.objects if o.type=='ARMATURE'),None)
    for name in views:
        scene.render.resolution_x=1000;scene.render.resolution_y=1000;d.ortho_scale=width
        cam.location={'front':(0,-6,.92),'back':(0,6,.92),'overhead':(0,-4,6)}.get(name,(3,-5,2.6))
        cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
        if rig:
            rig.animation_data.action=bpy.data.actions['Walk' if name=='walk' else 'Idle'];scene.frame_set(10 if name=='walk' else 1)
        scene.render.filepath=str(directory/(name+'.png'));bpy.ops.render.render(write_still=True);print('CREATURE_RENDER',scene.render.filepath,flush=True)
    if rig:rig.animation_data.action=bpy.data.actions['Idle'];scene.frame_set(1)
    for ob in c.objects:ob.hide_set(True)
    return c


def main():
    global BODY,PART,M
    iteration=SETTINGS.get('iteration',1)
    for kind in SETTINGS.get('models',['patient']):
        path=SOURCE/(kind+'.blend')
        if path.exists():
            bpy.ops.wm.open_mainfile(filepath=str(path))
            if bpy.context.scene.get('creature_kind')!=kind:raise RuntimeError('Wrong authored source')
            BODY=bpy.data.collections['BODY | editable anatomy'];PART=bpy.data.collections['PARTS | independently removable']
            M={m.name:m for m in bpy.data.materials}
            specs=json.loads(bpy.context.scene['body_specs'])
            for spec in specs:
                for key,value in list(spec.items()):
                    if isinstance(value,dict):spec[key]={a:Vector(b) for a,b in value.items()}
                    elif isinstance(value,list):spec[key]=Vector(value)
            if iteration<2:raise RuntimeError('Existing mesh: review before refining; do not rebuild over authored source')
        else:specs=new_scene(kind)
        scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
        if iteration>=2:
            refine_anatomy(specs,kind)
            sys.path.insert(0,str(SOURCE))
            from family_rig import add_rig
            add_rig(BODY,specs)
        # Consolidate only by body/material, retaining independently removable parts.
        for label in ['A','B']:
            for surface in list(M):
                objects=[o for o in BODY.objects if o.type=='MESH' and o.get('body')==label and o.get('surface')==surface]
                if len(objects)>1:join(label+'_'+surface,objects)
                elif objects:objects[0].name=label+'_'+surface
        review=studio(kind,iteration)
        root=bpy.data.objects.get('EnemyRoot')
        if root is None:
            root=bpy.data.objects.new('EnemyRoot',None);scene.collection.objects.link(root)
        for ob in list(BODY.objects)+list(PART.objects):
            if ob.parent is None:ob.parent=root
        scene.frame_set(1);bpy.context.view_layer.update()
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(path))
        root.rotation_euler.z=math.pi
        bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
        for ob in list(BODY.objects)+list(PART.objects):ob.select_set(True)
        bpy.context.view_layer.objects.active=root;bpy.context.view_layer.update()
        bpy.ops.export_scene.gltf(filepath=str(ASSETS/(kind+'.glb')),export_format='GLB',use_selection=True,export_yup=True,
            export_materials='EXPORT',export_extras=True,export_animations=iteration>=2,export_animation_mode='ACTIONS',
            export_force_sampling=True,export_frame_range=False,export_anim_slide_to_zero=True,export_cameras=False,export_lights=False)
        root.rotation_euler.z=0
        stats={'kind':kind,'triangles':0,'meshes':0,'materials':set(),'bones':0,'source':str(path),'export':str(ASSETS/(kind+'.glb'))}
        for ob in list(BODY.objects)+list(PART.objects):
            if ob.type=='MESH':
                ob.data.calc_loop_triangles();stats['triangles']+=len(ob.data.loop_triangles);stats['meshes']+=1;stats['materials'].update(m.name for m in ob.data.materials)
            elif ob.type=='ARMATURE':stats['bones']+=len(ob.data.bones)
        stats['materials']=sorted(stats['materials']);stats['animations']=['Idle','Walk'] if iteration>=2 else []
        (OUT/(kind+'-stats.json')).write_text(json.dumps(stats,indent=2)+'\n');print('CREATURE_STATS',json.dumps(stats),flush=True)


main()
