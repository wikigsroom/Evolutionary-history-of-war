"""Prepare the complete Epoch Rush marketing production workspace."""
from pathlib import Path
from PIL import Image, ImageDraw
from fontTools.ttLib import TTFont
from fontTools import subset
import hashlib,json,shutil

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/marketing/2026-10-08'
ART=ROOT/'output/imagegen/marketing/2026-10-08'
BRAND=ROOT/'output/imagegen/brand-kit/2026-10-08-pixel-crest'

THEMES=[
    ('01-evolution','纪元急袭','',
     'A single epic side-view battlefield stretching from primitive palisades and classical colonnades at the distant left, through a mighty red-banner medieval fortress and industrial smoke, to modern armored firepower and an icy blue orbital citadel at the right. Red-gold and cool cyan armies meet across the entire lower half. Stone shield infantry, archers, heavy armored knights, an artillery cannon, tanks and a small energy mech read as a progression of civilization. Gates of the left and right bases face inward toward each other. A graceful golden ribbon of square time particles links the eras. The war is at its peak; dust, shield sparks and small blue energy trails punctuate the battle.'),
    ('02-medieval','纪元急袭','',
     'A vivid medieval siege in warm sunset firelight against a deep navy sky. Giant opposing stone castles with warm red-and-gold banners on the left and blue banners on the right, both gates face toward the battlefield center. In the lower half, armored shield infantry collide, crossbowmen fire from the second rank, a red-caped heavy cavalry knight breaks into the enemy shield line, and a small falcon flies beside a scout. Heavy armor and splintered shields convey weight, while the front line remains clearly readable. Red-gold pixel sparks and square dust plumes. Include distant classical ruins to connect the world to its older eras. No central portrait.'),
    ('03-industrial','纪元急袭','',
     'Gunpowder and industrial-trench warfare across a rugged side-view battle line. A red military fortress on the left and a cool steel fortified opposing base on the right face toward each other. Line infantry, muzzle flashes, a large wooden-wheel early cannon, industrial field artillery and a distinctive rhomboid early tank clash along the lower two-thirds. Distant brick factories, war trenches and smokestacks under an ink-navy evening sky. A bright but controlled brass-gold artillery blast near the lower middle creates the focal action. Broken earth, flying square embers and volumetric pixel smoke. Early army musicians and a tiny field medic give troops variety. Clear mass contrast between bases and infantry.'),
    ('04-modern','纪元急袭','',
     'Modern mechanized single-lane warfare at dusk, using the reference modern desert headquarters and main battle tank designs. A massive warm red-gold army base at the far left and an equally imposing cool blue enemy command bunker at the far right open inward. Desert assault soldiers, a precision marksman, shoulder-fired anti-armor missiles, two main battle tanks and a combat medic advance in opposing formations across the lower half. A grounded missile launch platform fires diagonally toward the far side. Fiery impact flashes, displaced dust, tank tread debris and small shell casings. Pixel military silhouettes, strong readable scale, cinematic dark blue sky and warm brass explosions. Aircraft are small distant background accents, never the main subject.'),
    ('05-orbital','纪元急袭','',
     'A striking futuristic orbital-era ground battle. Use the reference luminous orbital fortresses and electric-arc mech designs. Huge red-accent armored bastion at lower left and ice-blue technological citadel at lower right have entrances facing the center. Alloy shield infantry, magnetic rail shooters, a phase spear soldier, a prominent but not oversized walking electric-arc mech and a temporal engineer clash across the lower half. Magenta-red and cyan energy bolts, shield cracking fragments and a narrow orbital strike descending near the right-center, leaving gold-white square shock sparks and pixel smoke. Deep space-navy sky, distant ringed orbital structures, terrain still clearly horizontal. Echo the gold time ribbon without creating any shield emblem or portrait.'),
    ('06-no-logo','', '',
     'A complete self-contained scenic key art illustration with NO reserved blank brand panel: opposing gigantic red-gold medieval castle and cyan futuristic citadel framing a rich battle across the center and lower half, gates face inward. A sweeping army progression from shield infantry and heavy mounted knights to cannons, tanks and an energy mech. Distant primitive camp, classical temple, smokestacks and orbital structures layered into a dramatic mountainous night panorama. Warm central horizon glow, detailed pixel clouds and a small trail of golden time-rift particles. The scene itself is the subject; no portrait, no crest, no badge, no emblem in the sky and no large empty space for a logo. The upper third can hold atmospheric sky but the lower two-thirds are a satisfying finished illustration, with readable troop formations and two-sided action.'),
]

