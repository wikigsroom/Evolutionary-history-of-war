"""Master CC0 music and build layered, reproducible weapon/UI audio; no external services."""
from pathlib import Path
from functools import lru_cache
import hashlib
import json
import re
import shutil
import subprocess
import wave
import numpy as np
from scipy.signal import butter, sosfilt, resample_poly

ROOT = Path(__file__).resolve().parents[1]
SR = 48000
RAW = ROOT / "output/audio-sources"
MASTERS = ROOT / "output/audio-masters"
PUBLIC = ROOT / "public/assets/audio"
GODOT = ROOT / "godot/assets/audio"
QA = ROOT / "output/qa/godot-audio"
SOURCE_MANIFEST = json.loads((RAW / "sources.json").read_text(encoding="utf-8"))
SOURCES = {source["id"]: source for source in SOURCE_MANIFEST["sources"]}
USED = set()
CUE_USED = set()

def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

@lru_cache(maxsize=None)
def decode(path, channels=1):
    content = run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", str(channels), "-ar", str(SR), "-"]).stdout
    return np.frombuffer(content, dtype="<f4").reshape(-1, channels).copy()

def filt(signal, frequency, kind="lowpass"):
    return sosfilt(butter(2, frequency, kind, fs=SR, output="sos"), signal, axis=0)

