"""Index and package the verified marketing masters without raw AVI captures."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

from PIL import Image
from graphics import ROOT, OUT, ART


def sha(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    qa = read_json(OUT / 'source/quality-report.json')
    visual = read_json(OUT / 'source/visual-review.json')
    if qa['status'] != 'passed' or visual['status'] != 'passed':
        raise RuntimeError('Verified images, movies and visual review are required before packaging')
    for movie in qa['movies']:
        if movie['sha256'] != sha(OUT / movie['file']):
            raise RuntimeError('Movie changed after verification')
    qa['visual_review'] = visual
    write_json(OUT / 'source/quality-report.json', qa)
    main_stills = qa['final_still_images']
    for dirname in ['original-art', 'prompts', 'audio']:
        (OUT / 'source' / dirname).mkdir(exist_ok=True)
    for document in ['marketing-materials-plan.md', 'branding-materials-update.md']:
        shutil.copy2(ROOT / 'docs/epoch-rush' / document, OUT / 'source' / document)
    for theme in read_json(OUT / 'source/production-plan.json')['themes']:
        stem = theme['id']
        shutil.copy2(ART / (stem + '.png'), OUT / 'source/original-art' / (stem + '.png'))
        shutil.copy2(ART / (stem + '.prompt.txt'), OUT / 'source/prompts' / (stem + '.prompt.txt'))
    shutil.copy2(ROOT / 'output/imagegen/brand-kit/2026-10-08-pixel-crest/poster-art.png',
                 OUT / 'source/original-art/portrait-background.png')
    shutil.copy2(ROOT / 'godot/assets/audio/music/age2.ogg', OUT / 'source/audio/age2.ogg')
    homepage = read_json(OUT / 'copy/homepage-recommendation.json')
    rows = [
        ('游戏图标', '1024×1024 / 512×512 / 不透明 PNG，附 Windows ICO', 'brand/game-icon-opaque-1024.png'),
        ('游戏 LOGO', '2048×512 / 1024×256 / 透明 PNG，仅游戏名', 'brand/game-logo-transparent-2048x512.png'),
        ('游戏 Banner', '2304×768 / 3:1 / 仅游戏名 / PNG、JPG', 'banners/game-banner-2304x768.png'),
        ('游戏海报', '1536×2304 / 2:3 / 仅游戏名 / PNG、JPG', 'posters/game-poster-1536x2304.png'),
        ('游戏简介、开发者的话', '完整中文文案 / Markdown、TXT', 'copy/game-introduction-and-developer-message.md'),
        ('游戏截图', '12 张 / 1920×1080 / PNG', 'screenshots/'),
        ('游戏实机录屏', '120.000 秒 / 1280×720 / 30 fps / MP4', 'videos/gameplay-120s.mp4'),
        ('宣传片', '45.000 秒 / 1920×1080 / 30 fps / MP4', 'videos/trailer-45s-1920x1080.mp4'),
        ('宣传图', '5 张 / 1920×1080 / 16:9 / PNG、JPG', 'promotional/'),
        ('首页推荐语', '主标题、推荐段落、短版、特色条 / TXT、JSON', 'copy/homepage-recommendation.txt'),
        ('横版封面', '1920×1080 / 16:9 / PNG、JPG', 'covers/horizontal-cover-1920x1080.png'),
        ('竖版封面', '1080×1620 / 2:3 / PNG、JPG', 'covers/vertical-cover-1080x1620.png'),
        ('游戏库背景壁纸', '6144×1984 超宽版，附 6144×3456 完整版 / 无 Logo、无文字 / PNG、JPG', 'wallpapers/library-background-no-logo-6144x1984.png'),
        ('无 LOGO 宣传图', '1920×1080 / 无文字、品牌徽章或界面 / PNG、JPG', 'promotional/no-logo-key-art-1920x1080.png'),
    ]
    table = '\n'.join(f'| {name} | {spec} | [{file}]({file}) |' for name, spec, file in rows)
    screenshot_names = ['首页营地', '主将整军', '石器部落', '青铜城邦', '古典帝国',
                        '中世纪王国', '火药列阵', '工业战壕', '二战钢盔',
                        '现代机械化', '无人战术', '轨道文明']
    shots = sorted((OUT / 'screenshots').glob('*.png'))
    shot_table = '\n'.join(f'| {i + 1:02d} | {name} | [{file.name}](screenshots/{file.name}) |'
                           for i, (name, file) in enumerate(zip(screenshot_names, shots)))
    intro = (OUT / 'copy/game-introduction.txt').read_text(encoding='utf-8')
    developer = (OUT / 'copy/developer-message.txt').read_text(encoding='utf-8')
    cjk = lambda text: sum('\u4e00' <= c <= '\u9fff' for c in text)
    readme = f'''# 《纪元急袭》宣传素材包

制作日期：2026-10-08。内容以 Windows / Android Godot 0.7.0 为准。
中文名称为《纪元急袭》，英文名称为 Epoch Rush: Pixel Command。游戏图标沿用已选 H03 红金骑士；正式 LOGO 是透明底的游戏名纯文字图。

## 交付目录

| 内容 | 规格 | 文件或目录 |
| --- | --- | --- |
{table}

宣传美术提供无损 PNG 和高质量 JPG 两种文件。截图共 12 张；另有 {main_stills - 12} 张图标、LOGO、宣传图、封面及壁纸主成图；其他图标与 LOGO 尺寸、ICO 和 JPG 格式另附。

游戏图标为完全不透明的 RGB PNG；游戏 LOGO 为真正透明的 RGBA PNG，仅含“纪元急袭”。横竖封面、五张宣传图、Banner、海报和宣传片封面均只叠加“纪元急袭”，不含英文副标题、宣传语、平台字样或功能数量。下文独立推荐文案不叠加到这些图片中。

游戏库壁纸两版均超过 3840×1240，无外加 Logo、标题、说明文字或水印。[完整 16:9 版](wallpapers/library-background-no-logo-6144x3456.png)保留天空与完整城堡轮廓，[超分细节对比](previews/wallpaper-super-resolution-comparison.jpg)单独展示处理前后效果。

## 首页推荐语

**{homepage['headline']}**

{homepage['recommendation']}

短版：{homepage['short']}

特色条：{homepage['feature_strip']}

完整介绍与开发者的话分别约 {cjk(intro)}、{cjk(developer)} 个汉字。全文另存为独立 TXT，可直接粘贴到游戏详情页。

## 实机截图清单

| 编号 | 画面内容 | 原图 |
| --- | --- | --- |
{shot_table}

![首页、整军和前四时代](previews/screenshots-01-06.jpg)

![后六个时代](previews/screenshots-07-12.jpg)

## 宣传美术总览

五张宣传图依次突出时代进化、盾墙与重骑、工业火炮、现代装甲、轨道机甲。

![宣传图、封面和壁纸](previews/promotional-covers-overview.jpg)

## 视频内容与来源

120 秒视频为连续原生游戏渲染，包含约 7 秒首页、整军、图鉴操作，以及约 113 秒中世纪对战。全程保留 HUD、原生音乐和音效；以当前发布 EXE 内嵌内容运行。自动操作按照正常研究、招募、训练、技能和道具规则执行。

45 秒宣传片由品牌开场、六段实机动作和品牌结尾组成。片段覆盖石器、中世纪、工业、现代、无人战术和轨道时代；包含接敌、炮击、坦克与机甲、技能和轨道打击。它剪辑自不同起始时代的对战。各交战片段保持正常模拟速度，裁取战场后以最近邻缩放导出 1080p。制作日志记录了每段原始时间范围和转场。

![120 秒录屏选帧](previews/gameplay-contact.jpg)

![45 秒宣传片选帧](previews/trailer-contact.jpg)

两个成片均为 H.264 / AAC，30 fps、48 kHz 双声道。完整解码检查通过；帧数分别为 3600 和 1350，音频无削波，逐秒抽样画面均有变化。

## 美术、字体与音乐

宣传背景通过 sub2-image-gen / gpt-image-2.5 生成，参考游戏中的营寨、兵种及已选 Logo。各横向原图为模型返回的 1672×941；竖向背景为 1024×1536。宣传图和封面通过保持比例裁切及最近邻缩放得到。

游戏库壁纸单独使用未叠加文字与 Logo 的 01-evolution 原画，经 Real-ESRGAN 插画模型进行 4 倍神经网络超分，得到 6688×3764 原生超分母图，再按比例裁切、Lanczos 缩小导出 6144×1984 与 6144×3456 两版。超宽版保留交战单位，完整版保留全部场景。推理使用 Windows 原生 ncnn Vulkan / NVIDIA RTX 3060；记录、校验值及超分母图保存于 source/upscale。模型和运行程序许可随 licenses 交付。

人物徽章使用已选骑士原图合成。游戏图标填满不透明底色；正式游戏 LOGO 仅为透明背景的“纪元急袭”四字文字图。无 Logo 版本不叠加标题、文字或人物徽章，场景内阵营旗帜与纹章为美术内容。

标题使用得意黑，说明使用资源圆体；OFL 许可和改名后的所需字形子集附在 licenses 与 source/fonts。宣传片配乐沿用游戏已有的 age2.ogg，配合原生打击音效混音；公开素材来源与 CC0 声明见 licenses/Audio-CREDITS.txt。

## 文件校验与制作记录

MANIFEST.json 包含文件大小、SHA-256、图片规格及交付分类。source/quality-report.json 保存视频完整解码、帧数、音频峰值及录制来源校验；source/visual-review.json 保存画面复查记录。source/brand-assets.json 保存图标不透明、LOGO 透明与文字范围的检查。source/prompts 保留六份图片提示词，source/selected-logo.png 为骑士来源参考图，正式上传 LOGO 使用 brand/game-logo-transparent-2048x512.png。

本机未压缩录制源保存在 source/native 下；下载包只附录制报告、操作记录及成片，不附体积较大的原始 AVI。源码仓库中的 tools/marketing 与 godot/qa/marketing_*.gd 保留制作流程。所有操作使用 Windows 原生进程。
'''
    (OUT / 'README.md').write_text(readme, encoding='utf-8')
    files = [OUT / 'README.md']
    for dirname in ['brand', 'banners', 'posters', 'screenshots', 'videos', 'promotional', 'covers', 'wallpapers', 'copy', 'previews', 'licenses']:
        files += sorted(f for f in (OUT / dirname).rglob('*') if f.is_file())
    files += [OUT / 'source' / file for file in
              ['production-plan.json', 'image-production.json', 'quality-report.json',
               'visual-review.json', 'brand-assets.json', 'branding-compliance.json', 'selected-logo.png', 'marketing-materials-plan.md', 'branding-materials-update.md',
               'video/trailer-edit.json', 'video/gameplay-master.json', 'video/trailer-filter.ffgraph']]
    files += [OUT / 'source/upscale' / file for file in
              ['native-receipt.json', 'wallpaper-production.json', 'native-inference.log',
               'library-unlettered-real-esrgan-4x-6688x3764.png']]
    for dirname in ['original-art', 'prompts', 'fonts', 'audio']:
        files += sorted(f for f in (OUT / 'source' / dirname).rglob('*') if f.is_file())
    for mode in ['screenshots', 'recording', 'showcase']:
        files += sorted((OUT / 'source/native' / mode).glob('*.json'))
    files = sorted(set(files))
    removed = ''.join(chr(n) for n in [20687, 32032, 25351, 25381, 21488])
    for file in files:
        if file.suffix in ['.md', '.txt', '.json', '.ffgraph']:
            if removed in file.read_text(encoding='utf-8'):
                raise RuntimeError('Removed subtitle remains in ' + file.name)
    manifest = {'game': '纪元急袭', 'version': '0.7.0', 'date': '2026-10-08',
                'requirements': [{'name': n, 'specification': s, 'path': f, 'status': 'delivered'}
                                 for n, s, f in rows],
                'main_still_images': main_stills, 'movies': 2, 'quality': 'source/quality-report.json',
                'files': []}
    for file in files:
        item = {'file': file.relative_to(OUT).as_posix(), 'bytes': file.stat().st_size, 'sha256': sha(file)}
        if file.suffix in ['.png', '.jpg']:
            with Image.open(file) as image:
                item['dimensions'] = list(image.size)
        manifest['files'].append(item)
    write_json(OUT / 'MANIFEST.json', manifest)
    files.append(OUT / 'MANIFEST.json')
    archive = OUT / 'Epoch-Rush-Marketing-Kit-2026-10-08.zip'
    with zipfile.ZipFile(archive, 'w', allowZip64=True) as handle:
        for file in files:
            mode = zipfile.ZIP_STORED if file.suffix in ['.mp4', '.png', '.jpg', '.ttf', '.ogg'] else zipfile.ZIP_DEFLATED
            handle.write(file, 'Epoch-Rush-Marketing-Kit/' + file.relative_to(OUT).as_posix(), compress_type=mode)
    with zipfile.ZipFile(archive) as handle:
        if handle.testzip() is not None:
            raise RuntimeError('ZIP CRC verification failed')
        for item in manifest['files']:
            packed = handle.read('Epoch-Rush-Marketing-Kit/' + item['file'])
            if hashlib.sha256(packed).hexdigest() != item['sha256']:
                raise RuntimeError('ZIP content differs from final master')
    archive_sha = sha(archive)
    archive.with_suffix('.zip.sha256').write_text(archive_sha + '  ' + archive.name + '\n', encoding='utf-8')
    report = {'archive': archive.name, 'files': len(files), 'bytes': archive.stat().st_size,
              'sha256': archive_sha, 'crc_verification': 'passed', 'content_hash_verification': 'passed',
              'requirements_completed': len(rows), 'main_still_images': main_stills, 'movies': 2}
    write_json(OUT / 'package-report.json', report)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
