"""Fault-inject only the authorized game's service and its dedicated SQL sessions."""
from pathlib import Path
import json,os,subprocess,time
from remote_admin import connect,command
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/qa/public-online/recovery';OUT.mkdir(parents=True,exist_ok=True)


def main():
    for name in ['gateway-fault-ready.json','gateway-fault-done','database-fault-ready.json','database-fault-done','public-native-recovery.json']:(OUT/name).unlink(missing_ok=True)
    env=dict(os.environ);env['EPOCH_QA_OUTPUT']=str(OUT)
    with (OUT/'native.log').open('wb') as log:
        process=subprocess.Popen([str(ROOT/'godot/toolchain/editor/Godot_v4.7.2-stable_win64.exe'),'--headless','--path',str(ROOT/'godot'),'--main-pack',str(ROOT/'godot/build/windows/Epoch-Rush-Godot.exe'),'--script',str(ROOT/'godot/qa/online/public_recovery.gd')],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        client,password=connect()
        try:
            for kind in ['gateway','database']:
                deadline=time.monotonic()+90
                while not (OUT/(kind+'-fault-ready.json')).exists():
                    if process.poll() is not None:raise RuntimeError('Native client exited before fault stage')
                    if time.monotonic()>deadline:raise TimeoutError('Native stage timeout')
                    time.sleep(.2)
                script="systemctl kill --kill-who=main --signal=SIGKILL epochrush-online.service" if kind=='gateway' else "runuser -u postgres -- psql -v ON_ERROR_STOP=1 -Atc \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='epochrush_online' AND usename='epochrush_server' AND backend_type='client backend';\""
                command(client,script,password,sudo=True,timeout=15)
                (OUT/(kind+'-fault-done')).touch()
            process.wait(timeout=90)
        finally:
            client.close()
            if process.poll() is None:process.kill();process.wait()
    report=json.loads((OUT/'public-native-recovery.json').read_text(encoding='utf-8'))
    assert process.returncode==0 and all(row['passed'] for row in report['checks'])
    text=(OUT/'native.log').read_text(encoding='utf-8',errors='replace')
    assert 'SCRIPT ERROR:' not in text and '\nERROR:' not in text
    print('PUBLIC NATIVE RECOVERY:',len(report['checks']),'checks passed')


if __name__=='__main__':main()
