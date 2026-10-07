"""Compare both versioned APKs with the production web build, including ZIP CRC."""
from pathlib import Path
import hashlib
import json,sys
import zipfile

root = Path(__file__).resolve().parents[1]
version = json.loads((root / 'package.json').read_text(encoding='utf-8'))['version']
candidate='--candidate' in sys.argv
folder=root/(f'output/releases/candidates/v{version}/android' if candidate else 'output/releases/android')
files = sorted(p for p in (root / 'dist').rglob('*') if p.is_file())
reports = []
for suffix in ['debug', 'release-unsigned']:
    apk = folder / f'Epoch-Rush-{version}-{"Candidate-" if candidate else ""}Android-{suffix}.apk'
    mismatches = []
    with zipfile.ZipFile(apk) as archive:
        bad = archive.testzip()
        for source in files:
            relative = source.relative_to(root / 'dist').as_posix()
            name = 'assets/public/' + relative
            try:
                packed = archive.read(name)
            except KeyError:
                mismatches.append({'path': relative, 'reason': 'missing'})
                continue
            if hashlib.sha256(packed).digest() != hashlib.sha256(source.read_bytes()).digest():
                mismatches.append({'path': relative, 'reason': 'hash'})
    reports.append({'file': apk.name, 'checkedFiles': len(files), 'mismatches': mismatches,
                    'crcVerified': bad is None, 'crcFailure': bad})

report = {'version': version, 'passed': all(not r['mismatches'] and r['crcVerified'] for r in reports),
          'packages': reports}
qa=root/'output/qa'/('v'+'.'.join(version.split('.')[:2]));qa.mkdir(parents=True,exist_ok=True)
(qa / f'android-bundle-{"candidate-" if candidate else ""}validation.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
raise SystemExit(not report['passed'])
