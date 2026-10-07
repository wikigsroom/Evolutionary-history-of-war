"""Subset licensed upstream fonts for every shipped native game string."""
from pathlib import Path
import json, re
from fontTools import subset

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'godot/assets/fonts'
text = ''.join(p.read_text(encoding='utf-8') for folder in ['godot/scripts', 'godot/assets/data'] for p in (ROOT/folder).rglob('*') if p.suffix in ['.gd', '.json'])
text += ''.join(chr(i) for i in range(32,127)) + 'ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ→←·—：＋％亿万'
required = set(map(ord,text))
report = []
for name,source in [('resource-rounded','resource-rounded/ResourceHanRoundedCN-Medium.ttf'),('smiley','smiley/SmileySans-Oblique.ttf')]:
    options = subset.Options(); options.flavor='woff2'; options.layout_features=['*']
    font = subset.load_font(str(ROOT/'output/font-sources'/source),options)
    missing = sorted({ord(c) for c in re.findall(r'[\u3400-\u4dbf\u4e00-\u9fff]',text)} - set(font.getBestCmap()))
    if missing: raise RuntimeError(name + ' missing Chinese: ' + ''.join(map(chr,missing)))
    selection = subset.Subsetter(options=options); selection.populate(unicodes=required); selection.subset(font)
    family = 'Epoch Rounded' if name=='resource-rounded' else 'Epoch Display'
    for record in font['name'].names:
        if record.nameID in [1,4,16]: record.string=family.encode(record.getEncoding())
        elif record.nameID==6: record.string=family.replace(' ','').encode(record.getEncoding())
    target=DEST/(name+'.woff2'); subset.save_font(font,str(target),options)
    report.append({'font':target.name,'source':source,'bytes':target.stat().st_size,'missingChinese':missing})
folder=ROOT/'output/qa/ten-eras';folder.mkdir(parents=True,exist_ok=True)
(folder/'font-coverage.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Native Chinese subsets:', report)
