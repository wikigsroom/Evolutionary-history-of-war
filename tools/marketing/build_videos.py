"""Native footage mastering and a timed 45-second gameplay trailer."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import argparse,json,subprocess,shutil
from PIL import Image,ImageDraw
from graphics import ROOT,OUT,INK,GOLD,IVORY,label

FFMPEG=shutil.which('ffmpeg')
FFPROBE=shutil.which('ffprobe')
VIDEO=OUT/'source/video'

def run(command,name):
    log=VIDEO/(name+'.log')
    print('Rendering '+name,flush=True)
    with open(log,'w',encoding='utf-8') as handle:
        result=subprocess.run([FFMPEG,'-hide_banner','-loglevel','warning','-y',*command],stdout=handle,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        print(log.read_text(encoding='utf-8',errors='replace')[-4000:],flush=True)
        raise RuntimeError('FFmpeg failed: '+name)
    print('Finished '+name,flush=True)

def probe(file):
    return json.loads(subprocess.run([FFPROBE,'-v','error','-show_streams','-show_format','-of','json',str(file)],check=True,capture_output=True,text=True,encoding='utf-8').stdout)

def recording():
    source=OUT/'source/native/recording/recording.avi'
    dest=OUT/'videos/gameplay-120s.mp4'
    run(['-i',str(source),'-map','0:v:0','-map','0:a:0','-t','120','-frames:v','3600','-vf','fps=30,setsar=1,format=yuv420p','-c:v','libx264','-preset','medium','-crf','17','-threads','4','-c:a','aac','-b:a','192k','-ar','48000','-ac','2','-movflags','+faststart',str(dest)],'gameplay-master')
    report={'source':str(source.relative_to(OUT)),'output':str(dest.relative_to(OUT)),'changes':'trim only the writer tail after frame 3600; native game resolution, full HUD, native music and SFX; no edits, speed changes, loop or external overlays','probe':probe(dest)}
    (VIDEO/'gameplay-master.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def chapter_overlay(text):
    overlay=Image.new('RGBA',(1920,1080))
    d=ImageDraw.Draw(overlay)
    for y in range(190):
        d.line((0,y,1920,y),fill=(*INK,round(140*(1-y/190)**1.4)))
    d.rectangle((84,58,91,126),fill=GOLD)
    box=label(overlay,text,70,115,66,tracking=4,color=IVORY)
    return overlay,box

def trailer():
    meta=json.loads((OUT/'source/native/showcase/showcase-report.json').read_text(encoding='utf-8'))
    source=OUT/'source/native/showcase/showcase.avi'
    chosen=[(1,'从石器出征'),(4,'盾墙接敌 · 重骑破阵'),(6,'火炮与钢铁'),(8,'指挥，改变战局'),(9,'迈向无人战术'),(10,'轨道审判')]
    duration=[4.3]+[6.3]*6+[5.0]
    sequence=[];jobs=[]
    for index,name in [(0,'opening'),(7,'ending')]:
        output=VIDEO/f'segment-{index:02d}.mp4'
        # A slow, bounded camera push keeps the exact character intact.
        motion="zoompan=z='min(1.026,1+on*0.0002)':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s=1920x1080:fps=30"
        filters=motion+',setsar=1,format=yuv420p'
        if index==0:filters+=',fade=t=in:st=0:d=0.4'
        else:filters+=',fade=t=out:st=4.4:d=0.6'
        jobs.append((f'trailer-{name}',['-loop','1','-framerate','30','-i',str(VIDEO/(name+'-card.png')),'-f','lavfi','-i','anullsrc=r=48000:cl=stereo','-vf',filters,'-map','0:v','-map','1:a','-t',str(duration[index]),'-frames:v',str(round(duration[index]*30)),'-c:v','libx264','-preset','fast','-crf','17','-threads','3','-c:a','aac','-b:a','192k','-pix_fmt','yuv420p','-movflags','+faststart',str(output)]))
        sequence.append({'index':index,'role':name,'duration':duration[index],'file':output.name})
    for index,(age,title) in enumerate(chosen,1):
        row=next(x for x in meta['clips'] if x['era']==f'A{age}')
        start=float(row['normal_start_seconds'])+.55
        if start+duration[index]>float(row['normal_start_seconds'])+float(row['normal_duration']):raise RuntimeError('Trailer edit exceeds normal-rate recorded range')
        overlay,box=chapter_overlay(title)
        image=OUT/'source/type'/f'chapter-{index:02d}.png';overlay.save(image,optimize=True)
        output=VIDEO/f'segment-{index:02d}.mp4'
        filters='[0:v]setpts=PTS-STARTPTS,crop=736:414:272:84,scale=1920:1080:flags=neighbor,fps=30,setsar=1[v];[1:v]format=rgba,fade=t=in:st=0:d=0.25:alpha=1[t];[v][t]overlay=format=auto:shortest=1,format=yuv420p[scene]'
        jobs.append((f'trailer-chapter-{index:02d}',['-ss',f'{start:.6f}','-i',str(source),'-loop','1','-framerate','30','-i',str(image),'-filter_complex',filters,'-map','[scene]','-map','0:a','-af',f'volume=1.18,afade=t=in:st=0:d=0.08,afade=t=out:st={duration[index]-.15}:d=0.15','-t',str(duration[index]),'-frames:v',str(round(duration[index]*30)),'-c:v','libx264','-preset','fast','-crf','17','-threads','3','-c:a','aac','-b:a','192k','-ar','48000','-ac','2','-pix_fmt','yuv420p','-movflags','+faststart',str(output)]))
        sequence.append({'index':index,'role':'gameplay','era':f'A{age}','title':title,'duration':duration[index],'file':output.name,'normal_source_start':float(row['normal_start_seconds']),'normal_source_duration':float(row['normal_duration']),'edit_start':start,'crop':[272,84,736,414],'overlay':box,'raid':row.get('raid',False)})
    with ThreadPoolExecutor(max_workers=2) as pool:
        pending={pool.submit(run,cmd,name):name for name,cmd in jobs}
        for future in as_completed(pending):future.result()
    sequence.sort(key=lambda x:x['index'])
    commands=[]
    for row in sequence:commands+=['-i',str(VIDEO/row['file'])]
    commands+=['-i',str(ROOT/'godot/assets/audio/music/age2.ogg')]
    filters=[]
    for i in range(8):
        filters.append(f'[{i}:v]settb=AVTB,setpts=PTS-STARTPTS,fps=30,format=yuv420p[v{i}]')
        filters.append(f'[{i}:a]aresample=48000,asetpts=PTS-STARTPTS[a{i}]')
    elapsed=duration[0];vprevious='v0';aprevious='a0'
    for i in range(1,8):
        offset=elapsed-.3
        filters.append(f'[{vprevious}][v{i}]xfade=transition=fade:duration=0.3:offset={offset:.6f}[vx{i}]')
        filters.append(f'[{aprevious}][a{i}]acrossfade=d=0.3:c1=tri:c2=tri[ax{i}]')
        vprevious=f'vx{i}';aprevious=f'ax{i}';elapsed+=duration[i]-.3
    if abs(elapsed-45)>1e-8:raise RuntimeError('Trailer duration arithmetic is wrong')
    # Use a licensed existing game score; keep transient game sounds audible.
    filters.append('[8:a]aresample=48000,aloop=loop=-1:size=2091960,atrim=duration=45,volume=0.53,afade=t=in:st=0:d=0.8,afade=t=out:st=43.4:d=1.6[music]')
    filters.append(f'[{aprevious}][music]amix=inputs=2:duration=longest:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=10,aresample=48000[mix]')
    graph=VIDEO/'trailer-filter.ffgraph';graph.write_text(';\n'.join(filters),encoding='utf-8')
    dest=OUT/'videos/trailer-45s-1920x1080.mp4'
    run([*commands,'-filter_complex_threads','2','-filter_complex_script',str(graph),'-map',f'[{vprevious}]','-map','[mix]','-t','45','-frames:v','1350','-r','30','-c:v','libx264','-preset','medium','-crf','17','-threads','4','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k','-ar','48000','-ac','2','-movflags','+faststart',str(dest)],'trailer-master')
    report={'duration':45,'fps':30,'dimensions':[1920,1080],'transition_seconds':.3,'scenes':sequence,'native_source':str(source.relative_to(OUT)),'music':'godot/assets/audio/music/age2.ogg','music_license':'licenses/Audio-CREDITS.txt','notes':'Six clips are original-rate native gameplay, cropped for cinematic framing. Excludes every accelerated preparation frame. Intro/end cards use approved crest and generated promotional art. No fabricated game animation or multiplayer claims.','probe':probe(dest)}
    (VIDEO/'trailer-edit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def previews():
    for file,times,name in [(OUT/'videos/gameplay-120s.mp4',[1,4,6,18,40,65,85,100,118],'gameplay-contact'),(OUT/'videos/trailer-45s-1920x1080.mp4',[1.5,5.5,11,17,24,30,35.5,40,43.5],'trailer-contact')]:
        directory=OUT/'source/video'/name;directory.mkdir(exist_ok=True)
        for i,t in enumerate(times):
            run(['-ss',str(t),'-i',str(file),'-frames:v','1','-update','1',str(directory/f'{i:02d}.png')],name+f'-frame-{i:02d}')
        board=Image.new('RGB',(1920,1176),INK);d=ImageDraw.Draw(board)
        from PIL import ImageFont
        font=ImageFont.truetype(str(OUT/'source/fonts/body.ttf'),24)
        for i,t in enumerate(times):
            image=Image.open(directory/f'{i:02d}.png').convert('RGB').resize((636,358),Image.Resampling.LANCZOS)
            x=(i%3)*640;y=(i//3)*392
            board.paste(image,(x+2,y+2));d.text((x+16,y+366),f'{t:.1f}s',font=font,fill=IVORY)
        board.save(OUT/'previews'/(name+'.jpg'),quality=95,subsampling=0)
    shutil.copy2(OUT/'covers/horizontal-cover-1920x1080.jpg',OUT/'previews/trailer-poster.jpg')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['recording','trailer','previews','all']);args=parser.parse_args()
    if not FFMPEG or not FFPROBE:raise RuntimeError('Native FFmpeg/ffprobe required')
    VIDEO.mkdir(parents=True,exist_ok=True)
    if args.stage in ['recording','all']:recording()
    if args.stage in ['trailer','all']:trailer()
    if args.stage in ['previews','all']:previews()

if __name__=='__main__':main()
