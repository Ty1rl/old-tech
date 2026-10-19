#!/usr/bin/env python3
"""Small before/after dry auditions from actual WAVs and Inspector cue gains.
Not a recording of Godot/hardware, nor a substitute for listening. Requires numpy;
optional --ffmpeg decodes the existing licensed music, never downloads/replaces it.
"""
import argparse, json, re, subprocess, wave
from pathlib import Path
import numpy as np

RATE=22050
ROOT=Path(__file__).resolve().parents[2]
DURATION=22

def palette(bank):
    text=(bank/'palette.tres').read_text()
    streams={i:Path(p).name for p,i in re.findall(r'\[ext_resource type="AudioStream" path="([^"]+)" id="([^"]+)"\]',text)}
    cues={}
    for block in text.split('[sub_resource')[1:]:
        name=re.search(r'\nid = &"([^"]+)"',block).group(1)
        stream=re.search(r'stream = ExtResource\("([^"]+)"\)',block).group(1)
        gain=float(re.search(r'volume_db = ([-.\d]+)',block).group(1))
        pitch=float(re.search(r'\npitch = ([-.\d]+)',block).group(1))
        cues[name]={'asset':streams[stream], 'gain':10**(gain/20),'pitch':pitch,'responsive':'responsive = true' in block}
    music=float(re.search(r'music_volume_db = ([-.\d]+)',text).group(1))
    return cues,10**(music/20)

def read(path):
    with wave.open(str(path),'rb') as f:
        assert f.getframerate()==RATE and f.getnchannels()==1 and f.getsampwidth()==2
        return np.frombuffer(f.readframes(f.getnframes()),'<i2').astype(float)/32768

def write(path, data):
    assert np.max(np.abs(data))<1
    with wave.open(str(path),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE)
        f.writeframes(np.round(data*32767).astype('<i2').tobytes())

def slew(target, seconds):
    result=np.ones(len(target));alpha=1-np.exp(-1/(RATE*seconds))
    for i in range(1,len(target)):result[i]=result[i-1]+(target[i]-result[i-1])*alpha
    return result

EVENTS=[(.2,'ring_launch',1),(.85,'cable_cut',1),(1.1,'hit',.5),(1.5,'ring_return',.5),
 (2.1,'flash_fire',.4),(2.65,'flash_fire',.4),(3.4,'flash_charged',1),(3.8,'pierce_hit',1),
 (4.7,'cone_pulse',1),(5.2,'cone_pulse',1),(6.1,'vent',1),(6.7,'enemy_yellow_warning',1),
 (7.15,'enemy_ranged_attack',1),(7.45,'enemy_blue_hurt',1),(7.8,'enemy_blue_death',1),
 (8.5,'repair_step',1),(9,'repair_full',1),(10.7,'ring_launch',1),(11.1,'flash_fire',.4),
 (12.0,'cable_cut',1),(12.6,'repair_step',1),(13.2,'flash_charged',1),(20.0,'recovery_confirm',1)]

