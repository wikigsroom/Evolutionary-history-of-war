"""Record only the game's own viewport using the released embedded PCK."""
from pathlib import Path
import argparse,os,subprocess,json,time

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/marketing/2026-10-08'
SCRIPTS={'probe':'marketing_probe.gd','screenshots':'marketing_screenshots.gd','recording':'marketing_recording.gd','showcase':'marketing_showcase.gd'}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('mode',choices=list(SCRIPTS))
    args=parser.parse_args()
    dest=OUT/'source/native'/args.mode
    dest.mkdir(parents=True,exist_ok=True)
    environment=os.environ.copy()
    environment['EPOCH_MARKETING_OUTPUT']=str(dest)
    environment['EPOCH_MARKETING_SCREENSHOTS']=str(OUT/'screenshots')
    environment['EPOCH_MARKETING_DIRECTOR']=str(ROOT/'godot/qa/marketing_director.gd')
    engine=ROOT/'godot/toolchain/editor/Godot_v4.7.2-stable_win64_console.exe'
    executable=ROOT/'godot/build/windows/Epoch-Rush-Godot.exe'
    commands=[str(engine),'--path',str(ROOT/'godot'),'--main-pack',str(executable),'--script',str(ROOT/'godot/qa'/SCRIPTS[args.mode]),'--windowed','--resolution','1920x1080','--position','-19000,-19000','--rendering-method','gl_compatibility','--rendering-driver','opengl3','--audio-driver','Dummy','--disable-vsync']
    if args.mode in ['probe','recording','showcase']:
        commands+=['--write-movie',str(dest/(args.mode+'.avi')),'--fixed-fps','30']
    else:
        commands+=['--fixed-fps','30']
    started=time.time()
    with open(dest/'capture.log','w',encoding='utf-8') as log:
        child=subprocess.Popen(commands,cwd=ROOT,env=environment,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        (dest/'process.json').write_text(json.dumps({'pid':child.pid,'command':commands,'started_unix':started},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(f'Native {args.mode} PID {child.pid}',flush=True)
        code=child.wait()
    (dest/'exit.json').write_text(json.dumps({'pid':child.pid,'exit_code':code,'wall_seconds':round(time.time()-started,3)},indent=2)+'\n',encoding='utf-8')
    print(f'Native {args.mode} exit {code}',flush=True)
    if code:
        print((dest/'capture.log').read_text(encoding='utf-8',errors='replace')[-7000:])
        raise SystemExit(code)

if __name__=='__main__':main()
