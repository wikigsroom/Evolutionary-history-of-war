"""Record verified local candidate artifacts without declaring final art complete."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, re

root = Path(__file__).resolve().parents[1]
version = json.loads((root / 'package.json').read_text(encoding='utf-8'))['version']
release = root / f'output/releases/candidates/v{version}'
qa = root / ('output/qa/v' + '.'.join(version.split('.')[:2]))
read_json = lambda name: json.loads((qa / name).read_text(encoding='utf-8'))
windows = read_json('windows-bundle-candidate-validation.json')
android = read_json('android-bundle-candidate-validation.json')
if not windows['passed'] or not android['passed']:
    raise RuntimeError('Candidate package validation must pass before handoff')
tests_log = (qa / 'tests-final.log').read_text(encoding='utf-8-sig')
passed = re.findall(r'Tests\s+(\d+)\s+passed', tests_log)
if not passed or re.search(r'\bFAIL\b|\d+ failed', tests_log):
    raise RuntimeError('Current test log does not confirm a passing suite')
native_lines = (qa / 'windows-native.log').read_text(encoding='utf-8-sig').splitlines()
native = next(json.loads(line)['desktopQa'] for line in native_lines if line.startswith('{"desktopQa"'))
if not all(native[key] for key in ('engineReady', 'menuReady', 'secureContext', 'indexedDB')) or native['images']:
    raise RuntimeError('Windows native launch check failed')
if not (qa / 'windows-portable.png').is_file():
    raise RuntimeError('Portable artifact launch screenshot missing')
paths = [
    release / f'windows/Epoch-Rush-{version}-Candidate-Windows-x64.exe',
    release / f'android/Epoch-Rush-{version}-Candidate-Android-debug.apk',
    release / f'android/Epoch-Rush-{version}-Candidate-Android-release-unsigned.apk',
    release / f'source/Epoch-Rush-{version}-Candidate-source.zip',
]
artifacts = []
for file in paths:
    if not file.is_file():
        raise RuntimeError(f'Missing candidate artifact: {file.name}')
    artifacts.append({'path': file.relative_to(root).as_posix(), 'bytes': file.stat().st_size,
                      'sha256': hashlib.sha256(file.read_bytes()).hexdigest()})
animation = json.loads((root / 'src/content/animation-manifest.json').read_text(encoding='utf-8'))
accepted = sum(sheet.get('review') == 'accepted' for sheet in animation['actors'].values())
benchmark = read_json('balance-standard.json')['standard']
campaign = read_json('campaign-combat.json')
report = {
    'version': version, 'releaseKind': 'candidate', 'createdAtUtc': datetime.now(timezone.utc).isoformat(),
    'status': 'playable_candidate_waiting_for_authored_animation_assets', 'finalReleaseAccepted': False,
    'artifacts': artifacts,
    'validation': {'testCasesPassed': int(passed[-1]), 'windows': windows, 'android': android,
                   'nativeWindowsLaunch': {'engineReady': True, 'menuReady': True, 'secureContext': True, 'indexedDB': True, 'brokenImages': 0},
                   'standardMatchSamples': len(benchmark), 'standardWins': sum(row['winner'] == 0 for row in benchmark),
                   'campaignMissionsWon': sum(row['winner'] == 0 for row in campaign['rows']),
                   'sourceArchive': json.loads((release / 'source/source-archive.json').read_text(encoding='utf-8'))},
    'animation': {'requiredActors': 26, 'acceptedActors': accepted, 'model': 'gpt-image-2.5',
                   'gatewayStatus': 'HTTP 400: image_generation tool declaration rejected',
                   'candidateUsesPreviousCharacterArt': True, 'u14RiderArtStillPending': True},
    'limitations': ['New complete character animations pending designated gateway repair',
                    'Full human campaign and difficulty/construct balance review pending',
                    'No physical Android device performance validation', 'iOS project synced; no IPA compilation/signing'],
    'evidenceDirectory': qa.relative_to(root).as_posix(),
}
release.mkdir(parents=True, exist_ok=True)
(release / 'release-manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'status': report['status'], 'artifacts': len(artifacts), 'testsPassed': int(passed[-1]), 'acceptedAnimations': accepted}))
