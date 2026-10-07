"""Create original instrumental loops and material effects. No sampled recordings."""
from pathlib import Path
import hashlib,json,math,shutil,subprocess,wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'public/assets'
RATE=48000
plan=json.loads((ROOT/'docs/epoch-rush/data/asset-manifest.json').read_text(encoding='utf-8'))['entries']
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
ffmpeg=shutil.which('ffmpeg')
if not ffmpeg: raise SystemExit('ffmpeg is required to encode original music MP3s')

def tone(hz,seconds,kind='pluck',gain=.25):
    t=np.arange(round(seconds*RATE))/RATE
    if kind=='flute': sound=np.sin(2*np.pi*hz*t)+.15*np.sin(4*np.pi*hz*t)
    elif kind=='brass': sound=sum(np.sin(2*np.pi*hz*n*t)/n**1.5 for n in range(1,7))
    else: sound=sum(np.sin(2*np.pi*hz*n*t)*np.exp(-t*(2+n*.8))/n**1.7 for n in range(1,6))
    attack=np.minimum(1,t/.025);release=np.minimum(1,(seconds-t)/.08)
    return sound*attack*release*gain

def percussion(seconds,seed,low=0,decay=18):
    rng=np.random.default_rng(seed);n=round(seconds*RATE);t=np.arange(n)/RATE
    sound=rng.normal(0,1,n)
    if low:
        spectrum=np.fft.rfft(sound);freq=np.fft.rfftfreq(n,1/RATE);spectrum*=1/(1+(freq/low)**4);sound=np.fft.irfft(spectrum,n)
        sound/=max(.001,np.max(np.abs(sound)))
    return sound*np.exp(-t*decay)*np.minimum(1,t/.002)

def write_wave(path,sound):
    peak=np.max(np.abs(sound));sound=sound/max(1,peak/.84)
    if sound.ndim==1: channels=1
    else: channels=2
    pcm=(sound*32767).astype('<i2')
    path.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(path),'wb') as file:
        file.setnchannels(channels);file.setsampwidth(2);file.setframerate(RATE);file.writeframes(pcm.tobytes())

def effect(name,seed):
    seconds=1.5 if name in ['evolve','base_destroyed','hero_respawn'] else .6 if 'cannon' in name or 'shield_break' in name else .24
    sound=np.zeros(round(seconds*RATE))
    def add(value,start=0):
        i=round(start*RATE);n=min(len(value),len(sound)-i)
        if n>0:sound[i:i+n]+=value[:n]
    if name in ['ui_confirm','queue_add','unit_spawn','loot_collect']:
        add(tone(659,.13,gain=.18));add(tone(880,.13,gain=.12),.065)
    elif name in ['ui_cancel','ui_error']:
        add(tone(196,.2,gain=.2));add(tone(147,.17,gain=.14),.04)
    elif name in ['evolve','hero_respawn','rush_flag']:
        for i,hz in enumerate([294,440,587,784]):add(tone(hz,.55,'brass',.12),i*.14)
        add(percussion(.45,seed,800,7)*.23)
    elif name in ['cannon_fire','cannon_hit','base_destroyed','hero_death']:
        add(percussion(seconds,seed,220,5)*.65);t=np.arange(len(sound))/RATE;add(np.sin(2*np.pi*(68*t-17*t*t))*np.exp(-t*9)*.5)
        add(percussion(min(.3,seconds),seed+1,4200,16)*.22)
    elif name in ['shield_hit','shield_break','arc_fire','skill_cast']:
        add(tone(440,seconds,'flute',.25));add(tone(733,seconds,'pluck',.15));add(percussion(seconds,seed,6000,14)*.16)
    elif name in ['musket_fire']:
        add(percussion(.2,seed,4500,28)*.8);add(tone(115,.15,'brass',.15))
    elif name in ['arrow_fire','arrow_hit']:
        add(percussion(seconds,seed,5000,20)*.32);add(tone(330,.16,gain=.09))
    elif name=='metal_hit':
        for hz in [1319,1871,2458]:add(tone(hz,.22,gain=.14))
        add(percussion(.12,seed,6000,32)*.34)
    elif name=='base_danger':
        add(tone(294,.16,'brass',.22));add(tone(220,.16,'brass',.2),.08)
    else:add(percussion(seconds,seed,1800,18)*.48);add(tone(140,.16,gain=.13))
    return sound

