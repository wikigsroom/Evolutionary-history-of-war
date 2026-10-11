"""Exercise real native HTTP recovery against an owned loopback fixture, no VM."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pack', action='store_true')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'godot/assets/data/online-manifest.json').read_text(encoding='utf-8'))
    state = {'offline': False, 'initial_failures': 3, 'requests': 0, 'tokens': {}, 'bootstrap': 0}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def response(self, code, value):
            data = value.encode() if isinstance(value, str) else json.dumps(value).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'text/html' if isinstance(value, str) else 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path.startswith('/qa/'):
                if self.path == '/qa/offline': state['offline'] = True
                if self.path == '/qa/online': state['offline'] = False
                self.response(200, {'requests': state['requests'], 'bootstrap': state['bootstrap']})
                return
            state['requests'] += 1
            if self.path == '/v1/bootstrap':
                state['bootstrap'] += 1
                if state['initial_failures']:
                    state['initial_failures'] -= 1
                    self.response(502, '<html>temporarily unavailable</html>')
                    return
            if state['offline']:
                self.response(503, '<html>temporarily unavailable</html>')
            elif self.path == '/v1/bootstrap':
                self.response(200, {'ok': True, **manifest})
            elif self.headers.get('Authorization', '').removeprefix('Bearer ') not in state['tokens']:
                self.response(401, {'ok': False, 'error': 'UNAUTHORIZED'})
            else:
                self.response(200, {'ok': True, 'activity': {'kind': '', 'id': ''}})

        def do_POST(self):
            state['requests'] += 1
            body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
            if state['offline']:
                self.response(503, '<html>temporarily unavailable</html>')
                return
            player = hashlib.sha256(body['installation_key'].encode()).hexdigest()[:24]
            token = 'fixture-token-' + player
            state['tokens'][token] = player
            self.response(200, {'ok': True, 'player_id': player, 'access_token': token})

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    env = dict(os.environ)
    env['EPOCH_ONLINE_URL'] = f'http://127.0.0.1:{server.server_port}'
    command = [os.sys.executable, str(ROOT / 'tools/online/run_native_checks.py'), '--script', 'qa/online/lobby_reconnect.gd', '--headless']
    if args.pack: command.append('--pack')
    try:
        result = subprocess.run(command, env=env, cwd=ROOT, timeout=155)
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=2)
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
