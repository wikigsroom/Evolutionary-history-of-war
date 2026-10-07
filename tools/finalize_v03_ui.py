from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'src/ui/screens-v03.ts'
s=p.read_text(encoding='utf-8')
s=s.replace('<time class="battle-clock" data-text="time"></time>','<div class="battle-time"><time class="battle-clock" data-text="time"></time><small data-text="wave"></small></div>')
controls='<button class="icon-button" data-action="trainingMenu" aria-label="管理训练队列">${uiIcon(\'people\')}</button><button class="icon-button" data-action="unitHelp" aria-label="查看当前兵种说明">${uiIcon(\'info\')}</button>'
if 'data-action="trainingMenu"' not in s:s=s.replace('<div class="map-controls" hidden>',controls+'<div class="map-controls" hidden>')
s=s.replace('<button class="tiny-button" data-action="unitHelp" aria-label="查看当前兵种说明">${uiIcon(\'info\')}</button>','')
s=s.replace('重型克制步兵','重型克制步兵，攻城伤害×2.6')
p.write_text(s,encoding='utf-8')
p=ROOT/'src/ui/app.ts';s=p.read_text(encoding='utf-8')
s=s.replace("['pause','fort','research','unitHelp']","['pause','fort','research','unitHelp','training']")
s=s.replace('点队列格取消训练，未开始全额退款，训练中退75%。','点人数图标管理队列，未开始全额退款，训练中退75%。')
s=s.replace('1–4 训练 · Q/W/E 技能 · Z/X/C 站位 · R 进化 · Esc 暂停或取消瞄准。','1–4 训练 · R 进化 · F 时代大招 · T 强化 · B 炮塔 · I 兵种说明 · Esc 暂停。开启指挥官后，Q/W/E 技能，Z/X/C 站位。')
s=s.replace('<p>${m.teaching}<br>','<p>${m.teaching}<br>敌军有 ${m.reinforcements?.waves ?? 4} 波增援，每轮间隔 ${m.reinforcements?.periodSec ?? 56} 秒；利用集结空档反推。<br>')
s=s.replace("heavy:'重型克制步兵'","heavy:'重型克制步兵，攻城伤害 ×2.6'")
s=s.replace('一场对战 · 五次文明登场','一场对战 · 五个时代')
p.write_text(s,encoding='utf-8')
print('Finished v0.3 toolbar, queue management and reinforcement explanations.')
