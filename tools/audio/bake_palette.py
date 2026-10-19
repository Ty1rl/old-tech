#!/usr/bin/env python3
"""Bake the softer Round P museum SFX; no runtime sample synthesis or source audio.
Requires numpy for offline authoring only. Run from any directory. Deterministic.
"""
from pathlib import Path
import argparse, hashlib, json, wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / 'audio/combat'
RATE = 22050
TAU = 2 * np.pi
ASSETS = {}
CUES = []

def tone(t, freq, decay=12, amp=1):
    return amp * np.sin(TAU * freq * t) * np.exp(-decay*t)

def modal(t, root, decay=18):
    return sum(tone(t,root*r,decay*(1+i*.35),a) for i,(r,a) in enumerate([(1,.55),(2.71,.24),(4.13,.13),(6.23,.08)]))

def noise(t, seed, smooth=6):
    x=np.random.default_rng(seed).uniform(-1,1,len(t))
    return np.convolve(x, np.ones(smooth)/smooth, mode='same')

def body(t, freq, decay=25):
    # Short harmonic body instead of the old long, inharmonic metal partials.
    return tone(t,freq,decay,.8)+tone(t,freq*2,decay*1.8,.12)

def air_loop(t, seed, cutoff=1100):
    # A single baked periodic airflow texture, not a permanent runtime synth.
    x=np.random.default_rng(seed).uniform(-1,1,len(t))
    frequencies=np.fft.rfftfreq(len(t),1/RATE)
    return np.fft.irfft(np.fft.rfft(x)*np.exp(-(frequencies/cutoff)**4),n=len(t))