def render(bank, music):
    cues,music_gain=palette(bank);t=np.arange(RATE*DURATION)/RATE;mix=np.zeros(len(t))
    scale=np.where((t>=10)&(t<14),.18,1.0)
    world=slew(scale**.45,.22);clock=slew(scale**.65,.30)
    def add(name,start,end=None,gain=1,rate=None):
        cue=cues[name];data=read(bank/cue['asset']);first=round(start*RATE)
        last=min(len(t),round(end*RATE)) if end is not None else len(t)
        rates=np.ones(last-first) if cue['responsive'] else world[first:last]
        if rate is not None:rates=rate[first:last]
        positions=np.cumsum(rates*cue['pitch'])-rates[0]*cue['pitch']
        if end is not None:positions%=len(data)
        else:positions=positions[positions<len(data)]
        sound=np.interp(positions,np.arange(len(data)),data)*cue['gain']*gain
        if end is not None:
            edge=np.minimum(1,np.minimum(np.arange(len(sound))/440,(len(sound)-1-np.arange(len(sound)))/660))
            sound*=np.maximum(0,edge)
        mix[first:first+len(sound)]+=sound
    for at,name,gain in EVENTS:add(name,at,gain=gain)
    add('ring_loop',.25,1.45,.8);add('cone_loop',4.5,6,.65)
    add('charge_loop',2.9,3.4,.8);add('clock_loop',10,15,.45,clock)
    add('ring_loop',10.7,12,.8)
    scrub=np.ones(len(t));scrub[(t>=16)&(t<18)]=np.linspace(.6,2.2,np.sum((t>=16)&(t<18)))
    scrub[(t>=18)&(t<20)]=np.linspace(2.2,.6,np.sum((t>=18)&(t<20)))
    scrub=slew(scrub,.30)
    add('clock_loop',16,20,.45,scrub);add('scrub_older',16,18,.65,scrub);add('scrub_newer',18,20,.65,scrub)
    if music is not None:
        pos=np.cumsum(world);bed=np.interp(pos,np.arange(len(music)),music)
        gate=np.where((t>=16)&(t<20),0.,1.)
        gate=slew(gate,.20)*np.minimum(1,t/.2);mix+=bed*music_gain*gate
    edge=np.minimum(1,np.minimum(t/.01,(t[-1]-t)/.03));return mix*np.maximum(0,edge)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--before',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--ffmpeg',type=Path);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
    music=None
    if a.ffmpeg:
        cmd=[str(a.ffmpeg),'-v','error','-ss','40','-i',str(ROOT/'audio/music/glow.ogg'),'-t',str(DURATION+1),'-ac','1','-ar',str(RATE),'-f','f32le','pipe:1']
        r=subprocess.run(cmd,capture_output=True,timeout=30)
        (a.out/'music-decode.log').write_bytes(r.stderr);r.check_returncode();music=np.frombuffer(r.stdout,'<f4').astype(float)
    old=render(a.before,music);new=render(ROOT/'audio/combat',music)
    boost=.75/max(np.max(np.abs(old)),np.max(np.abs(new))) # ONE boost for both; never level-match away the changes.
    write(a.out/'before-mix.wav',old*boost);write(a.out/'after-mix.wav',new*boost)
    write(a.out/'weapon-AB.wav',np.concatenate([old*boost,np.zeros(RATE),new*boost]))
    index={'before_seconds':[0,22],'after_seconds':[23,45],'sections':{'normal':[0,10],'slow_entry_exit':[10,15],'older_newer_scrub':[16,20],'recovery':[20,22]},'events':[{'at':t,'cue':name,'strength':gain} for t,name,gain in EVENTS],'common_audition_boost_db':float(20*np.log10(boost)),'note':'Dry PCM audition with actual palette gains and once-applied world pitch. No 3D attenuation/native mixer/hardware listening claim.'}
    if music is not None:
        _,old_gain=palette(a.before);_,new_gain=palette(ROOT/'audio/combat');clip=music[:RATE*8];edge=np.minimum(1,np.minimum(np.arange(len(clip))/(RATE*.03),(len(clip)-1-np.arange(len(clip)))/(RATE*.03)));clip*=np.maximum(0,edge)
        boost_music=.7/max(np.max(np.abs(clip*old_gain)),np.max(np.abs(clip*new_gain)))
        write(a.out/'music-AB.wav',np.concatenate([clip*old_gain*boost_music,np.zeros(RATE),clip*new_gain*boost_music]))
        index['music']={'before_seconds':[0,8],'after_seconds':[9,17],'same_source':'Glow 40..48s, same encoded track; only default gain changes','gain_change_db':float(20*np.log10(new_gain/old_gain)),'common_boost_db':float(20*np.log10(boost_music))}
    (a.out/'comparison-index.json').write_text(json.dumps(index,indent=2)+'\n');print(json.dumps({'weapon_AB_seconds':45,'music_AB_seconds':17 if music is not None else 0,'out':str(a.out)}))
