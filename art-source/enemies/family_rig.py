"""Small in-place creature rig. Baked FK/IK authoring, no runtime integration."""
import bpy,math
from mathutils import Vector,Matrix,Euler


def ease(a,b,v):
    t=max(0,min(1,(v-a)/(b-a)));return t*t*(3-2*t)


def add_rig(collection,specs):
    if any(o.type=='ARMATURE' for o in collection.objects):
        raise RuntimeError('Existing creature rig: review edits before rebuilding animation or weights')
    data=bpy.data.armatures.new('CreatureSkeleton');rig=bpy.data.objects.new('CreatureRig',data);collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    def bone(name,head,tail,parent=None):
        b=data.edit_bones.new(name);b.head=head;b.tail=tail
        if parent:b.parent=data.edit_bones[parent]
    bone('root',(0,0,0),(0,0,.15))
    for s in specs:
        p=s['label']+'.';scale=s['scale'];hip=s['hip'];chest=s['chest'];neck=s['neck'];head=s['head']
        bone(p+'pelvis',hip,hip+Vector((0,0,.14*scale)),'root')
        bone(p+'spine',hip+Vector((0,0,.14*scale)),chest-Vector((0,0,.14*scale)),p+'pelvis')
        bone(p+'chest',chest-Vector((0,0,.14*scale)),neck,p+'spine')
        bone(p+'neck',neck,head,p+'chest');bone(p+'head',head,s['head_tip'],p+'neck')
        for side in ['L','R']:
            bone(p+'upper_arm.'+side,s['shoulder'][side],s['elbow'][side],p+'chest')
            bone(p+'forearm.'+side,s['elbow'][side],s['wrist'][side],p+'upper_arm.'+side)
            bone(p+'hand.'+side,s['wrist'][side],s['hand'][side],p+'forearm.'+side)
            bone(p+'thigh.'+side,s['leg_hip'][side],s['knee'][side],p+'pelvis')
            bone(p+'shin.'+side,s['knee'][side],s['ankle'][side],p+'thigh.'+side)
            bone(p+'foot.'+side,s['ankle'][side],s['ankle'][side]+Vector((0,-.13*scale,-.06*scale)),p+'shin.'+side)
    bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True
    for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
    for ob in list(collection.objects):
        if ob.type!='MESH':continue
        s=next(s for s in specs if s['label']==ob.get('body','A'));p=s['label']+'.';scale=s['scale'];offset=s['offset'];bulk=s['bulk']
        groups={b.name:ob.vertex_groups.new(name=b.name) for b in data.bones}
        for v in ob.data.vertices:
            x=(v.co.x-offset)/scale;y=v.co.y/scale;z=v.co.z/scale
            side='L' if x>=0 else 'R';hip=s['hip'].z/scale;knee=s['knee'][side].z/scale;ankle=s['ankle'][side].z/scale
            surface=ob.get('surface');region=ob.get('region')
            arm_threshold=(.35 if z>1.16 else .50) if bulk else .205
            if region=='root':w={'root':1}
            elif surface=='Cloth':w={p+'pelvis':1}
            elif surface in ['Metal','Brass'] and z>1.65 and y>-.25:w={'root':1}
            elif z>(s['head'].z/scale-.03) and y<(s['head'].y/scale+.13):
                t=ease(s['neck'].z/scale-.025,s['head'].z/scale+.025,z);w={p+'neck':1-t,p+'head':t}
            elif abs(x)>arm_threshold and .18<z<1.5:
                elbow=s['elbow'][side];wrist=s['wrist'][side]
                t=(v.co-elbow).dot((wrist-elbow).normalized())/scale
                f=ease(-.025,.035,t)
                h=ease(-.02,.025,(v.co-wrist).dot((s['hand'][side]-wrist).normalized())/scale)
                w={p+'upper_arm.'+side:(1-f)*(1-h),p+'forearm.'+side:f*(1-h),p+'hand.'+side:h}
            elif z<hip+.03:
                if z<ankle+.07:
                    t=ease(ankle-.015,ankle+.09,z);w={p+'foot.'+side:1-t,p+'shin.'+side:t}
                elif z<knee+.10:
                    t=ease(knee-.08,knee+.10,z);w={p+'shin.'+side:1-t,p+'thigh.'+side:t}
                else:
                    t=ease(hip-.12,hip+.03,z);w={p+'thigh.'+side:1-t,p+'pelvis':t}
            else:
                if z<hip+.20:
                    t=ease(hip+.02,hip+.20,z);w={p+'pelvis':1-t,p+'spine':t}
                else:
                    t=ease(hip+.22,s['chest'].z/scale-.025,z);w={p+'spine':1-t,p+'chest':t}
            total=sum(w.values())
            for name,value in w.items():
                if value>.00001:groups[name].add([v.index],value/total,'REPLACE')
        used={g.group for v in ob.data.vertices for g in v.groups}
        for g in reversed(list(ob.vertex_groups)):
            if g.index not in used:ob.vertex_groups.remove(g)
        mod=ob.modifiers.new('Creature linear skin deformation','ARMATURE');mod.object=rig
        ob.parent=rig;ob.matrix_parent_inverse=Matrix.Identity(4)
    rest={b.name:b.matrix_local.copy() for b in data.bones};desired={}
    def fk(name,angles=(0,0,0)):
        b=data.bones[name]
        base=desired[b.parent.name]@rest[b.parent.name].inverted()@rest[name] if b.parent else rest[name]
        desired[name]=base@Euler(angles,'XYZ').to_matrix().to_4x4();return desired[name]
    def direct(name,head,tail):
        b=data.bones[name];q=(b.tail_local-b.head_local).rotation_difference(Vector(tail)-Vector(head))
        m=(q.to_matrix()@rest[name].to_3x3()).to_4x4();m.translation=head;desired[name]=m
    def ik(first,second,start,target,pole):
        start=Vector(start);target=Vector(target);axis=(target-start).normalized()
        a=data.bones[first].length;b=data.bones[second].length;d=min((target-start).length,a+b-.0005)
        target=start+axis*d;along=(a*a-b*b+d*d)/(2*d)
        bend=Vector(pole)-start-axis*(Vector(pole)-start).dot(axis);bend.normalize()
        joint=start+axis*along+bend*math.sqrt(max(0,a*a-along*along))
        direct(first,start,joint);direct(second,joint,target);return target
    rig.animation_data_create();scene=bpy.context.scene;scene.render.fps=30
    for name,end,step in [('Idle',61,3),('Walk',37,1)]:
        action=bpy.data.actions.new(name);action.use_fake_user=True;action.use_frame_range=True;action.frame_start=1;action.frame_end=end
        rig.animation_data.action=action
        for frame in range(1,end+1,step):
            phase=2*math.pi*(frame-1)/(end-1);walking=name=='Walk';desired.clear();desired['root']=rest['root'].copy()
            for index,s in enumerate(specs):
                p=s['label']+'.';scale=s['scale'];phase2=phase+index*math.pi*.5;bulk=s['bulk']
                fk(p+'pelvis')
                desired[p+'pelvis'].translation.z+=(-.025+.003*math.sin(phase*2)**2)*scale if walking else 0
                fk(p+'spine',(.012*math.sin(phase),0,0));fk(p+'chest',(-.009*math.sin(phase),.010*math.sin(phase2) if walking else 0,0))
                fk(p+'neck');fk(p+'head',(0,.010*math.sin(phase),0))
                for sign,side in [(1,'L'),(-1,'R')]:
                    legphase=phase2+(math.pi if sign<0 else 0)
                    thigh=p+'thigh.'+side;shin=p+'shin.'+side;foot=p+'foot.'+side
                    h=(desired[p+'pelvis']@rest[p+'pelvis'].inverted()@rest[thigh]).translation
                    target=s['ankle'][side].copy()
                    if walking:
                        target.y-=.105*scale*math.sin(legphase);target.z+=.040*scale*max(0,math.cos(legphase))**2
                    anklepos=ik(thigh,shin,h,target,s['knee'][side]+Vector((0,-.25*scale,0)))
                    desired[foot]=rest[foot].copy();desired[foot].translation=anklepos
                    upper=p+'upper_arm.'+side;fore=p+'forearm.'+side;hand=p+'hand.'+side
                    sh=(desired[p+'chest']@rest[p+'chest'].inverted()@rest[upper]).translation
                    wrist=s['wrist'][side]+Vector((0,.035*scale*math.sin(legphase) if walking else 0,.012*scale))
                    wristpos=ik(upper,fore,sh,wrist,s['elbow'][side]+Vector((sign*.10*scale,.06*scale,0)))
                    desired[hand]=rest[hand].copy();desired[hand].translation=wristpos
            for b in data.bones:
                args={'parent_matrix':desired[b.parent.name],'parent_matrix_local':rest[b.parent.name]} if b.parent else {}
                pb=rig.pose.bones[b.name];pb.matrix_basis=b.convert_local_to_pose(desired[b.name],rest[b.name],invert=True,**args)
                pb.keyframe_insert('location',frame=frame,group=b.name);pb.keyframe_insert('rotation_quaternion',frame=frame,group=b.name);pb.keyframe_insert('scale',frame=frame,group=b.name)
        for curve in action.fcurves:
            for key in curve.keyframe_points:key.interpolation='LINEAR'
    rig.animation_data.action=bpy.data.actions['Idle'];scene.frame_start=1;scene.frame_end=61;scene.frame_set(1)
    bpy.context.view_layer.update()
    return rig