def bake(name, duration, make, looping=False):
    t=np.arange(round(duration*RATE))/RATE
    y=make(t)
    edge=np.minimum(1,np.minimum(t/.006,(t[-1]-t)/.018))
    # Loops are periodic by construction; only transient edges fade to zero.
    if not looping: y*=np.maximum(0,edge)
    y=y/max(.001,float(np.max(np.abs(y))))*.64
    pcm=np.round(y*32767).astype('<i2')
    path=BANK/(name+'.wav')
    with wave.open(str(path),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(pcm.tobytes())
    # Native WAV smpl loop metadata is recognized by Godot's WAV importer.
    if looping:
        import struct
        data=path.read_bytes();body=struct.pack('<9I6I',0,0,round(1e9/RATE),60,0,0,0,1,0,0,0,0,len(pcm)-1,0,0)
        data+=b'smpl'+struct.pack('<I',len(body))+body
        data=data[:4]+struct.pack('<I',len(data)-8)+data[8:];path.write_bytes(data)
    ASSETS[name]={'path':str(path.relative_to(ROOT)),'duration':duration,'loop':looping,'peak':float(np.max(np.abs(pcm)))/32768,'rms':float(np.sqrt(np.mean((pcm.astype(float)/32768)**2))),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}

def cue(name, asset=None, gain=-12, priority=2, responsive=False, cooldown=.08, pitch=1, effect=''):
    CUES.append(dict(id=name,asset=asset or name,gain=gain,priority=priority,responsive=responsive,cooldown=cooldown,pitch=pitch,effect=effect))

def build():
    BANK.mkdir(parents=True,exist_ok=True)
    # Short pew/body/air gestures; no bright ringing tail on repeated actions.
    bake('ring_launch',.18,lambda t: body(t,230,30)+.5*noise(t,1,15)*np.exp(-26*t))
    bake('ring_return',.14,lambda t: body(t,310,38)+tone(t,155,40,.25))
    bake('cable_cut',.12,lambda t: body(t,640,55)*.3+noise(t,2,10)*np.exp(-48*t))
    bake('hit',.11,lambda t: body(t,145,48)+noise(t,3,20)*np.exp(-50*t)*.25)
    bake('flash_fire',.14,lambda t: np.sin(TAU*(105*t+360*(1-np.exp(-28*t))/28))*np.exp(-25*t)+noise(t,4,16)*np.exp(-40*t)*.15)
    bake('flash_charged',.28,lambda t: body(t,68,18)*.85+np.sin(TAU*(130*t+430*(1-np.exp(-20*t))/20))*np.exp(-17*t)*.65+noise(t,5,15)*np.exp(-22*t)*.2)
    bake('flash_ready',.18,lambda t: tone(t,550,25,.7)+tone(np.maximum(0,t-.05),740,30,.35)*(t>=.05))
    bake('pierce_hit',.16,lambda t: noise(t,6,10)*np.exp(-35*t)+body(t,520,45)*.35)
    bake('cone_pulse',.16,lambda t: noise(t,7,12)*np.exp(-23*t)+tone(t,72,25,.14))
    bake('vent',.24,lambda t: noise(t,8,14)*np.exp(-14*t)+body(t,115,32)*.1)
    bake('core_break',.58,lambda t: modal(t,86,9)+noise(t,9)*np.exp(-12*t)+tone(t,43,8,.5))
    bake('repair_step',.24,lambda t: modal(t,520,27)+tone(np.maximum(0,t-.06),780,26,.5)*(t>=.06))
    bake('repair_full',.62,lambda t: sum(tone(np.maximum(0,t-d),f,12,a)*(t>=d) for d,f,a in [(0,440,.7),(.10,660,.6),(.20,880,.5)]))
    bake('room_open',.75,lambda t: tone(t,110,5,.6)+modal(np.maximum(0,t-.08),330,6)*(t>=.08)+noise(t,10,20)*np.exp(-7*t)*.5)
    bake('player_hurt',.48,lambda t: tone(t,48,9)+noise(t,11,12)*np.exp(-15*t)*1.2+modal(t,160,20)*.4)
    bake('recovery_confirm',.70,lambda t: sum(tone(np.maximum(0,t-d),f,8,a)*(t>=d) for d,f,a in [(0,220,.7),(.08,330,.5),(.16,440,.4)]))
    bake('ui_click',.09,lambda t: modal(t,610,70)+noise(t,12,2)*np.exp(-85*t)*.4)
    bake('emergency_start',.55,lambda t: body(t,54,7)+noise(t,81,18)*np.exp(-18*t)+tone(t,310,15,.2))
    bake('time_low_loop',1,lambda t: tone(np.mod(t,.5),85,24,.4)+air_loop(t,82,220)*.06,True)
    bake('repair_spin',.22,lambda t: noise(t,83,12)*np.exp(-19*t)+body(t,210,30)*.4)
    bake('repair_connect',.16,lambda t: body(t,480,42)+noise(t,84,3)*np.exp(-60*t)*.3)
    bake('repair_trace',.3,lambda t: noise(t,85,18)*np.sin(np.pi*t/.3)**2*.5)
    bake('scrub_older',1,lambda t: .45*np.sin(TAU*96*t)+.24*np.sin(TAU*192*t+.8*np.sin(TAU*5*t))+.10*np.sin(TAU*1370*t)*(np.sin(TAU*12*t)**8),True)
    bake('scrub_newer',1,lambda t: .4*np.sin(TAU*144*t)+.21*np.sin(TAU*288*t+.6*np.sin(TAU*7*t))+.08*np.sin(TAU*2050*t)*(np.sin(TAU*9*t)**8),True)
    bake('ring_loop',1,lambda t: (np.sin(TAU*144*t)*.4+np.sin(TAU*288*t)*.06)*(1+.06*np.cos(TAU*3*t))+air_loop(t,31,700)*.08,True)
    bake('charge_loop',1,lambda t: np.sin(TAU*176*t)*.4+np.sin(TAU*352*t)*.055,True)
    bake('cone_loop',1,lambda t: air_loop(t,32,1100)+np.sin(TAU*66*t)*.025,True)
    # Time motor and signed scrub content deliberately retain their identities.
    bake('clock_loop',1,lambda t: np.sin(TAU*64*t)*.30+np.sin(TAU*192*t)*.1+np.sin(TAU*1152*t)*(.5+.5*np.cos(TAU*8*t))**18*.35,True)
    families={'cable':(180,1),'glass':(360,2),'steam':(76,3),'shield':(120,4),'relay':(240,5),'pack':(235,6),'boss':(55,7)}
    for family,(freq,seed) in families.items():
        for event,duration,decay,mul in [('warning',.34,14,1.5),('attack',.16,30,1),('hurt',.10,48,1.5),('death',.36,16,.65)]:
            def make(t,f=freq*mul,d=decay,s=seed,event=event,family=family):
                x=body(t,f,d)
                if family=='steam': x=.1*x+noise(t,s,16)*np.exp(-d*t)
                elif family=='glass': x+=tone(t,f*2,d*2,.10)
                elif family=='relay': x*=.85+.15*np.cos(TAU*4*t)
                elif family=='pack': x+=noise(t,s,24)*np.exp(-d*t)*.2
                elif family=='boss': x+=tone(t,f*.5,d,.5)
                if event=='warning': x+=body(np.maximum(0,t-.10),f*1.12,d*1.6)*(t>=.10)*.30
                return x
            bake(f'{family}_{event}',duration,make)
    visual={'ring_launch':'ring_launch','ring_return':'ring_return','flash_fire':'flash_fire','flash_charged':'flash_fire','cone_pulse':'cone_pulse','hit':'hit','cable_cut':'cable_cut','vent':'vent','core_break':'core_break','repair_step':'repair_step','player_hurt':'player_hurt'}
    for name in ['ring_launch','ring_return','flash_fire','flash_charged','flash_ready','pierce_hit','cone_pulse','hit','cable_cut','vent','core_break','repair_step','repair_full','room_open','player_hurt','recovery_confirm','ui_click']:
        responsive=name in ['repair_step','repair_full','recovery_confirm','ui_click']
        priority=5 if name in ['player_hurt','recovery_confirm','repair_full'] else (4 if name in ['core_break','room_open','cable_cut','flash_charged'] else 2)
        gain={'ring_launch':-15,'ring_return':-18,'cable_cut':-14,'hit':-19,'flash_fire':-16,'flash_charged':-12,'flash_ready':-16,'pierce_hit':-15,'cone_pulse':-18,'vent':-17}.get(name,-10 if priority>=4 else -14)
        cue(name,gain=gain,priority=priority,responsive=responsive,cooldown=.08 if responsive else .10,effect=visual.get(name,''))
    cue('flash_pierce','flash_charged',gain=-12,priority=4,effect='flash_fire')
    cue('hostile_warning','relay_warning',gain=-15,priority=4,cooldown=.65,effect='hostile_warning')
    cue('hostile_fire','relay_attack',gain=-18,priority=3,effect='hostile_fire')
    for name in ['ring_loop','charge_loop','cone_loop','clock_loop','scrub_older','scrub_newer']:
        cue(name,gain=-24 if name in ['clock_loop','scrub_older','scrub_newer'] else -32,responsive=name in ['clock_loop','scrub_older','scrub_newer'])
    kinds={'target':'relay','swarmer':'pack','brute':'shield','skirmisher':'relay','warden':'shield','ranged':'relay','blue':'cable','yellow':'glass','orange':'steam','side_guard':'shield','front_guard':'shield','loop':'cable','zigzag':'cable','pair':'glass','loop_boss':'boss','sequence_boss':'boss','final_boss':'boss'}
    for i,(kind,family) in enumerate(kinds.items()):
        for event in ['warning','attack','hurt','death']:
            cue(f'enemy_{kind}_{event}',f'{family}_{event}',gain={'warning':-15,'attack':-18,'hurt':-20,'death':-18}[event],priority=4 if event=='warning' else 2,cooldown={'warning':.70,'attack':.24,'hurt':.32,'death':.35}[event],pitch=round(.82+i*.025,3))
    cue('emergency_start',priority=5,responsive=True,gain=-12,cooldown=.5)
    cue('time_low_loop',responsive=True,gain=-28)
    for gesture in ['spin','connect','trace']:
        cue('repair_'+gesture,responsive=True,gain=-22,cooldown=.2)
    write_library()
    return kinds

def write_library():
    assets=sorted(ASSETS);resources=['[gd_resource type="Resource" script_class="CombatAudioLibrary" load_steps=%d format=3]'%(len(assets)+len(CUES)+4),'','[ext_resource type="Script" path="res://scripts/audio/combat_audio_library.gd" id="1"]','[ext_resource type="Script" path="res://scripts/audio/combat_audio_cue.gd" id="2"]']
    resources.append('[ext_resource type="AudioStream" path="res://audio/music/glow.ogg" id="music"]')
    for i,name in enumerate(assets):
        # User recordings win; rebuilding fallbacks must never discard their wiring.
        supplied=BANK/'supplied'/(name+'.mp3')
        path=supplied if supplied.is_file() else BANK/(name+'.wav')
        resources.append(f'[ext_resource type="AudioStream" path="res://{path.relative_to(ROOT)}" id="s{i}"]')
    for i,c in enumerate(CUES):
        resources += ['',f'[sub_resource type="Resource" id="Cue{i}"]','script = ExtResource("2")',f'id = &"{c["id"]}"',f'stream = ExtResource("s{assets.index(c["asset"])}")',f'volume_db = {float(c["gain"])}',f'priority = {c["priority"]}',f'responsive = {str(c["responsive"]).lower()}',f'cooldown = {c["cooldown"]}',f'pitch = {float(c["pitch"])}',f'looping = {str(ASSETS[c["asset"]]["loop"]).lower()}',f'effect = &"{c["effect"]}"']
    resources += ['','[resource]','script = ExtResource("1")','cues = Array[ExtResource("2")](['+', '.join(f'SubResource("Cue{i}")' for i in range(len(CUES)))+'])','']
    resources += ['music = ExtResource("music")','music_volume_db = -26.0','']
    (BANK/'palette.tres').write_text('\n'.join(resources))

def reel(out):
    # Offline PCM audition, explicitly not evidence from Dummy-driver playback.
    parts=[];index=[];at=0
    groups=['ring_launch','ring_loop','cable_cut','hit','ring_return','flash_fire','flash_charged','pierce_hit','flash_ready','cone_loop','cone_pulse','vent','repair_step','repair_full','room_open','relay_warning','relay_attack','cable_warning','glass_warning','steam_warning','shield_warning','pack_warning','boss_warning','boss_hurt','boss_death','clock_loop','scrub_older','scrub_newer','recovery_confirm']
    for name in groups:
        with wave.open(str(BANK/(name+'.wav')),'rb') as f:y=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(float)/32768
        index.append({'at_seconds':round(at/RATE,3),'name':name})
        if ASSETS[name]['loop']: y=np.tile(y,2)
        parts.extend([y*.7,np.zeros(round(RATE*.28))]);at+=len(y)+round(RATE*.28)
    # Actual content resampled with exactly the feedback policy's .22/.30s ramps.
    for name,tau,target in [('ring_loop',.22,.18**.45),('clock_loop',.30,.18**.65)]:
        with wave.open(str(BANK/(name+'.wav')),'rb') as f:y=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(float)/32768
        t=np.arange(RATE*5)/RATE
        wanted=np.where((t>=1)&(t<3),target,1.0);pitch=np.ones(len(t))
        for i in range(1,len(t)):pitch[i]=pitch[i-1]+(wanted[i]-pitch[i-1])*(1-np.exp(-1/(RATE*tau)))
        source=np.cumsum(pitch)%len(y);render=np.interp(source,np.arange(len(y)),y)*.6
        render*=np.minimum(1,np.minimum(t/.02,(t[-1]-t)/.03))
        index.append({'at_seconds':round(at/RATE,3),'name':name+' entry/exit ramp: slow at +1s, normal at +3s'})
        parts.extend([render,np.zeros(round(RATE*.4))]);at+=len(render)+round(RATE*.4)
    for name,start,end in [('scrub_older',.6,2.2),('scrub_newer',2.2,.6)]:
        with wave.open(str(BANK/(name+'.wav')),'rb') as f:y=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(float)/32768
        t=np.arange(RATE*3)/RATE;wanted=np.linspace(start,end,len(t));pitch=np.full(len(t),start)
        for i in range(1,len(t)):pitch[i]=pitch[i-1]+(wanted[i]-pitch[i-1])*(1-np.exp(-1/(RATE*.30)))
        render=np.interp(np.cumsum(pitch)%len(y),np.arange(len(y)),y)*.6
        render*=np.maximum(0,np.minimum(1,np.minimum(t/.02,(t[-1]-t)/.03)))
        index.append({'at_seconds':round(at/RATE,3),'name':name+' speed ramp'})
        parts.extend([render,np.zeros(round(RATE*.3))]);at+=len(render)+round(RATE*.3)
    data=np.clip(np.concatenate(parts),-.95,.95)
    out.mkdir(parents=True,exist_ok=True)
    with wave.open(str(out/'audition.wav'),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(np.round(data*32767).astype('<i2').tobytes())
    (out/'audition-index.json').write_text(json.dumps(index,indent=2)+'\n')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    kinds=build();reel(a.out)
    (a.out/'bank-analysis.json').write_text(json.dumps({'sample_rate':RATE,'assets':ASSETS,'cues':CUES,'enemy_kinds':kinds},indent=2)+'\n')
    print(json.dumps({'assets':len(ASSETS),'cues':len(CUES),'bytes':sum(p.stat().st_size for p in BANK.glob('*.wav')),'audition':str(a.out/'audition.wav')}))
