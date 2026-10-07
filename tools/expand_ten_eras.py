"""Author the ten-era Godot content and Sub2 production jobs, using native Windows."""
from pathlib import Path
import argparse, copy, hashlib, json, shutil, zipfile

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'godot/assets/data'
OUT = ROOT / 'output/imagegen/ten-eras'
QA = ROOT / 'output/qa/ten-eras'

ERAS = [
    ('石器部落', 'Prehistoric stone-age fur, bone, flint, wooden clubs and hide drums', ['骨盾战士','投石手','燧石矛手','獠牙兽骑','祭火鼓手'], ['volcanic savanna with distant mammoths','misty limestone caves and fern forest','amber river valley and stone circles'], 'meteor', '流星陨火'),
    ('青铜城邦', 'Bronze-age crested bronze helmets, linen, round shields, bows and horse chariots', ['青铜盾卫','城邦弓手','青铜长矛卫','双轮战车','太阳旗卫'], ['sunlit ziggurat beside the Euphrates','Aegean coastal citadel and olive trees','red desert oasis and sandstone temples'], 'fire_arrow', '火矢齐射'),
    ('古典帝国', 'Classical Roman-inspired legion helmets, segmented iron armor, rectangular shields, short swords and ballistae', ['军团盾卫','帝国弩手','重标枪兵','攻城弩车','军团医师'], ['marble aqueduct and cypress valley','Mediterranean harbor and imperial road','pine-covered frontier and stone watchtowers'], 'ballista', '重弩破阵'),
    ('中世纪王国', 'Medieval steel helmets, blue heraldic shields, crossbows, pikemen, armored horses and falcon scouts', ['铁盾军士','城垒弩手','破甲长枪兵','重装骑士','猎隼斥候'], ['green valley below a stone castle','rainy autumn abbey and distant mountains','snowy pine forest and medieval fortress'], 'arrow_rain', '王国箭雨'),
    ('火药列阵', 'Early modern Napoleonic-inspired line infantry, shakos, navy-blue coats, white crossbelts, flintlock muskets, bayonets and brass field cannons', ['线列步兵','燧发枪手','刺刀掷弹兵','野战加农炮','军乐鼓手'], ['golden farmland with a windmill and stone bridge','coastal artillery fort and sailing ships','autumn estate and orderly cannon emplacements'], 'cannonball', '炮列齐鸣'),
    ('工业战壕', 'Late nineteenth-century and WWI-inspired khaki infantry, steel Brodie helmets, bolt-action rifles, canvas webbing, field guns and riveted early tracked tanks', ['堑壕步兵','栓动步枪兵','重机枪手','菱形坦克','战地军医'], ['foggy trench lines and smoking brick factory','muddy battlefield with distant railway viaduct','frosty industrial frontier with observation balloons'], 'artillery', '重炮覆盖'),
    ('二战钢盔', 'WWII-inspired olive drab uniforms, rounded steel helmets, webbing, service rifles, portable anti-tank launchers and medium tanks; no real insignia', ['钢盔步兵','半自动步枪兵','反坦克射手','中型坦克','卫生兵'], ['damaged European village at sunrise','Pacific jungle airstrip and palm trees','snowy town beside an armored rail yard'], 'bomber', '轰炸机群'),
    ('现代机械化', '1991 Gulf War-inspired desert camouflage, kevlar helmets, body armor, assault rifles, anti-tank missiles and angular modern main battle tanks', ['沙漠突击兵','精确射手','导弹反甲兵','主战坦克','战斗医疗兵'], ['desert oilfield with distant smoke plumes','dry canyon and modern forward operating base','dusk coastal city and desert highway'], 'missile', '制导空袭'),
    ('无人战术', 'Near-future compact charcoal tactical exoskeletons, blue optics, drones, coil rifles, electronic warfare gear and tracked unmanned combat vehicles', ['外骨骼卫士','线圈射手','电磁反甲兵','无人突击车','电子工程师'], ['rainy neon megacity outskirts','high-altitude wind farm and unmanned outpost','polar research base and satellite dishes'], 'drone', '无人蜂群'),
    ('轨道文明', 'Orbital science fantasy cream ceramic and warm brass armor, navy-blue panels, cyan phase crystals, compact energy weapons and a two-legged combat mech', ['合金卫士','磁轨射手','相位矛卫','电弧机甲','时序工程师'], ['planetary launchport beneath a ringed planet','lunar canyon with a luminous orbital elevator','alien twilight plains beside a domed colony'], 'orbital', '轨道审判'),
]
XP = [260, 420, 650, 990, 1480, 2180, 3180, 4580, 6520, None]
ROLES = ['front','ranged','anti_armor','heavy','ranged']
BASE_HP = [165,75,115,245,100]
BASE_ATTACK = [14,17,23,30,11]
PERIOD = [1.15,1.4,1.35,1.8,1.7]
COST = [45,60,70,110,80]
REUSE = {1:1,2:2,4:3,10:5}
HERO_DETAILS = {
 'H01': 'male heroic standard-bearer, swept-back brown hair, determined face, blue sash, compact era-appropriate melee weapon or service carbine, attached compact battle flag',
 'H02': 'female eagle-eye ranger, wavy brown hair, blue scarf, keen eyes, light armor and the era-appropriate precise ranged weapon',
 'H03': 'broad older bearded male guardian, blue cape or scarf, heavy era-appropriate armor and a large protective shield or armored ballistic cover',
 'H04': 'male inventive engineer, short brown hair, goggles, tan utility clothes, blue scarf, era-appropriate ranged tool and attached belt equipment',
 'H05': 'female strategist, pale hair tied back, cream clothing with blue trim, era-appropriate ritual token, survey instrument or cyan electronic control ring',
 'H06': 'female supply marshal, braided brown hair, blue ribbon, compact supply satchel and era-appropriate compact ranged weapon',
}
SIGNATURE_NAMES = {
 'H01':['骨槌冲锋','盾矛突进','军团破阵','王国冲锋','军旗突击','刺刀突击','突破推进','战术突入','动力冲锋','相位贯阵'],
 'H02':['燧石连投','青铜连矢','重弩点射','鹰隼齐射','线列齐射','远距狙击','穿甲连射','制导点杀','无人追猎','星轨连射'],
 'H03':['祖灵护佑','青铜誓卫','军团盾阵','城垒誓卫','列阵掩护','堑壕堡垒','钢盔守备','装甲屏障','电子护罩','相位壁垒'],
 'H04':['投石机关','城邦弩机','帝国重弩','折叠弩台','火药炮台','战壕机枪','防御火炮','遥控炮台','无人炮塔','轨道哨机'],
 'H05':['祭仪泥沼','日轮牵制','阵线扰动','风阵拘束','硝烟压制','磁场扰动','电波压制','战术干扰','共振封锁','裂隙场'],
 'H06':['草药补给','城邦军需','军团补给','行军补给','火药补给','战壕补给','前线救护','空投补给','无人补给','时序补给'],
}

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def write(path, value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def baseline():
    QA.mkdir(parents=True,exist_ok=True)
    target=QA/'baseline-0.6.2-sources.zip'
    if not target.exists():
        with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as archive:
            for directory in ['godot/scripts','godot/scenes','godot/assets/data','godot/assets/shaders']:
                for path in (ROOT/directory).rglob('*'):
                    if path.is_file(): archive.write(path,path.relative_to(ROOT))
            for name in ['godot/project.godot','godot/README.md','docs/epoch-rush/README.md']:
                archive.write(ROOT/name,name)
    with zipfile.ZipFile(target,'a',zipfile.ZIP_DEFLATED) as archive:
        existing=set(archive.namelist())
        for directory in ['godot/assets/characters/animations','godot/assets/base','godot/assets/environment/turrets','godot/assets/ui/units']:
            for path in (ROOT/directory).rglob('*.png'):
                relative=path.relative_to(ROOT).as_posix()
                if relative not in existing:archive.write(path,relative)
    original=ROOT/'godot/build/windows/Epoch-Rush-Godot-Windows.zip'
    if original.exists() and not (QA/'baseline-0.6.2-Windows.zip').exists():
        shutil.copy2(original,QA/'baseline-0.6.2-Windows.zip')
    return target

def authored_content():
    baseline()
    with zipfile.ZipFile(QA/'baseline-0.6.2-sources.zip') as source:
        originals={Path(name).stem:json.loads(source.read(name).decode('utf-8')) for name in source.namelist() if name.startswith('godot/assets/data/') and name.endswith('.json')}
        original=lambda name:copy.deepcopy(originals[name])
        old_units={row['id']:row for row in original('units')}
        old_heroes=original('heroes');old_turrets=original('turrets')
        old_missions=original('missions');old_upgrades=original('run-upgrades')
    eras=[];units=[];hero_forms=[];specials=[];turrets=[];upgrades=[]
    for index,(name,look,names,maps,fx,special_name) in enumerate(ERAS):
        number=index+1;era_id=f'A{number}';power=5**index
        money=round(1.28**index,4);knowledge=round(1.45**index,4)
        eras.append({'id':era_id,'name':name,'hpAttackMultiplier':power,'hpMultiplier':power,'attackMultiplier':power,
            'costMultiplier':money,'incomeMultiplier':round(1.28**index,4),'knowledgeMultiplier':knowledge,
            'nextEvolutionKnowledge':XP[index],'baseHp':2400*power,'visual':look,'mapVariants':3,
            'enemyBaseMirrored':number in REUSE,
            'backgrounds':[f'environment/eras/{era_id}-{v}.png' for v in range(1,4)],
            'ambient':(['bat','bird','pterosaur'] if number==1 else ['bird'] if number<5 else ['bird','balloon'] if number==5 else ['biplane','balloon'] if number==6 else ['fighter','bomber'] if number==7 else ['jet','helicopter'] if number==8 else ['drone','jet'] if number==9 else ['shuttle','drone']),
            'eventPool':(['meteor','dinosaur','rockfall'] if number==1 else ['meteor','rockfall','storm'] if number<6 else ['meteor','plane','storm'] if number<9 else ['meteor','drone','debris'])})
        for slot,unit_name in enumerate(names,1):
            row=copy.deepcopy(old_units[f'U1{slot}'])
            row.update(id=f'U{number}{slot}',name=unit_name,eraId=era_id,role=ROLES[slot-1],
                hpBase=BASE_HP[slot-1],attackBase=BASE_ATTACK[slot-1],attackPeriodSec=PERIOD[slot-1],
                costBase=COST[slot-1],trainSec=[1.7,2.1,2.4,3.8,2.7][slot-1],
                armor=[16,0,6,12,4][slot-1],energyResistance=.05,
                bountyGold=round(COST[slot-1]*.38),killKnowledge=[8,10,10,14,10][slot-1],
                visual=look+'; '+unit_name,special={})
            row['range']=[42,220,90,52,190][slot-1]
            row['weaponId']=['W02','W01','W02','W06','W08'][slot-1]
            row['damageType']='pierce' if slot==3 else 'physical'
            row['animationFamily']=['shield','throw','spear','mounted','drum'][slot-1]
            if number>=2 and slot==2:row['weaponId']='W03';row['animationFamily']='bow'
            if number>=5 and slot in [1,2,3,5]:
                row['weaponId']='W04';row['animationFamily']='gun';row['range']=[120,240,230,52,200][slot-1]
            if number>=5 and slot==4:
                row['weaponId']='W05';row['animationFamily']='cannon';row['range']=255
            if number>=9 and slot==4:row['animationFamily']='mech' if number==10 else 'cannon'
            if number>=9 and slot in [2,3]:row['weaponId']='W07' if slot==2 else 'W04'
            if slot==3 and number in [1,2,4]: row['weaponId']='W06'
            if number==3 and slot==3: row.update(weaponId='W03',animationFamily='bow',range=170)
            if number in [7,8] and slot==3: row.update(weaponId='W05',animationFamily='gun')
            if number==10:
                row.update(weaponId=['W02','W07','W06','W07','W07'][slot-1],animationFamily=['shield','gun','spear','mech','mech'][slot-1],range=[42,240,90,255,200][slot-1])
            if slot==4:row['special']={'firstContactBonus':.2,'minRunDistance':100}
            if slot==5:
                row['special']={'auraRadius':160,'supportPulseSec':1.5,'supportTargetCap':3}
                if number in [3,6,7,8]: row['special']['auraHealHpRatio']=.012
                elif number in [2,10]:row['special']['auraShieldRatio']=.015
                elif number==9:row['special']['auraHealHpRatio']=.009
                elif number==4:row['special']={'markedShotBonus':.12}
                else:row['special']['auraAttackSpeedBonus']=.08
            row['material']='metal' if number>=6 or slot==4 and number>=4 else 'wood' if number==2 and slot in [1,4,5] else 'flesh'
            units.append(row)
        effects=['blast','pierce','pierce','pierce','blast','blast','blast','blast','energy','energy']
        specials.append({'id':era_id,'name':special_name,'cost':round(55*knowledge),'cooldown':34.0,
            'damage':65.0,'radius':[140,155,170,180,195,210,220,230,235,240][index],
            'pulses':[2,3,2,4,3,3,3,2,4,3][index],'damageType':effects[index],
            'fx':fx,'warningSec':1.15,'pulseIntervalSec':.24,'sfx':['meteor_impact','arrow_rain','cannon_hit','arrow_rain','cannon_hit','cannon_hit','airstrike','airstrike','energy_hit','orbital_impact'][index],
            'carrier':fx,'projectileCount':6 if number in [2,4,9] else 3})
        for hero in old_heroes:
            hid=hero['id'];weapon=hero.get('weaponId','W02')
            if hid in ['H02','H04','H06']:
                weapon='W01' if number==1 else 'W03' if number<5 else 'W04' if number<9 else 'W07'
            if hid=='H01' and number>=5:weapon='W04'
            if hid=='H01' and number==10:weapon='W02'
            if hid=='H03' and number>=8:weapon='W07' if number==10 else 'W04'
            hero_forms.append({'id':f'{hid}-{era_id}','heroId':hid,'eraId':era_id,
                'name':hero['name'],'title':name+' · '+hero['title'],'visual':look+'; '+HERO_DETAILS[hid],
                'signatureName':SIGNATURE_NAMES[hid][index], 'weaponId':weapon,
                'range':52.0 if hid=='H01' and number==10 else 185.0 if number>=8 and hid=='H03' or number>=5 and hid in ['H01','H04','H06'] else float(hero['range']),
                'hpBase':hero['hpBase'],'attackBase':hero['attackBase'],'armor':hero['armor'],
                'moveSpeed':hero['moveSpeed'],'attackPeriodSec':hero['attackPeriodSec'],
                'damageType':('energy' if number==10 else 'physical') if hid=='H03' and number>=8 else hero['damageType'],'skillVariant':{
                    'chargeRange':150+index*10,'chargeTargets':2+index//3,'knockback':30+index*4,
                    'pulses':2+index//3,'pierceTargets':1+index//4,'projectileWeapon':weapon,
                    'shieldReduction':min(.22,index*.024),'fieldDuration':3.0+index*.25,
                    'fieldSlow':.18+index*.018,'fieldRadius':85+index*4,
                    'supplyGold':round(35*money),'supplyCommand':min(18,5+index),
                    'summonWeapon':'W01' if number==1 else 'W03' if number<5 else 'W04' if number<9 else 'W07',
                    'summonRange':200+index*10,'summonDuration':14.0+index*.5}})
        for slot in [1,2]:
            row=copy.deepcopy(old_turrets[slot-1]);row.update(id=f'TR{number}{slot}',eraId=era_id,name=(name+'轻炮塔' if slot==1 else name+'重炮塔'),attackBase=18 if slot==1 else 31,weaponId='W01' if number==1 else 'W03' if number<5 else 'W05' if slot==2 else 'W04')
            turrets.append(row)
        if number>=2:
            for choice,template in enumerate(old_upgrades[:3],1):
                row=copy.deepcopy(template);row.update(id=f'R{number}{choice}',eraId=era_id,choiceGroup='evolution_'+era_id,name=name+' · '+['军团锋刃','坚守阵线','战术补给'][choice-1])
                upgrades.append(row)
    missions=[]
    for i in range(20):
        row=copy.deepcopy(old_missions[min(i,len(old_missions)-1)])
        era=i//2+1;row.update(id=f'M{i+1:02}',name=ERAS[era-1][0]+(' · 军团推进' if i%2==0 else ' · 阵线突破'),
            startingEraId=f'A{era}',maximumEraId=f'A{min(10,era+1)}',playerStartingGold=240,enemyStartingGold=240,
            boss=i%2==1,heroUnlockIds=({'M03':['H02'],'M07':['H04'],'M11':['H06'],'M15':['H05']}.get(f'M{i+1:02}',[])),
            teaching='占位接敌、研究与时代奇袭；医疗和护盾有共享恢复上限。')
        row['playerStartingGold']=row['enemyStartingGold']=round(240*1.28**(era-1))
        row['chapter']=era
        row['bossParameters']={};row['reinforcements']={'periodSec':36,'waves':40,'deploySec':28}
        missions.append(row)
    rules=original('rules');rules['designVersion']='0.7.0';rules['status']='ten_eras_rebuild'
    rules['support']={'pulseSec':1.5,'maximumTargets':3,'combatRecoveryRatioPerSec':.02,
        'outOfCombatRecoveryRatioPerSec':.05,'passiveShieldCapRatio':.12,'totalShieldCapRatio':.2,
        'combatSustainFractionOfPressure':.35,'pressureWindowSec':3.0,'shieldRegenHpRatioPerSec':.01}
    rules['caps']['shieldHpRatio']=.2
    rules['randomEvents']={'enabled':True,'firstMinSec':38,'firstMaxSec':58,'intervalMinSec':48,'intervalMaxSec':82,
        'warningSec':2.1,'maximumDamageHpRatioPerEvent':.1,'maximumEvents':14,'canDamageBase':False}
    rules['overtime'].update(firstSec=1200,secondSec=1440,burnStartsSec=1800)
    for name,rows in [('eras',eras),('units',units),('hero-evolutions',hero_forms),('era-specials',specials),('turrets',turrets),('run-upgrades',upgrades),('missions',missions),('rules',rules)]:write(DATA/(name+'.json'),rows)
    snapshot=ROOT/'docs/epoch-rush/data-v0.7'
    for path in DATA.glob('*.json'):
        if path.name!='animations.json':shutil.copy2(path,snapshot/path.name) if snapshot.exists() else (snapshot.mkdir(parents=True,exist_ok=True),shutil.copy2(path,snapshot/path.name))
    return eras,units,hero_forms