def music(name):
    index={'menu':0,'age1':1,'age2':2,'age3':3,'age4':4,'age5':5,'victory':6,'defeat':7}[name]
    bpm=[84,92,98,106,112,116,112,76][index];beat=60/bpm;beats=64 if index<6 else 16
    length=round(beats*beat*RATE);left=np.zeros(length);right=np.zeros(length)
    progression=[[50,53,57],[46,50,53],[53,57,60],[48,52,55]]
    motif=[0,4,7,4,2,5,7,9,7,5,4,2,0,2,4,7]
    if index==7:motif=[0,2,4,2,0,-1,-3,-5,0,2,4,2,0,-1,-3,-5]
    def put(note,at,pan=0):
        start=round(at*RATE);n=min(len(note),length-start)
        if n<=0:return
        left[start:start+n]+=note[:n]*(.75-pan*.2);right[start:start+n]+=note[:n]*(.75+pan*.2)
    for b in range(beats):
        chord=progression[(b//8)%4];at=b*beat;kind='brass' if index in [3,4,6] else 'flute' if index in [1,2,7] else 'pluck'
        if b%2==0:put(tone(440*2**((chord[0]-12-69)/12),beat*1.7,'pluck',.16),at)
        if b%4==0:
            for j,midi in enumerate(chord):put(tone(440*2**((midi-69)/12),beat*3.9,'flute',.055),at,(j-1)*.6)
        pitch=62+motif[(b+index*2)%len(motif)]
        put(tone(440*2**((pitch-69)/12),beat*.84,kind,.11),at,.25)
        if index==5:put(tone(440*2**((pitch+12-69)/12),beat*.4,'pluck',.06),at+beat*.5,-.35)
        if index!=7:
            if b%2==0:put(percussion(.25,1000+b,180,12)*.14,at)
            else:put(percussion(.18,2000+b,4500,25)*(.11 if index>=3 else .06),at)
            if index>=3:put(percussion(.08,3000+b,6500,50)*.04,at+beat*.5,.5)
    stereo=np.column_stack([left,right]);peak=np.max(np.abs(stereo));stereo*=.5/max(peak,.001)
    # Crossfade the loop tail into the beginning; result/defeat stings fade out.
    if index<6:
        cross=min(round(RATE*.15),length//10);weights=np.linspace(0,1,cross)[:,None]
        stereo[-cross:]=stereo[-cross:]*(1-weights)+stereo[:cross]*weights
    else:stereo[-round(RATE*1.2):]*=np.linspace(1,0,round(RATE*1.2))[:,None]
    return stereo

completed=[]
for entry in plan:
    if entry['kind']!='audio':continue
    key=entry['key'];path=OUT/entry['targetPath'];name=key.split('.')[1]
    seed=int.from_bytes(hashlib.sha256(key.encode()).digest()[:4],'little')
    if key.startswith('sfx.'):sound=effect(name,seed);write_wave(path,sound)
    else:
        sound=music(name);intermediate=ROOT/'output/audio-source'/(name+'.wav');write_wave(intermediate,sound);path.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(intermediate),'-codec:a','libmp3lame','-b:a','128k',str(path)],check=True)
    manifest['entries'][key]={'key':key,'kind':'audio','path':entry['targetPath'],'size':[],'status':'synthesized_pending_listening_review','method':'original_local_synthesis','sampleRate':RATE,'durationSec':round(len(sound)/RATE,3),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    completed.append(key)
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'originalAudioFiles':len(completed),'keys':completed},ensure_ascii=False))
