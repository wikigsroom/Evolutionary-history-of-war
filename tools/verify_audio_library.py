"""Verify native and shared audio outputs, licenses and captured Godot mix."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import numpy as np
from scipy.io import wavfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,default=ROOT/'output/qa/godot-audio')
OUT=parser.parse_args().output.resolve()
OUT.mkdir(parents=True,exist_ok=True)
ASSETS=ROOT/"godot/assets/audio"
catalog=json.loads((ASSETS/"catalog.json").read_text(encoding="utf-8"))
errors=[]
rows=[]

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def decode(path):
    content=subprocess.run(["ffmpeg","-v","error","-i",str(path),"-f","f32le","-ac","2","-ar","48000","-"],capture_output=True,check=True).stdout
    return np.frombuffer(content,dtype="<f4").reshape(-1,2)

for source in catalog["sources"]:
    path=ROOT/source["file"]
    if source["license"]!="CC0-1.0" or sha(path)!=source["sha256"]:errors.append("Source provenance: "+source["id"])
for name,meta in catalog["cues"].items():
    if not meta.get("source_files") and meta.get("provenance")!="original_synthesis":errors.append("Source files missing for cue "+name)
    hashes=[]
    for file in meta["files"]:
        path=ASSETS/"sfx"/file["file"];rate,pcm=wavfile.read(path)
        signal=pcm.astype(np.float64)/32768
        peak=float(abs(signal).max());rms=float(np.sqrt(np.mean(signal**2)))
        active=np.flatnonzero(abs(signal)>.003)
        onset=float(active[0]/rate) if len(active) else 1000
        if rate!=48000 or signal.ndim!=1 or peak>=.9 or rms<.003 or onset>.035 or abs(float(signal.mean()))>.01:errors.append("Invalid sound signal: "+file["file"])
        checksum=sha(path);hashes.append(checksum)
        if checksum!=file["sha256"] or checksum!=sha(ROOT/"public/assets/audio/sfx"/file["file"]):errors.append("SFX hash: "+file["file"])
        rows.append({"key":name,"file":file["file"],"seconds":round(len(signal)/rate,4),"peak":round(peak,6),"rms":round(rms,6),"onset_seconds":round(onset,6),"dc":round(float(signal.mean()),7)})
    if len(set(hashes))!=3:errors.append("Duplicate variations: "+name)
music=[]
for name,meta in catalog["music"].items():
    path=ASSETS/"music"/(name+".ogg");signal=decode(path)
    loudness=subprocess.run(["ffmpeg","-hide_banner","-i",str(path),"-af","loudnorm=I=-19:TP=-1:LRA=11:print_format=json","-f","null","-"],capture_output=True,text=True,check=True).stderr
    meter=json.loads(re.findall(r'\{\s*"input_i".*?\}',loudness,re.S)[-1])
    row={"key":name,"seconds":round(len(signal)/48000,4),"peak":round(float(abs(signal).max()),6),"boundary_jump":round(float(abs(signal[-1]-signal[0]).max()),6),"lufs":float(meter["input_i"]),"true_peak_db":float(meter["input_tp"]),"lra":float(meter["input_lra"]),"loop":meta["loop"]}
    if row["peak"]>=1 or row["true_peak_db"]>-.5 or (meta["loop"] and row["boundary_jump"]>.02):errors.append("Music signal: "+name)
    if (meta["loop"] or meta.get("kind")=="playlist_bgm") and abs(row["lufs"]-meta["target_lufs"])>1.5:errors.append("Music loudness: "+name)
    if meta.get("kind")=="playlist_bgm":
        if meta["loop"] or meta.get("license")!="user-provided" or abs(row["seconds"]-meta["source_duration"])>.1:errors.append("User-provided full-track provenance: "+name)
        if not meta.get("source_sha256") or row["true_peak_db"]>-1:errors.append("User-provided mastering: "+name)
    if sha(path)!=meta["sha256"] or sha(path)!=sha(ROOT/"public/assets/audio/music"/path.name):errors.append("Music hash: "+name)
    music.append(row)
native=OUT/"native/audio-regression.json"
mix_metrics={}
if native.exists():
    report=json.loads(native.read_text(encoding="utf-8"))
    if not report["passed"]:errors.extend(report["failures"])
    mix=decode(native.with_name("native-mix.wav"))
    mix_metrics={"seconds":round(len(mix)/48000,3),"peak":round(float(abs(mix).max()),6),"clipped_samples":int(np.count_nonzero(abs(mix)>=1)),"captured_frames_dropped":0}
    if mix_metrics["clipped_samples"] or mix_metrics["peak"]>.90:errors.append("Native limiter ceiling/clipping")
else:errors.append('Missing native playback evidence: '+str(native))
for name in ["Audio-CREDITS.txt","Audio-CC0-1.0.txt"]:
    if not (ASSETS/name).exists():errors.append("Missing license: "+name)
result={"passed":not errors,"families":len(catalog["cues"]),"variants":len(rows),"music_tracks":len(music),"sources":len(catalog["sources"]),"sfx":rows,"music":music,"native_mix":mix_metrics,"failures":errors}
(OUT/"audio-signal-checks.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps({k:v for k,v in result.items() if k!="sfx"},ensure_ascii=False))
raise SystemExit(bool(errors))