def production_jobs():
    OUT.mkdir(parents=True,exist_ok=True);(OUT/'prompts').mkdir(exist_ok=True);(OUT/'raw').mkdir(exist_ok=True)
    jobs=[]
    style='Production raster pixel-art for a polished mobile 2D side-view strategy game. Crisp pixel clusters, limited painterly pixel palette, navy-blue allied accents, warm cream and brass details. No text, no letters, no watermarks, no HUD. '
    def job(name,kind,prompt,size='1024x1024',reference=None,dependencies=None,**metadata):
        prompt_path=OUT/'prompts'/f'{name}.txt';prompt_path.write_text(prompt,encoding='utf-8')
        jobs.append(dict(name=name,kind=kind,prompt=prompt_path.relative_to(ROOT).as_posix(),size=size,
            reference=reference,dependencies=dependencies or [],model='gpt-image-2.5',**metadata))
    for index,(name,look,names,maps,fx,special) in enumerate(ERAS,1):
        aid=f'A{index}'
        job('maps-'+aid,'maps',style+'ONE image containing EXACTLY THREE separate horizontal panoramic background strips stacked vertically, equal heights, edge to edge, with no separating labels. Each strip is a complete different side-view battlefield in '+look+'. Top strip: '+maps[0]+'. Middle strip: '+maps[1]+'. Bottom strip: '+maps[2]+'. Each panorama has sky and distant scenery in the upper 75 percent and an uninterrupted level, unobstructed walkable horizontal ground near 82 percent. Both ends are open empty spaces for large bases rendered separately. No characters, no soldiers, no animals, no foreground structures obscuring the battle line. Readable atmospheric depth, restrained detail, different colors and landmarks in each strip. Never merge the three locations.',size='1536x1024',era=aid)
        hero_descriptions='; '.join(f'cell {i}: {detail}' for i,detail in enumerate(HERO_DETAILS.values(),1))
        job('hero-seeds-'+aid,'hero_seeds',style+'Exactly six isolated full-body characters, THREE columns by TWO rows, one centered figure per cell, facing RIGHT. Solid exact magenta #ff00ff background and clear 30px margin between figures. All six wear '+look+'. '+hero_descriptions+'. All body parts and compact attached weapons contained inside their own cells. Keep human faces and personal identities distinctive. No shadows, scenery, cell borders or detached effects.',era=aid)
        for hid,detail in HERO_DETAILS.items():
            visual=look+'; '+detail
            anim_prompt=style+'Use the attached approved era character seed as the identity reference. Keep exactly this costume, face, gear, proportions and blue faction colors. Create ONE WHOLE ANIMATION SHEET, precisely SIX columns by FIVE rows, exactly THIRTY complete isolated poses of the same '+visual+'. All face RIGHT. Row 1 six idle poses; row 2 six successive WALK frames, visible alternating steps; row 3 anticipation, windup, distinct attack RELEASE on frame 3, recoil and recovery; row 4 six HIT reactions; row 5 six DEATH poses ending on the floor. Always retain all limbs, equipment and weapon. Shorten weapons to fit their cells. Use a flat exact #ff00ff magenta matte, no ground shadows, no scenery, no grid lines, no effects. Leave at least 18px empty margin on each cell and all canvas edges. All frames share one scale and stable floor anchor. Do not merge adjacent figures.'
            job(f'{hid}-{aid}','animation',anim_prompt,reference=f'output/imagegen/ten-eras/seeds/{hid}-{aid}.png',dependencies=['hero-seeds-'+aid],actor=f'{hid}-{aid}',era=aid,heroId=hid)
        if index not in REUSE:
            role_desc=['frontline protective infantry','ranged support shooter','anti-armor specialist','heavy mounted, artillery or armored vehicle','distinctive support medic or engineer with green medical emblem if a medic']
            job('unit-seeds-'+aid,'unit_seeds',style+'Exactly FIVE isolated full-body military units, THREE columns by TWO rows with bottom-right cell EMPTY. Magenta #ff00ff matte. One complete figure or vehicle centered in each occupied cell, facing RIGHT. Era: '+look+'. Cells in row-major order: '+'; '.join(f'{i+1}: {names[i]}, {role_desc[i]}' for i in range(5))+'. Large clear margins, compact weapons, no scenery, text, shadows or grid. For a tank show the full vehicle without detached crew. Make the five silhouettes distinct.',era=aid)
            for slot in range(1,6):
                unit_id=f'U{index}{slot}'
                job(unit_id,'animation',style+'Use the attached era seed as the identity reference. ONE full animation sheet of exactly THIRTY complete isolated silhouettes in SIX columns by FIVE rows. Character: '+look+'; '+names[slot-1]+'; '+role_desc[slot-1]+'. Always facing RIGHT, exact same costume, proportions, colors, weapon and vehicle across all frames. Row 1 idle six frames; row 2 WALK six sequential frames (mounted gait or rolling tracks for a vehicle); row 3 attack preparation, windup, clear RELEASE on third frame, recoil and recovery; row 4 hurt six frames; row 5 death six frames. Very compact weapons; full body/vehicle fully inside every cell, 18px magenta clearance at every edge. Exact flat #ff00ff background. No grid, scenery, shadows, text or detached particles. Visible action changes, not identical pasted figures.',reference=f'output/imagegen/ten-eras/seeds/{unit_id}.png',dependencies=['unit-seeds-'+aid],actor=unit_id,era=aid)
            job('base-'+aid,'base',style+'ONE large isolated fortified military base appropriate to '+look+'. Side-view building facing right, with layered silhouette, clear entrance and room for roof turrets, broad footprint, no soldiers. Building style must reflect the era rather than a generic castle. The complete base fits inside the image with clear margins. Exact magenta #ff00ff matte, no external ground, text or cast shadow.',era=aid)
        job('fx-'+aid,'fx',style+'Exactly SIX isolated game VFX assets in THREE columns by TWO rows, one per cell on flat #ff00ff magenta matte. Era '+look+'. Ability '+special+'. Cells: 1 the '+fx+' carrier or launcher silhouette; 2 a single '+fx+' projectile aimed diagonally downward-right; 3 bright era-appropriate impact explosion or energy burst; 4 expanding shock ring; 5 fragment and spark cluster; 6 dense smoke or energy plume. Clear cell margins, all elements complete and separated, no text, no actual magenta in the effects. Expressive chunky bright pixel clusters and controlled glow, avoid photographic smoke.',era=aid)
    job('ambient-pack','ambient',style+'Exactly TWELVE isolated tiny sky sprites in FOUR columns by THREE rows on #ff00ff matte. Facing RIGHT. Row-major: bat, bird, prehistoric pterosaur, observation balloon, biplane, WWII propeller fighter, WWII bomber, modern fighter jet, helicopter, near-future drone, orbital shuttle, small satellite debris. One complete sprite per cell, no effects, no scenery, text or shadows. Distinct historically recognizable silhouettes and strong readability at 30-60 pixels.',names=['bat','bird','pterosaur','balloon','biplane','fighter','bomber','jet','helicopter','drone','shuttle','debris'])
    job('event-pack','events',style+'Exactly SIX isolated falling event sprites in THREE columns by TWO rows, #ff00ff matte, clean margins: fiery meteor chunk, compact damaged propeller airplane banking down, small whimsical green dinosaur falling with surprised expression, rolling boulder, broken near-future drone, orbital satellite debris. No gore, no text, no scenery. Game-size readable pixel shapes, dramatic but playful.',names=['meteor','plane','dinosaur','rockfall','drone','debris'])
    job('turret-pack','turrets',style+'Exactly TWENTY isolated small base turret mounts in FOUR columns by FIVE rows on #ff00ff matte. Row-major order two turrets per era, light then heavy: stone sling catapult and heavy stone thrower; bronze bow turret and bronze catapult; Roman scorpio and ballista; medieval crossbow turret and trebuchet; flintlock swivel gun and brass cannon; WWI machine gun and field howitzer; WWII machine gun and anti-tank gun; modern autocannon and missile turret; unmanned coil gun and drone-defense cannon; orbital energy gun and plasma cannon. Complete self-contained pedestal and weapon, no operators, no scenery, grid lines or text. Every muzzle faces RIGHT, compact enough to remain wholly inside its cell.')
    write(OUT/'jobs.json',{'version':'0.7.0','model':'gpt-image-2.5','jobs':jobs})
    print(json.dumps({'jobs':len(jobs),'maps':30,'units':50,'heroForms':60,'newAnimations':90},ensure_ascii=False))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--prompts-only',action='store_true');args=parser.parse_args()
    if not args.prompts_only:authored_content()
    production_jobs()
