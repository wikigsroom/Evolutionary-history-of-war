"""Read deployment state and restore only this game's backup to an isolated DB."""
import json,socket
from pathlib import Path
import requests
from remote_admin import connect,command

ROOT=Path(__file__).resolve().parents[2]
URL='https://jyqx-server.sidcloud.cn'


def main():
    checks=[]
    def check(value,name):
        checks.append({'name':name,'passed':bool(value)})
        if not value:raise AssertionError(name)
    check('43.160.222.104' in {row[4][0] for row in socket.getaddrinfo('jyqx-server.sidcloud.cn',443,type=socket.SOCK_STREAM)},'Public DNS resolves to the authorized host')
    bootstrap=requests.get(URL+'/v1/bootstrap',timeout=15)
    manifest=json.loads((ROOT/'godot/assets/data/online-manifest.json').read_text(encoding='utf-8'))
    check(bootstrap.status_code==200 and bootstrap.json()['simulation_hash']==manifest['simulation_hash'],'Trusted public HTTPS returns the current simulation manifest')
    check(all(requests.get(URL+path,timeout=15).status_code==404 for path in ['/healthz','/metrics','/admin']),'Public proxy hides health, metrics and administration')
    client,password=connect()
    try:
        script=r'''python3 - <<'PY'
import datetime,hashlib,json,os,pathlib,subprocess,urllib.request
def run(args):return subprocess.check_output(args,text=True).strip()
def sql(text):return run(['runuser','-u','postgres','--','psql','-d','epochrush_online','-Atc',text])
health=json.load(urllib.request.urlopen('http://127.0.0.1:28187/healthz',timeout=5))
units=['epochrush-online.service','epochrush-health.timer','epochrush-backup.timer','certbot.timer']
enabled=all(run(['systemctl','is-enabled',unit])=='enabled' for unit in units)
release=pathlib.Path('/opt/epochrush/current')
manifest=json.loads((release/'BUNDLE-MANIFEST.json').read_text())
files_ok=all(hashlib.sha256((release/name).read_bytes()).hexdigest()==entry['sha256'] for name,entry in manifest['files'].items())
role=sql("SELECT rolconnlimit::text||'|'||rolsuper::text||'|'||rolcreatedb::text||'|'||rolcreaterole::text||'|'||rolreplication::text FROM pg_roles WHERE rolname='epochrush_server'")
secret=pathlib.Path('/etc/epochrush/online.env').stat()
subprocess.run(['systemctl','start','epochrush-backup.service'],check=True)
backup=max(pathlib.Path('/var/backups/epochrush').glob('*.dump'),key=lambda path:path.stat().st_mtime)
expected=(backup.parent/(backup.name+'.sha256')).read_text().split()[0]
backup_ok=hashlib.sha256(backup.read_bytes()).hexdigest()==expected
# Refuse to remove or overwrite any pre-existing test database.
if sql("SELECT count(*) FROM pg_database WHERE datname='epochrush_restorecheck'")!='0':raise RuntimeError('Restore check name already exists')
subprocess.run(['runuser','-u','postgres','--','createdb','epochrush_restorecheck'],check=True)
try:
    with backup.open('rb') as stream:subprocess.run(['runuser','-u','postgres','--','pg_restore','--no-owner','--no-privileges','-d','epochrush_restorecheck'],stdin=stream,check=True)
    counts=run(['runuser','-u','postgres','--','psql','-d','epochrush_restorecheck','-Atc','SELECT count(*) FROM online_players; SELECT count(*) FROM online_results;']).splitlines()
    restore_ok=len(counts)==2 and all(int(value)>0 for value in counts)
finally:subprocess.run(['runuser','-u','postgres','--','dropdb','epochrush_restorecheck'],check=True)
cert=run(['openssl','x509','-in','/etc/letsencrypt/live/epochrush-public/fullchain.pem','-noout','-enddate']).split('=',1)[1]
expiry=datetime.datetime.strptime(cert,'%b %d %H:%M:%S %Y %Z').replace(tzinfo=datetime.timezone.utc)
proxy=pathlib.Path('/www/server/panel/vhost/nginx/jyqx-server.sidcloud.cn.conf').read_text()
unit=pathlib.Path('/etc/systemd/system/epochrush-online.service').read_text()
observed={'active':run(['systemctl','is-active','epochrush-online.service'])=='active','enabled':enabled,'health':health,'role':role,'secret_permissions':(secret.st_mode&0o777)==0o600 and secret.st_uid==0,'files_ok':files_ok,'release_version':manifest['version'],'backup_sha256_verified':backup_ok,'backup_restore_verified':restore_ok,'restore_rows':{'players':int(counts[0]),'results':int(counts[1])},'certificate_expiry':expiry.isoformat(),'certificate_valid_30_days':expiry>datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=30),'renewal_configured':pathlib.Path('/etc/letsencrypt/renewal/epochrush-public.conf').exists() and pathlib.Path('/etc/letsencrypt/renewal-hooks/deploy/epochrush-nginx.sh').exists(),'private_gateway':run(['ss','-lnt']).find('127.0.0.1:28187')>=0,'private_database':run(['ss','-lnt']).find('127.0.0.1:5432')>=0,'logs_and_limits':proxy.count('access_log off;')==2 and proxy.count('error_log /dev/null crit;')==2 and 'MemoryMax=320M' in unit and 'User=epochrush' in unit,'health_guards':pathlib.Path('/opt/epochrush/current/ops/health.sh').read_text().find('524288')>=0}
print('EPOCH_OPERATION_JSON='+json.dumps(observed))
PY'''
        output=command(client,script,password,sudo=True,timeout=90).decode()
        prefix='EPOCH_OPERATION_JSON='
        observed=json.loads(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)))
    finally:client.close()
    check(observed['active'] and observed['health']['ok'],'Native systemd gateway and dedicated database are healthy')
    check(observed['enabled'],'Game service, health, backup and certificate timers are enabled')
    check(observed['health']['max_matches']==2 and observed['health']['active_matches']==0 and not observed['health']['draining'],'Two-match admission is healthy and QA leaves no active matches')
    check(observed['role']=='4|false|false|false|false' and observed['secret_permissions'],'Dedicated database role is restricted and environment remains root-only')
    check(observed['files_ok'] and observed['release_version']=='0.8.1','Every deployed authority file matches the final Linux release manifest')
    check(observed['backup_sha256_verified'] and observed['backup_restore_verified'],'Fresh database dump verifies and restores real records into an isolated database')
    check(observed['certificate_valid_30_days'] and observed['renewal_configured'],'Trusted certificate has over 30 days remaining and its renewal hook is installed')
    check(observed['private_gateway'] and observed['private_database'],'Gateway and database listen on loopback rather than public ports')
    check(observed['logs_and_limits'] and observed['health_guards'],'Proxy ticket logging is disabled and native resource/disk guards are configured')
    result={'endpoint':URL,'checks':checks,'observations':observed,'same_host_backup_only':True}
    (ROOT/'output/qa/public-online/server-operations.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('PUBLIC OPERATIONS:',len(checks),'checks passed')


if __name__=='__main__':main()
