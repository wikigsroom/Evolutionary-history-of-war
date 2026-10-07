"""Write the verified final release manifest."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, re

root = Path(__file__).resolve().parents[1]
version = json.loads((root / 'package.json').read_text(encoding='utf-8'))['version']
release = root / f'output/releases'
qa = root / ('output/qa/v' + '.'.join(version.split('.')[:2]))

def read_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def artifact(relative: str):
    path = root / relative
    if not path.is_file():
        raise RuntimeError(f'Missing final artifact: {relative}')
    data = path.read_bytes()
    return {'path': relative.replace('\\', '/'), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}

gate = read_json(qa / 'final-release-gate.log')
if gate.get('acceptedActors') != gate.get('requiredActors') or gate.get('missing'):
    raise RuntimeError('Animation release gate is incomplete')
tests_text = (qa / 'tests-final.log').read_text(encoding='utf-8-sig')
test_match = re.findall(r'Tests\s+(\d+)\s+passed', tests_text)
if not test_match or re.search(r'\bFAIL\b|\d+ failed', tests_text, re.I):
    raise RuntimeError('Current test log does not confirm a passing suite')
windows = read_json(qa / 'windows-bundle-validation.json')
android = read_json(qa / 'android-bundle-validation.json')
if not windows.get('passed') or not android.get('passed'):
    raise RuntimeError('Platform bundle validation failed')
native_lines = (qa / 'windows-native.log').read_text(encoding='utf-8-sig').splitlines()
native = next((json.loads(line)['desktopQa'] for line in native_lines if line.startswith('{"desktopQa"')), None)
if not native or not all(native.get(key) for key in ('engineReady', 'menuReady', 'secureContext', 'indexedDB')) or native.get('images'):
    raise RuntimeError('Windows native launch check failed')
budget = read_json(qa / 'animation-loading-budget.json')
if not budget.get('withinBudget'):
    raise RuntimeError('Animation bootstrap budget failed')

files = [
    artifact(f'output/releases/windows/Epoch-Rush-{version}-Windows-x64.exe'),
    artifact(f'output/releases/android/Epoch-Rush-{version}-Android-debug.apk'),
    artifact(f'output/releases/android/Epoch-Rush-{version}-Android-release-unsigned.apk'),
    artifact(f'output/releases/source/Epoch-Rush-{version}-source.zip'),
]
animation = read_json(root / 'src/content/animation-manifest.json')
accepted = sum(sheet.get('review') == 'accepted' for sheet in animation['actors'].values())
standard = read_json(qa / 'balance-standard.json')['standard']
campaign = read_json(qa / 'balance-campaign.json')['campaign']
manifest = {
    'version': version,
    'releaseKind': 'final',
    'createdAtUtc': datetime.now(timezone.utc).isoformat(),
    'status': 'playable_final_local_release',
    'finalReleaseAccepted': True,
    'artifacts': files,
    'validation': {
        'testCasesPassed': int(test_match[-1]),
        'windows': windows,
        'android': android,
        'nativeWindowsLaunch': native,
        'standardMatchSamples': len(standard),
        'standardWins': sum(row.get('winner') == 0 for row in standard),
        'campaignRows': len(campaign),
        'campaignWins': sum(row.get('winner') == 0 for row in campaign),
        'animationBudget': budget,
        'assetValidation': read_json(qa / 'asset-audio-validation.json'),
        'sourceArchive': read_json(release / 'source/source-archive.json'),
    },
    'animation': {
        'requiredActors': len(animation['actors']),
        'acceptedActors': accepted,
        'model': 'gpt-image-2.5',
        'route': 'Sub2 CLI edit',
        'gatewayStatus': 'recovered; all reviewed actor sheets accepted',
    },
    'limitations': [
        'Android release APK is unsigned and needs a release key before store distribution',
        'No physical Android device performance validation',
        'iOS project synced; no IPA compilation/signing on Windows',
        'Full human difficulty and audio listening review remain separate release operations',
    ],
    'evidenceDirectory': qa.relative_to(root).as_posix(),
}
(release / 'release-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'status': manifest['status'], 'artifacts': len(files), 'testsPassed': int(test_match[-1]), 'acceptedAnimations': accepted}, ensure_ascii=False))