def main():
    for folder in ['screenshots','videos','promotional','covers','wallpapers','copy','previews','source','source/native','source/video','source/type','source/fonts','licenses']:
        (OUT/folder).mkdir(parents=True,exist_ok=True)
    ART.mkdir(parents=True,exist_ok=True)
    shutil.copy2(BRAND/'selected-logo.png',ART/'selected-logo.png')
    shutil.copy2(BRAND/'selected-logo.png',OUT/'source/selected-logo.png')
    shutil.copy2(BRAND/'reference-game-bases.jpg',ART/'reference-game-bases.jpg')
    source=ROOT/'docs/epoch-rush/game-introduction-and-developer-message.zh-CN.md'
    shutil.copy2(source,OUT/'copy/game-introduction-and-developer-message.md')
    recommend={
      'headline':'纪元急袭',
      'recommendation':'从骨盾与投石到坦克与机甲，在同一条战线上组织军团、指挥主将。把经验投入进化，或用一次奇袭稳住防线；抓住换代时机，让新时代的军队带着你反攻敌方营寨。',
      'short':'招募军团，指挥主将，从石器部落一路打到轨道文明。',
      'feature_strip':'10 个时代 · 50 个兵种 · 6 位主将 · 20 关战役',
    }
    (OUT/'copy/homepage-recommendation.json').write_text(json.dumps(recommend,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (OUT/'copy/homepage-recommendation.txt').write_text('\n\n'.join([recommend['headline'],recommend['recommendation'],recommend['short'],recommend['feature_strip']])+'\n',encoding='utf-8')
    intro=source.read_text(encoding='utf-8')
    a,b=intro.split('## 开发者的话',1)
    (OUT/'copy/game-introduction.txt').write_text(a.split('## 游戏简介',1)[1].strip().replace('**','')+'\n',encoding='utf-8')
    (OUT/'copy/developer-message.txt').write_text(b.strip()+'\n',encoding='utf-8')
    all_text=intro+'\n'.join(recommend.values())+'纪元急袭 EPOCH RUSH: PIXEL COMMAND 从石器到轨道 指挥决定战局 抓住进化时机 组建你的军团 将战线推向胜利 原生实机演出 战鼓 烟幕 时序补给 Windows Android 单机策略时代战争 从石器出征 盾墙接敌 重骑破阵 火炮与钢铁 指挥改变战局 迈向无人战术 轨道审判 即刻出征 首页营地 主将整军 实机截图 宣传美术 宣传片封面 游戏库背景 无文字版本 素材总览'+''.join(a+b+c for a,b,c,d in THEMES)
    required=set(map(ord,all_text))|set(range(32,127))
    for name,source_font in [('display',ROOT/'output/font-sources/smiley/SmileySans-Oblique.ttf'),('body',ROOT/'output/font-sources/resource-rounded/ResourceHanRoundedCN-Medium.ttf')]:
        f=TTFont(source_font)
        missing=sorted(required-set(f.getBestCmap()))
        # Whitespace and markdown punctuation are not rendered by this pipeline.
        missing=[x for x in missing if chr(x).strip() and chr(x) not in ['\ufe0f','\u200d']]
        if missing: raise RuntimeError(name+' lacks '+''.join(map(chr,missing)))
        options=subset.Options();options.layout_features=['*']
        selection=subset.Subsetter(options=options);selection.populate(unicodes=required);selection.subset(f)
        for record in f['name'].names:
            if record.nameID in [1,4,16]:record.string=('Epoch Marketing '+name.title()).encode(record.getEncoding())
            elif record.nameID==6:record.string=('EpochMarketing'+name.title()).encode(record.getEncoding())
        f.save(OUT/'source/fonts'/f'{name}.ttf')
    for name in ['smiley','resource-rounded']:
        shutil.copy2(ROOT/'godot/assets/fonts'/f'{name}-LICENSE.txt',OUT/'licenses'/f'{name}-LICENSE.txt')
    shutil.copy2(ROOT/'godot/assets/audio/Audio-CREDITS.txt',OUT/'licenses/Audio-CREDITS.txt')
    # Approved unit-card art lets the image model see the actual game's troops.
    board=Image.new('RGB',(1536,512),'#102139');d=ImageDraw.Draw(board)
    ids=['U41','U44','U54','U64','U84','U104']
    for i,unit in enumerate(ids):
        art=Image.open(ROOT/'godot/assets/ui/units'/f'{unit}.png').convert('RGBA')
        art.thumbnail((226,440),Image.Resampling.NEAREST)
        x=i*256+(256-art.width)//2;y=(512-art.height)//2
        d.rectangle((i*256+8,8,i*256+247,503),outline='#394761',width=2)
        board.paste(art,(x,y),art)
    board.save(ART/'reference-game-troops.jpg',quality=96)
    base_prompt='''Create premium cohesive hand-crafted pixel-art marketing KEY ART for the existing single-player side-view strategy game Epoch Rush. This is a 16:9 landscape artwork, NOT a screenshot or UI. Reference 1: the approved bearded red-gold guardian logo establishes art finish and palette; do not redraw that portrait, shield crest or any badge anywhere in this generated scenic art. Reference 2: real in-game civilization bases. Reference 3: actual unit card art, especially heavy medieval cavalry, cannons, early tanks, modern tanks and futuristic mechs. Preserve their broad design vocabulary and scale.

Use deliberate square pixel clusters, crisp stepped silhouettes, limited material ramps, premium 16-bit game-key-art detail. No smooth vector illustration, no photorealism, no 3D rendering. Deep navy #071126 and #102139, warm ivory #fff0ce and brass #ffd577, crimson flags and dark burgundy, selective opposing cyan. Dramatic depth, strong focal lighting, believable horizontal ground plane. Opposing bases are much larger than soldiers and face toward the battlefield center. Buildings and troops have distinct shapes and excellent silhouette readability. Selected details of attacks, recoil, impact sparks and smoke suggest satisfying combat. This is a fictional civilization-evolution game, with visually consistent equipment rather than historical reconstruction.

COMPOSITION: Finished 16:9 scenic illustration. Rich scene in lower 60-70 percent, foreground troop action from y=48 to y=88 percent. Leave upper LEFT x=5-63 percent, y=4-29 percent as a fairly quiet ink-navy atmospheric sky, so an exact title can be typeset afterward. Do not draw a panel or placeholder there. Keep top right relatively quiet for a small existing crest that will be overlaid afterward. Keep all important combat units away from crop edges. Larger structures on far left and right frame action, but do not block the upper-left title zone. Show action in the lower portion without obscuring all armies with smoke.

SCENE:
{scene}

STRICT: NO text, NO Chinese characters, NO Latin letters, NO numerals, NO watermark or signature, NO game logo, NO portrait, NO shield crest or floating badge, NO health bar, NO HUD, NO button, NO QR code, NO smartphone mockup, NO contact sheet or grid, NO fake multiplayer mode. Fully opaque PNG. 16:9 aspect exactly.'''
    for name,zh,en,scene in THEMES:
        prompt=base_prompt.replace('{scene}',scene)
        if name=='06-no-logo':
            prompt=prompt.replace('Leave upper LEFT x=5-63 percent, y=4-29 percent as a fairly quiet ink-navy atmospheric sky, so an exact title can be typeset afterward. Do not draw a panel or placeholder there. Keep top right relatively quiet for a small existing crest that will be overlaid afterward.','Do not reserve blank areas for branding; this image is a finished illustration without any title, portrait, badge, crest or logo. No emblems in the sky. A rich atmospheric panorama with coherent composition.')
        (ART/f'{name}.prompt.txt').write_text(prompt+'\n',encoding='utf-8')
    manifest={'date':'2026-10-08','timezone':'Asia/Taipei','game':'纪元急袭','version':'0.7.0','source_exe':str((ROOT/'godot/build/windows/Epoch-Rush-Godot.exe').relative_to(ROOT)),'source_exe_sha256':hashlib.file_digest(open(ROOT/'godot/build/windows/Epoch-Rush-Godot.exe','rb'),'sha256').hexdigest(),'logo_sha256':hashlib.sha256((ART/'selected-logo.png').read_bytes()).hexdigest(),'image_provider':'sub2-image-gen','image_model':'gpt-image-2.5','themes':[{'id':n,'caption':zh,'english':en} for n,zh,en,scene in THEMES],'plan':'docs/epoch-rush/marketing-materials-plan.md'}
    (OUT/'source/production-plan.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Prepared '+str(OUT));print('Six art prompts, exact selected logo, font glyph coverage and game-source identity ready.')

if __name__=='__main__':main()