def edges(signal, attack=.001, release=.015):
    signal = signal.copy()
    first = min(int(attack * SR), len(signal) // 3)
    last = min(int(release * SR), len(signal) // 3)
    if first: signal[:first] *= np.linspace(0, 1, first).reshape((-1,) + (1,) * (signal.ndim-1))
    if last: signal[-last:] *= np.linspace(1, 0, last).reshape((-1,) + (1,) * (signal.ndim-1))
    return signal

def write_wav(path, signal):
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.round(np.clip(signal, -.9999, .9999) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1 if signal.ndim == 1 else signal.shape[1])
        stream.setsampwidth(2); stream.setframerate(SR); stream.writeframes(pcm.tobytes())

def tone(f0, f1, seconds, gain=1, decay=6, harmonic=.12):
    t = np.arange(int(seconds * SR)) / SR
    frequency = f0 * (f1 / f0) ** (t / max(seconds, .001))
    phase = np.cumsum(frequency) * 2 * np.pi / SR
    signal = (np.sin(phase) + harmonic*np.sin(phase*2.01)) * np.exp(-decay*t/seconds)
    return edges(signal, .003, .012) * gain

def noise(seconds, seed, gain=1, cutoff=5500, decay=5):
    t = np.arange(int(seconds*SR))/SR
    signal = filt(np.random.default_rng(seed).normal(0, .5, len(t)), cutoff)
    return edges(signal*np.exp(-decay*t/seconds), .002, .02)*gain

def mix(*layers):
    # Layer tuple: (signal, gain, delay_seconds). Never normalize layers independently here.
    extent = max(len(signal)+int(delay*SR) for signal, gain, delay in layers)
    result = np.zeros(extent)
    for signal, gain, delay in layers:
        start = int(delay*SR); result[start:start+len(signal)] += signal*gain
    return result

def sample(pack, pattern, index=0, seconds=None, speed=1):
    files = sorted((RAW/pack/"extracted").rglob(pattern))
    if not files: raise ValueError(f"Missing source {pack}/{pattern}")
    path = files[index % len(files)]
    USED.add(path.relative_to(ROOT).as_posix())
    CUE_USED.add(path.relative_to(ROOT).as_posix())
    signal = decode(path).ravel().astype(np.float64)
    # Remove source leading/trailing silence, keeping 2 ms before the first transient.
    active = np.flatnonzero(np.abs(signal) > max(.0008, np.max(np.abs(signal))*.004))
    if len(active): signal = signal[max(0, active[0]-96):min(len(signal), active[-1]+480)]
    signal /= max(.0001, np.max(np.abs(signal)))
    if speed != 1: signal = resample_poly(signal, 1000, round(speed*1000))
    if seconds is not None: signal = signal[:int(seconds*SR)]
    return edges(signal)

# All 24 legacy keys remain valid. Extra keys resolve formerly silent/ambiguous events.
CUES = {
 "ui_confirm": ("UI", 40, 45, .62), "ui_cancel": ("UI", 40, 45, .58), "ui_error": ("UI", 85, 160, .78),
 "queue_add": ("UI", 50, 70, .62), "research_complete": ("UI", 65, 160, .8), "loot_collect": ("UI", 35, 170, .50),
 "unit_spawn": ("Battle", 25, 220, .42), "unit_death": ("Battle", 30, 90, .55),
 "hero_death": ("Battle", 95, 750, .95), "hero_respawn": ("Battle", 75, 700, .85),
 "evolve": ("Battle", 100, 800, 1), "rush_flag": ("Battle", 65, 450, .72),
 "shield_hit": ("Battle", 55, 80, .7), "shield_break": ("Battle", 85, 240, .95),
 "stone_hit": ("Battle", 45, 65, .75), "wood_hit": ("Battle", 45, 65, .72), "metal_hit": ("Battle", 50, 65, .77),
 "flesh_hit": ("Battle", 45, 65, .80), "arrow_hit": ("Battle", 45, 70, .65),
 "sword_swing": ("Battle", 20, 90, .46), "spear_swing": ("Battle", 25, 100, .52), "stone_throw": ("Battle", 20, 100, .45),
 "arrow_fire": ("Battle", 25, 70, .55), "musket_fire": ("Battle", 60, 65, .78),
 "cannon_fire": ("Battle", 70, 120, .92), "cannon_hit": ("Battle", 75, 120, .92),
 "arc_fire": ("Battle", 55, 80, .72), "energy_hit": ("Battle", 55, 70, .75),
 "support_pulse": ("Battle", 25, 280, .45), "heal": ("Battle", 30, 260, .42),
 "skill_cast": ("Battle", 75, 200, .8), "skill_ready": ("UI", 55, 900, .65), "build": ("Battle", 60, 240, .7),
 "arrow_rain": ("Battle", 75, 180, .75), "meteor_impact": ("Battle", 90, 220, .95),
 "airstrike": ("Battle", 90, 200, .95), "orbital_impact": ("Battle", 95, 240, 1),
 "item_drum": ("Battle", 75, 300, .8), "item_smoke": ("Battle", 70, 250, .65), "item_supply": ("Battle", 70, 250, .75),
 "base_danger": ("UI", 100, 6000, .80), "base_destroyed": ("Battle", 100, 1200, 1),
 "danger_warning": ("Battle", 90, 450, .70),
}

def effect(name, variant):
    i = variant
    speed = [.98, 1.02, 1][i]
    s = lambda pack, pattern, duration=None, pitch=speed: sample(pack, pattern, i, duration, pitch)
    impact = lambda pattern, duration=.45: s("kenney-impact", pattern, duration)
    interface = lambda pattern: s("kenney-interface", pattern, .36)
    rpg = lambda pattern, duration=.35: s("kenney-rpg", pattern, duration)
    sci = lambda pattern, duration=.6: s("kenney-scifi", pattern, duration)
    seed = sum(map(ord, name))*17+i
    if name == "ui_confirm": return mix((interface("click_*.ogg"), .65, 0), (tone(780, 1040, .11, .14), 1, .025))
    if name == "ui_cancel": return interface("back_*.ogg")
    if name == "ui_error": return mix((interface("error_*.ogg"), .65, 0), (tone(170, 95, .16, .12), 1, .03))
    if name == "queue_add": return mix((interface("select_*.ogg"), .55, 0), (rpg("metalClick.ogg"), .2, .03))
    if name == "loot_collect": return mix((rpg("handleCoins*.ogg", .23), .8, 0), (tone(1150, 1200, .12, .08), 1, .015))
    if name in ["research_complete", "skill_ready", "item_supply"]:
        return mix((interface("confirmation_*.ogg"), .4, 0), (tone(523, 523, .22, .15), 1, 0), (tone(659, 659, .27, .15), 1, .10), (tone(784, 784, .32, .15), 1, .20), (rpg("handleCoins*.ogg"), .2 if name=="item_supply" else .05, .20))
    if name == "unit_spawn": return mix((rpg("cloth*.ogg", .15), .45, 0), (impact("footstep_wood_*.ogg", .18), .5, .05))
    if name == "unit_death": return mix((impact("impactSoft_heavy_*.ogg"), .8, 0), (rpg("dropLeather.ogg"), .35, .05))
    if name == "hero_death": return mix((impact("impactMetal_heavy_*.ogg"), .65, 0), (tone(180, 50, .8, .3, 3), 1, .06), (noise(.65, seed, .3, 1300), 1, .04))
    if name in ["hero_respawn", "evolve"]:
        layers=[(sci("forceField_*.ogg", .7), .38, 0)]
        for index,freq in enumerate([261.63,392,523.25,783.99]): layers.append((tone(freq,freq,.48,.15,3),1,index*.11))
        if name=="evolve": layers += [(sci("lowFrequency_explosion_*.ogg", .9), .45, .33), (impact("impactBell_heavy_*.ogg", 1), .22, .33)]
        return mix(*layers)
    if name in ["sword_swing", "spear_swing", "stone_throw", "arrow_fire"]:
        signal=rpg("knifeSlice*.ogg", .25) if name!="arrow_fire" else rpg("drawKnife*.ogg", .25)
        layers=[(signal, .6, 0),(noise(.17 if name!="spear_swing" else .24,seed,.23,4500),1,.015)]
        if name=="arrow_fire": layers.append((tone(430,160,.08,.16),1,0))
        if name=="stone_throw": layers.append((rpg("cloth*.ogg", .16),.4,0))
        return mix(*layers)
    if name in ["flesh_hit", "arrow_hit", "stone_hit", "metal_hit", "wood_hit"]:
        pattern={"flesh_hit":"impactPunch_heavy_*.ogg","arrow_hit":"impactPunch_medium_*.ogg","stone_hit":"impactMining_*.ogg","metal_hit":"impactMetal_medium_*.ogg","wood_hit":"impactWood_medium_*.ogg"}[name]
        return mix((impact(pattern,.4),.85,0),(tone(135 if name!="metal_hit" else 240,65,.14,.18),1,.004))
    if name in ["shield_hit", "shield_break"]:
        return mix((sci("forceField_*.ogg", .35 if name=="shield_hit" else .6),.5,0),(impact("impactPlate_medium_*.ogg" if name=="shield_hit" else "impactGlass_heavy_*.ogg",.6),.7,0),(tone(540,220,.25,.14),1,.006))
    if name in ["musket_fire", "cannon_fire", "cannon_hit", "meteor_impact", "airstrike", "orbital_impact", "base_destroyed"]:
        duration={"musket_fire":.24,"cannon_fire":.55,"cannon_hit":.75,"meteor_impact":1,"airstrike":1.15,"orbital_impact":1.3,"base_destroyed":2.3}[name]
        layers=[(sci("explosionCrunch_*.ogg",duration),.75,0),(tone(120,38,duration,.35,4),1,0),(noise(duration,seed,.4,6000 if name=="musket_fire" else 1800),1,0)]
        if name=="musket_fire": layers.append((rpg("metalClick.ogg", .16),.35,.04))
        elif name in ["cannon_hit","meteor_impact","base_destroyed"]: layers.append((impact("impactMining_*.ogg",duration),.25,.07))
        if name in ["orbital_impact","airstrike"]: layers.append((sci("laserLarge_*.ogg", .65),.28,0))
        if name=="base_destroyed":
            for delay in [.18,.46,.82,1.1]: layers.append((impact("impactWood_heavy_*.ogg", .45),.25,delay))
            layers.append((noise(2.3,seed+100,.25,500,2.6),1,.08))
        signal=mix(*layers)
        # Low frequency wash gives heavy weapons weight; make the larger cases last beyond source cuts.
        if name not in ["musket_fire","cannon_fire"]: signal=mix((signal,1,0),(filt(signal,2200),.18,.1))
        return signal
    if name in ["arc_fire", "energy_hit", "skill_cast", "support_pulse", "heal", "item_smoke"]:
        pattern={"arc_fire":"laserSmall_*.ogg","energy_hit":"laserRetro_*.ogg","skill_cast":"forceField_*.ogg","support_pulse":"forceField_*.ogg","heal":"forceField_*.ogg","item_smoke":"thrusterFire_*.ogg"}[name]
        signal=sci(pattern,.35 if name not in ["skill_cast","item_smoke"] else .65)
        if name in ["heal","support_pulse"]: signal=filt(signal,2400)
        f=660 if name in ["heal","support_pulse"] else 180
        return mix((signal,.65,0),(tone(f,f*1.25,.25,.12),1,.01))
    if name == "build": return mix((rpg("metalLatch.ogg"),.6,0),(impact("impactWood_heavy_*.ogg", .22),.5,.10),(interface("confirmation_*.ogg"),.3,.16))
    if name == "arrow_rain": return mix(*[(rpg("knifeSlice*.ogg", .23),.55 if j==0 else .28,j*.05) for j in range(5)])
    if name in ["item_drum","rush_flag"]: return mix(*[(tone(140,68,.24,.4,5),1,j*.12) for j in range(3)],(impact("impactWood_heavy_*.ogg",.2),.3,0))
    if name == "base_danger":
        shift=[.98,1,1.02][i]
        return mix((tone(440*shift,380*shift,.23,.23,2),1,0),(tone(466*shift,402*shift,.23,.17,2),1,0),(tone(440*shift,380*shift,.23,.23,2),1,.30),(tone(466*shift,402*shift,.23,.17,2),1,.30))
    if name == "danger_warning":
        shift=[.98,1,1.02][i]
        return mix(*[(tone((660+j*70)*shift,(810+j*70)*shift,.16,.22,3),1,j*.16) for j in range(3)])
    raise ValueError(name)

def build_sfx():
    catalog = {}
    for name,(bus,priority,cooldown,gain) in CUES.items():
        CUE_USED.clear()
        files=[]; sources=set(); metrics=[]
        for variant in range(3):
            before=set(USED)
            signal=effect(name,variant)
            signal=filt(signal,45,"highpass")
            signal=edges(signal,.0015,.024)
            # Preserve attack/body ratio and match peaks without flattening transients.
            signal*=.74/max(.0001,float(np.max(np.abs(signal))))
            rms=float(np.sqrt(np.mean(signal**2)))
            if rms>.23: signal*=.23/rms
            filename=name+("" if variant==0 else f"_{variant+1:02d}")+".wav"
            master=MASTERS/"sfx"/filename;write_wav(master,signal)
            for destination in [PUBLIC,GODOT]:
                (destination/"sfx").mkdir(parents=True,exist_ok=True)
                shutil.copyfile(master,destination/"sfx"/filename)
            files.append("res://assets/audio/sfx/"+filename)
            sources.update(USED-before)
            # Include repeated cached source use in per-cue provenance: each recipe logs selected samples.
            metrics.append({"file":filename,"duration":round(len(signal)/SR,4),"peak":round(float(np.max(np.abs(signal))),5),"rms":round(float(np.sqrt(np.mean(signal**2))),5),"sha256":sha(master)})
        catalog[name]={"bus":bus,"priority":priority,"cooldown_ms":cooldown,"gain":gain,"variants":files,"files":metrics,"source_files":sorted(CUE_USED),"provenance":"cc0_layered_original_synthesis" if CUE_USED else "original_synthesis"}
    return catalog

def music_source(key):
    USED.add(SOURCES[key]["file"])
    return ROOT/SOURCES[key]["file"]

def master_music(track, source_id, style, loop=True):
    source=music_source(source_id)
    signal=decode(source,2).astype(np.float64)
    # Existing exact-length authored loops retain their musical period. A 2 ms edit removes clicks,
    # without shortening bars as a whole-track crossfade would. Menu's authored rests are intentional.
    signal=filt(signal,45,"highpass")
    signal=edges(signal,.002,.002 if loop else .10)
    temp=MASTERS/"music"/(track+"-premaster.wav");write_wav(temp,signal)
    target_i=-20 if track=="menu" else -19
    common=f"equalizer=f=3100:t=q:w=1.0:g=-1.8,loudnorm=I={target_i}:TP=-2:LRA=11"
    analysis=run(["ffmpeg","-hide_banner","-i",str(temp),"-af",common+":print_format=json","-f","null","-"],text=True).stderr
    measurements=json.loads(re.findall(r"\{\s*\"input_i\".*?\}",analysis,re.S)[-1])
    values=":".join(f"{out}={measurements[key]}" for out,key in [("measured_I","input_i"),("measured_LRA","input_lra"),("measured_TP","input_tp"),("measured_thresh","input_thresh"),("offset","target_offset")])
    output=MASTERS/"music"/(track+".wav")
    run(["ffmpeg","-v","error","-y","-i",str(temp),"-af",common+":"+values+":linear=true","-ar",str(SR),"-c:a","pcm_s16le",str(output)])
    # Native Vorbis supports sample-accurate loops; MP3 remains for the legacy web client only.
    for suffix,encoder,options in [("ogg","libvorbis",["-q:a","5"]),("mp3","libmp3lame",["-b:a","160k"])]:
        path=PUBLIC/"music"/(track+"."+suffix);path.parent.mkdir(parents=True,exist_ok=True)
        run(["ffmpeg","-v","error","-y","-i",str(output),"-c:a",encoder,*options,str(path)])
        if suffix=="ogg":
            (GODOT/"music").mkdir(parents=True,exist_ok=True);shutil.copyfile(path,GODOT/"music"/path.name)
    signal=decode(output,2)
    return {"path":"res://assets/audio/music/"+track+".ogg","loop":loop,"source_ids":[source_id],"style":style,
            "duration":round(len(signal)/SR,5),"target_lufs":target_i,"peak":round(float(np.max(np.abs(signal))),5),
            "source_loudness":measurements,"sha256":sha(GODOT/"music"/(track+".ogg"))}

def build_sting(track):
    # A newly arranged short cadence avoids falsely looping a victory/defeat song.
    frequencies={"victory":[392,493.88,587.33,783.99],"defeat":[392,349.23,311.13,261.63],"draw":[392,523.25,392]}[track]
    layers=[]
    for i,f in enumerate(frequencies):
        layers.append((tone(f,f,.6 if i==len(frequencies)-1 else .28,.18,2.4),1,i*.22))
        layers.append((tone(f*.5,f*.5,.3,.11,3),1,i*.22))
    layers.append((sample("kenney-jingles","jingles_PIZZI00.ogg" if track=="victory" else "jingles_PIZZI11.ogg",seconds=.45),.18,0))
    mono=edges(mix(*layers),.002,.09)
    mono*=.55/max(.0001,float(np.max(np.abs(mono))))
    signal=np.column_stack([mono,mono])
    master=MASTERS/"music"/(track+".wav");write_wav(master,signal)
    for suffix,encoder,options in [("ogg","libvorbis",["-q:a","5"]),("mp3","libmp3lame",["-b:a","160k"])]:
        path=PUBLIC/"music"/(track+"."+suffix)
        run(["ffmpeg","-v","error","-y","-i",str(master),"-c:a",encoder,*options,str(path)])
        if suffix=="ogg":shutil.copyfile(path,GODOT/"music"/path.name)
    return {"path":"res://assets/audio/music/"+track+".ogg","loop":False,"source_ids":["kenney-jingles"],"style":"原创结算短句 + CC0 拨弦质感","duration":round(len(mono)/SR,5),"peak":round(float(np.max(np.abs(mono))),5),"sha256":sha(GODOT/"music"/(track+".ogg"))}

def main():
    for folder in [MASTERS/"music",QA,GODOT/"music"]:folder.mkdir(parents=True,exist_ok=True)
    music={}
    for track,source_id,style in [("menu","relax","温暖拨弦 · 整军待发"),("age1","krakatoa","部落打击乐 · 木质与兽皮"),("age2","epic-march","军阵行进 · 低鼓与铜管"),("age3","hope","王国冲锋 · 管弦与军鼓"),("age4","8bit-battle","工业脉冲 · 机械与芯片节奏"),("age5","awake","星际决战 · 电子与碎拍")]:
        music[track]=master_music(track,source_id,style);print("Mastered "+track,flush=True)
    for track in ["victory","defeat","draw"]:music[track]=build_sting(track)
    cues=build_sfx()
    catalog={"version":2,"sample_rate":SR,"music":music,"cues":cues,"sources":SOURCE_MANIFEST["sources"],"used_source_files":sorted(USED),"method":"CC0 samples layered with original transient/body/tail synthesis; two-pass music mastering"}
    for path in [GODOT/"catalog.json",PUBLIC/"catalog.json",QA/"audio-build.json"]:path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    # Source declarations also go in the Android and Windows resource packs.
    credits=["Epoch Rush — Audio credits / 音频素材声明", "", "CC0-1.0 public-domain dedication: https://creativecommons.org/publicdomain/zero/1.0/", "Music has been mastered/edited. Sound effects have been layered, filtered and arranged.", "Original synthesis/cadences and game mix: Epoch Rush audio pipeline.", ""]
    used_ids={p.split("/")[2] for p in USED}
    for source in SOURCE_MANIFEST["sources"]:
        if source["id"] in used_ids:
            credits += [f"{source['title']} — {source['author']} (CC0-1.0)",source["page"]]
            if source["id"]=="awake":credits.append("Artist: https://cynicmusic.com/ ; https://pixelsphere.org/")
            credits += ["Source SHA-256: "+source["sha256"],""]
    for destination in [GODOT,PUBLIC,ROOT/"godot/build/windows"]:
        (destination/"Audio-CREDITS.txt").write_text("\n".join(credits)+"\n",encoding="utf-8")
        shutil.copyfile(RAW/"CC0-1.0.txt",destination/"Audio-CC0-1.0.txt")
    manifest_path=ROOT/"public/assets/manifest.json"
    manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
    for track,meta in music.items():
        for suffix in ["mp3","ogg"]:
            key="music."+track+(".ogg" if suffix=="ogg" else "")
            path=PUBLIC/"music"/(track+"."+suffix)
            manifest["entries"][key]={"key":key,"kind":"audio","path":"audio/music/"+path.name,"size":[],"status":"mastered_technical_qa","method":"cc0_source_mastering" if track not in ["victory","defeat","draw"] else "cc0_layered_original_cadence","sampleRate":SR,"durationSec":meta["duration"],"sha256":sha(path),"sourceIds":meta["source_ids"]}
    for name,meta in cues.items():
        for i,file in enumerate(meta["files"]):
            key="sfx."+name+("" if i==0 else f".v{i+1}")
            manifest["entries"][key]={"key":key,"kind":"audio","path":"audio/sfx/"+file["file"],"size":[],"status":"layered_technical_qa","method":meta["provenance"],"sampleRate":SR,"durationSec":file["duration"],"sha256":file["sha256"]}
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    shutil.copyfile(manifest_path,ROOT/"src/content/runtime-manifest.json")
    # Only known, now-unused duplicate files are removed, after a scoped snapshot.
    for path in GODOT.glob("*.wav"):
        if path.stem in CUES:
            path.unlink();path.with_suffix(".wav.import").unlink(missing_ok=True)
    for path in (GODOT/"music").glob("*.mp3"):
        if path.stem in music:
            path.unlink();path.with_suffix(".mp3.import").unlink(missing_ok=True)
    print(json.dumps({"music_tracks":len(music),"sound_families":len(cues),"sfx_variants":len(cues)*3,"used_source_files":len(USED)},ensure_ascii=False))

if __name__=="__main__":main()
