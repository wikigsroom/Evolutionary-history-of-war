import { Battle } from '../core/battle';
import { builds,catalog,eras,heroes,missions,relics,skills,specializations,talents,units,upgrades,rules } from '../content/catalog';
import { chapters,missionLines } from '../content/story';
import { worldX,type Action,type BattleState,type Loadout,type MatchConfig } from '../core/types';
import { fitLoadout,loadoutErrors } from '../core/loadout';
import { availability,craft,loadoutFor,missionAvailable,type Profile,type RewardReceipt,validateProfile } from '../core/profile';
import { ProfileStore } from '../services/profile-store';
import { WebStorage } from '../services/storage';
import { validateSnapshot } from '../services/save-validation';
import { assetPath } from '../presentation/assets';
import { GameAudio } from '../presentation/audio';
import {BattleCamera,type CameraAnchor} from '../presentation/battle-camera';
import {MatchSaver} from '../services/match-saver';
import {menuMarkup,battleHud} from './screens';
import {uiIcon} from './icons';
import {exportFile,haptic,watchLifecycle} from '../services/platform';
import {ageSpecials} from '../core/age-specials';
import {activeItems,activeItemIds,type ActiveItemId} from '../core/active-items';
import {researches,researchLevel,researchCost} from '../core/research';
import {reinforcementWindow} from '../core/campaign-waves';
import {advanceSimulation} from '../presentation/simulation-clock';

const html=(text: string) => text.replace(/[&<>"']/g,char => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[char]!));
const clock=(ticks: number) => `${Math.floor(ticks/1800).toString().padStart(2,'0')}:${Math.floor(ticks/30)%60<10 ? '0' : ''}${Math.floor(ticks/30)%60}`;
const icon=(key: string,label: string) => assetPath(key) ? `<img src="${assetPath(key)}" alt="${html(label)}" draggable="false">` : `<span class="glyph">${html(label.slice(0,1))}</span>`;

export class GameApp {
  readonly camera=new BattleCamera();
  current: Battle | null=null;
  selectedSkill: string | null=null;
  reducedMotion=matchMedia('(prefers-reduced-motion: reduce)').matches;
  private root=document.querySelector<HTMLElement>('#interface')!;
  private storage=new WebStorage();
  private matchSaver=new MatchSaver(this.storage);
  private profiles=new ProfileStore(this.storage);
  private profile!:Profile;
  private draft:Loadout | null=null;
  private editingLoadout=false;
  private pendingNavigation:{action:string;value?:string} | null=null;
  private skillSlot=0;
  private mode:MatchConfig['mode']='standard';
  private heroEnabled=false;
  private missionId='M01';
  private starting=false;
  private assetsReady=false;
  private assetError=false;
  private importCandidate:Profile | null=null;
  private audio=new GameAudio();
  private selectedHero='H01';
  private difficulty='D02';
  private saved: BattleState | null=null;
  private accumulator=0;
  private page='menu';
  private uiEra='';
  private queueKey='';
  private hudTick=-1;
  private ended=false;
  private toastTimer=0;
  private modalFocus:HTMLElement | null=null;
  private lastSavedTick=0;
  private mapTick=-1;

  async init() {
    this.root.innerHTML='<section id="page"></section><section id="hud" hidden></section><section id="overlay" hidden></section><div id="toast" role="status" aria-live="polite"></div>';
    this.root.addEventListener('click',event => {
      const button=(event.target as HTMLElement).closest<HTMLElement>('[data-action]');
      if (!button || button.hasAttribute('disabled')) return;
      void this.handle(button.dataset.action!,button.dataset.value).catch(error=>this.toast(error instanceof Error ? error.message : '操作未保存，请重试'));
    });
    let mapPointer:number | null=null;
    const moveMap=(event:PointerEvent)=>{const map=document.getElementById('battle-minimap');if(!map || !this.canNavigate())return;const rect=map.getBoundingClientRect();this.camera.tracking='free';this.camera.focus((event.clientX-rect.left)/rect.width*1600);this.paintCamera();};
    this.root.addEventListener('pointerdown',event=>{const map=(event.target as HTMLElement).closest<HTMLElement>('#battle-minimap');if(map && this.canNavigate()){event.preventDefault();mapPointer=event.pointerId;map.setPointerCapture(event.pointerId);moveMap(event);}});
    this.root.addEventListener('pointermove',event=>{if(mapPointer===event.pointerId)moveMap(event);});
    this.root.addEventListener('pointerup',()=>{mapPointer=null;});
    this.root.addEventListener('pointercancel',()=>{mapPointer=null;});
    document.addEventListener('keydown',event => this.keyboard(event));
    document.addEventListener('visibilitychange',() => { if (document.hidden) this.pause(); });
    window.addEventListener('blur',() => this.pause());
    window.addEventListener('pagehide',() => { if (this.current) void this.persist(); });
    window.addEventListener('contextmenu',event => { if (this.selectedSkill) { event.preventDefault(); this.selectedSkill=null; this.paintHud(true); } });
    void watchLifecycle(()=>this.pause(),()=>{if(this.page==='battle')this.pause();else if(this.page==='menu')this.menu();});
    try { this.profile=await this.profiles.load();this.audio.setMuted(this.profile.settings.muted);this.reducedMotion=this.profile.settings.reducedMotion || this.reducedMotion;document.body.classList.toggle('reduce-motion',this.reducedMotion); }
    catch(error){document.querySelector<HTMLElement>('#page')!.innerHTML=`<div class="book-page"><h1>档案需要修复</h1><p>${html(error instanceof Error ? error.message : '本地档案读取失败')}</p><button class="primary" data-action="restoreBackup">恢复上一份完整备份</button><button class="text-button" data-action="reload">重新读取</button></div>`;return;}
    try { const saved=await this.storage.read<BattleState>('match'); if (saved && saved.config.profileId===this.profile.profileId) this.saved=validateSnapshot(saved); }
    catch (error) { this.toast(error instanceof Error ? error.message : '读取对局失败'); }
    this.menu();
    this.finishRestored();
  }

  private menu() {
    this.editingLoadout=false;
    void this.audio.setMusic('music.menu');this.page='menu';this.root.dataset.screen='menu';
    const page=document.querySelector<HTMLElement>('#page')!;page.hidden=false;
    document.querySelector<HTMLElement>('#hud')!.hidden=true;this.hideModal();
    page.innerHTML=menuMarkup(this.profile,this.selectedHero,this.mode,this.difficulty,!!this.saved,this.assetsReady,this.heroEnabled);
    page.scrollTop=0;page.scrollLeft=0;
    if(this.assetError){document.getElementById('loading-message')!.textContent='部分战场素材未能载入，请重新读取。';const retry=document.createElement('button');retry.className='secondary';retry.dataset.action='reload';retry.textContent='重新读取战场';this.root.querySelector('.menu-actions')!.append(retry);}
  }

  private async start(replace=false) {
    if(!this.assetsReady){this.toast('军团正在集结，请稍候。');return;}
    if(this.starting) return;
    if(this.saved?.winner===null && this.mode!=='trial' && !replace){this.modal(`<span class="eyebrow">已有一条未结束的战线</span><h2>继续，还是开启新战线？</h2><p>继续上次对局可保留当前进度。开启新战线会替换这份对局记录，营地档案不受影响。</p><div class="modal-actions"><button class="primary" data-action="resumeSaved">继续上次对局</button><button class="secondary" data-action="replaceMatch">开启新战线</button><button class="text-button" data-action="closeModal">返回</button></div>`);return;}
    this.starting=true;
    try {
      await this.matchSaver.flush();
      const mission=this.mode==='campaign' ? catalog.missions[this.missionId] : undefined;
      if(mission && !missionAvailable(this.profile,mission.id)) throw new Error('请先完成前一关');
      const player=this.mode==='challenge' ? builds.find(build=>build.heroId===this.selectedHero)! : loadoutFor(this.profile,this.selectedHero);
      const enemyProfileId=mission?.enemyProfileId ?? (this.mode==='challenge' ? 'AP03' : 'AP01');
      const enemyTemplate=catalog.builds[catalog.enemies[enemyProfileId].buildId];
      const enemy=this.mode==='challenge' ? enemyTemplate : fitLoadout(enemyTemplate,this.profile.masteryPoints,this.profile.unlockedSkillIds,this.profile.ownedRelicIds);
      const config:MatchConfig={matchId:crypto.randomUUID(),mode:this.mode,heroEnabled:this.heroEnabled,seed:this.mode==='challenge' ? 20261004 : crypto.getRandomValues(new Uint32Array(1))[0],loadout:player,enemyLoadout:enemy,enemyProfileId,difficultyId:this.difficulty,...mission ? {missionId:mission.id} : this.mode==='challenge' ? {startingEraId:'A3',maximumEraId:'A4'} : this.mode==='trial' ? {startingEraId:'A3',maximumEraId:'A5'} : {}};
      if(this.mode==='trial'){this.current=new Battle(config);this.current.state.sides[0].gold=10000000;this.current.state.sides[0].knowledge=1000000;this.current.state.sides[0].command=100000;this.current.spawn(1,'U31','A3').x=85000;this.current.spawn(1,'U34','A3').x=94000;}
      else {const started=await this.profiles.begin(config);this.profile=started.profile;this.current=started.battle;}
      this.enterBattle();
      this.toast('盾兵在前，支援在后；交战获得 XP，可用于进化或时代大招。');
    } catch(error){this.toast(error instanceof Error ? error.message : '开战失败，档案已保留');}
    finally{this.starting=false;}
  }
  private bookPage(title:string,kicker:string,body:string,preserveScroll=false) {
    const oldScroll=document.getElementById('page')!.scrollTop;this.editingLoadout=false;
    this.page='camp';this.root.dataset.screen='camp';document.querySelector<HTMLElement>('#page')!.hidden=false;document.querySelector<HTMLElement>('#hud')!.hidden=true;this.hideModal();
    document.querySelector<HTMLElement>('#page')!.innerHTML=`<div class="book-page"><header class="book-header"><button class="back-button" data-action="menu">${uiIcon('back')}返回营地</button><span>续火盟 / 万年档案</span></header><span class="eyebrow">${kicker}</span><h2>${title}</h2>${body}</div>`;
    document.getElementById('page')!.scrollTop=preserveScroll ? oldScroll : 0;
  }
  private campaign() {
    this.mode='campaign';
    this.bookPage('把炉火带向明日','折线原野 · 五章战役',`<p>恢复万年档案中的工艺与记忆。每关会公开时代范围、敌方构筑与章末规则。</p><div class="campaign-chapters">${chapters.map((chapter,index)=>`<section style="--chapter-image:url('${assetPath(`background.A${index+1}.far`)}')"><div><small>第 ${index+1} 章</small><h3>${chapter.name}</h3><p>${chapter.description}</p></div><div class="mission-nodes">${missions.filter(m=>m.chapter===index+1).map(m=>{const cleared=this.profile.clearedMissionIds.includes(m.id),available=missionAvailable(this.profile,m.id);return `<button data-action="mission" data-value="${m.id}" ${available ? '' : 'disabled'} class="${cleared ? 'cleared' : ''}"><small>${m.boss ? '章末 · ' : ''}${m.id}</small><strong>${m.name}</strong><span>${catalog.eras[m.startingEraId].name} → ${catalog.eras[m.maximumEraId].name}</span><em>${cleared ? '已收录 ✓' : available ? '进入战线 →' : '前一关后开放'}</em></button>`;}).join('')}</div></section>`).join('')}</div>`);
  }
  private missionBrief(id:string) {
    if(!missionAvailable(this.profile,id)) return;
    this.missionId=id;const m=catalog.missions[id],profile=catalog.enemies[m.enemyProfileId],enemy=fitLoadout(catalog.builds[profile.buildId],this.profile.masteryPoints,this.profile.unlockedSkillIds,this.profile.ownedRelicIds);
    const bossText:Record<string,string>={M03:'敌基地生命提高20%。',M06:'敌方预建一座近防炮塔，费用从开局军资扣除。',M09:'敌方轰击会提前0.9秒显示落点。',M12:'敌方时代策略会显示在战场。',M15:'核心在65%与30%生命时各请求一次4秒护盾，每次消耗20能量。'};
    this.modal(`<span class="eyebrow">${m.id} · ${chapters[m.chapter-1].name}</span><h2>${m.name}</h2><div class="story-lines">${missionLines[id].map(line=>`<p>${line}</p>`).join('')}</div><p>${m.teaching}<br>敌军有 ${m.reinforcements?.waves ?? 4} 波增援，每轮间隔 ${m.reinforcements?.periodSec ?? 56} 秒；利用集结空档反推。<br>${catalog.eras[m.startingEraId].name} → ${catalog.eras[m.maximumEraId].name}${m.boss ? `<br>${bossText[id]}` : ''}</p><details class="enemy-brief"><summary>敌方 · ${profile.name} · 查看公开构筑</summary><p>${catalog.heroes[enemy.heroId].name} / ${catalog.specializations[enemy.specializationId].name}<br>${enemy.commonSkillIds.map(s=>catalog.skills[s].name).join('、')}<br>传承 ${enemy.talentIds.length}/${this.profile.masteryPoints} · ${enemy.relicIds.length ? enemy.relicIds.map(r=>catalog.relics[r].name).join('、') : '无遗物'}</p></details><div class="modal-actions"><button class="primary" data-action="startMission">进入战线</button><button class="text-button" data-action="closeModal">回到地图</button></div>`);
  }
  private loadoutPage(reset=true) {
    const focused=document.activeElement instanceof HTMLElement ? {...document.activeElement.dataset} : {};
    if(reset || !this.draft) this.draft=structuredClone(loadoutFor(this.profile,this.selectedHero));
    const draft=this.draft,hero=catalog.heroes[draft.heroId];
    this.bookPage('军议与构筑',`续火盟 · ${this.profile.masteryPoints}点传承`,
      `<div class="camp-hero-grid">${heroes.map(h=>`<button data-action="draftHero" data-value="${h.id}" ${this.profile.unlockedHeroIds.includes(h.id) ? '' : 'disabled'} aria-pressed="${h.id===draft.heroId}">${icon(`portrait.${h.id}`,h.name)}<strong>${h.name}</strong><small>${this.profile.unlockedHeroIds.includes(h.id) ? h.title : `${h.unlockMissionId}首通后加入`}</small></button>`).join('')}</div>
      <div class="build-heading"><h3>${hero.name} · ${hero.title}</h3><span>熟练度 ${this.profile.heroProficiency[hero.id]} · Lv.${1+rules.heroProficiency.thresholds.filter(n=>n>0 && this.profile.heroProficiency[hero.id]>=n).length}</span><button class="secondary" data-action="recommended">应用推荐构筑</button><button class="primary" data-action="saveLoadout">保存军令</button></div>
      <h3 class="camp-label">专精 · 每次选择一项</h3><div class="choice-grid spec-grid">${specializations.filter(s=>s.heroId===hero.id).map(s=>`<button data-action="spec" data-value="${s.id}" aria-pressed="${s.id===draft.specializationId}"><strong>${s.name}</strong><span>${s.description}</span></button>`).join('')}</div>
      <h3 class="camp-label">通用技能 · 先选槽位，再选技能</h3><div class="skill-slots">${draft.commonSkillIds.map((id,index)=>`<button data-action="skillSlot" data-value="${index}" aria-pressed="${index===this.skillSlot}">${icon(`skill.${id}`,catalog.skills[id].name)}<strong>槽 ${index+1} · ${catalog.skills[id].name}</strong></button>`).join('')}</div>
      <div class="choice-grid ability-grid">${skills.filter(s=>s.category==='common').map(s=>`<button data-action="draftSkill" data-value="${s.id}" ${this.profile.unlockedSkillIds.includes(s.id) ? '' : 'disabled'} aria-pressed="${draft.commonSkillIds.includes(s.id)}">${icon(`skill.${s.id}`,s.name)}<strong>${s.name}</strong><span>${this.profile.unlockedSkillIds.includes(s.id) ? s.description : '完成首关后开放'}</span><small>${s.commandCost}能量 / ${s.cooldownSec}秒</small></button>`).join('')}</div>
      <h3 class="camp-label">遗物 · 可空置，最多两件</h3><div class="choice-grid relic-grid">${relics.map(r=>`<button data-action="draftRelic" data-value="${r.id}" ${this.profile.ownedRelicIds.includes(r.id) ? '' : 'disabled'} aria-pressed="${draft.relicIds.includes(r.id)}">${icon(`relic.${r.id}`,r.name)}<strong>${r.name}</strong><span>${this.profile.ownedRelicIds.includes(r.id) ? r.description : '尚未收藏'}</span></button>`).join('')}</div>
      <h3 class="camp-label">传承天赋 · 已用 ${draft.talentIds.length}/${this.profile.masteryPoints} <button class="text-button" data-action="resetTalents">重配路线</button></h3><div class="talent-branches">${[...new Set(talents.map(t=>t.branch))].map(branch=>`<section><h4>${branch}</h4>${talents.filter(t=>t.branch===branch).map(t=>`<button data-action="talent" data-value="${t.id}" aria-pressed="${draft.talentIds.includes(t.id)}"><small>第${t.tier}层</small><strong>${t.name}</strong><span>${t.description}</span></button>`).join('')}</section>`).join('')}</div><button class="primary" data-action="saveLoadout">保存这套军令</button>`,!reset);
    this.editingLoadout=true;
    const indicator=document.createElement('span');indicator.className='draft-status';indicator.textContent=this.draftDirty() ? '军令有未保存的调整' : '当前军令已收录';indicator.setAttribute('role','status');this.root.querySelector('.build-heading')!.append(indicator);
    if(!reset && focused.action)[...this.root.querySelectorAll<HTMLElement>('[data-action]')].find(e=>e.dataset.action===focused.action && e.dataset.value===focused.value)?.focus({preventScroll:true});
  }
  private draftDirty(){
    if(!this.draft)return false;
    const signature=(l:Loadout)=>JSON.stringify([l.heroId,l.specializationId,l.commonSkillIds,[...l.relicIds].sort(),[...l.talentIds].sort()]);
    return signature(this.draft)!==signature(loadoutFor(this.profile,this.draft.heroId));
  }
  private collection() {
    this.bookPage('万年遗物','生活与工艺的记录',`<p>已收藏 ${this.profile.ownedRelicIds.length}/12 · 藏品碎片 ${this.profile.fragments}。首通固定遗物，胜利藏品箱可获收藏；重复转换一片碎片。第一章后可用四片定向制作。</p><div class="choice-grid collection-grid">${relics.map(r=>{const owned=this.profile.ownedRelicIds.includes(r.id);return `<article class="relic-card rarity-${r.rarity}">${icon(`relic.${r.id}`,r.name)}<small>${{common:'普通',rare:'稀有',epic:'史诗'}[r.rarity] ?? r.rarity}</small><h3>${r.name}</h3><p>${r.description}</p><button class="secondary" data-action="craft" data-value="${r.id}" ${owned || !this.profile.clearedMissionIds.includes('M03') || this.profile.fragments<4 ? 'disabled' : ''}>${owned ? '已经收藏 ✓' : '定向制作 · 4碎片'}</button></article>`;}).join('')}</div><details class="enemy-brief"><summary>查看藏品箱概率与保底</summary><p>普通60% / 稀有30% / 史诗10%，每类四件均分。连续四箱没有稀有，第五箱稀有75%或史诗25%；连续十九箱没有史诗，第二十箱必得史诗。固定首通与制作不影响保底。</p></details>`);
  }
  private enterBattle() {
    const config=this.current!.state.config;this.mode=config.mode;this.selectedHero=config.loadout.heroId;this.difficulty=config.difficultyId;if(config.missionId)this.missionId=config.missionId;
    this.page='battle';this.root.dataset.screen='battle';this.camera.reset(); this.ended=false; this.selectedSkill=null; this.accumulator=0; this.uiEra=''; this.queueKey=''; this.hudTick=-1; this.lastSavedTick=this.current?.state.tick ?? 0; this.audio.reset();
    document.querySelector<HTMLElement>('#page')!.hidden=true; document.querySelector<HTMLElement>('#hud')!.hidden=false; this.hideModal();
    this.paintHud(true);
    void this.audio.setMusic(`music.age${this.current!.state.sides[0].eraId[1]}`);
  }
  interpolation(){return this.current?.state.paused ? 1 : Math.min(1,this.accumulator/(1000/30));}
  ready(errors:string[]=[]){this.assetError=errors.length>0;this.assetsReady=!this.assetError;if(this.profile && this.page==='menu'){this.menu();this.finishRestored();}}
  private finishRestored(){if(this.assetsReady && this.saved?.winner!==null && this.saved){this.current=new Battle(this.saved.config,this.saved);this.enterBattle();void this.result();}}
  advance(delta: number) {
    if (!this.current || this.page!=='battle') return;
    if (innerWidth<700 && innerHeight>innerWidth && !this.current.state.paused) { this.pause(); this.toast('扩大窗口或切换横屏，可以完整观察战线。'); }
    if (!this.current.state.paused && this.current.state.winner===null) {
      const advanced=advanceSimulation(this.accumulator,delta,()=>this.current!.step());
      this.accumulator=advanced.accumulator;const steps=advanced.steps;
      this.audio.consume(this.current.state.events,this.current.state);
      if (this.current.state.tick-this.lastSavedTick>=150 && steps>0) {this.lastSavedTick=this.current.state.tick;void this.persist();}
    }
    this.paintHud();
    if (this.current.state.sides[0].awaitingUpgrade) this.evolution();
    if (this.current.state.winner!==null && !this.ended) void this.result();
  }
  private dispatch(action: Action) {
    if (!this.current) return;
    const result=this.current.act(action,this.current.state.lastActionSequence+1);
    if (!result.ok) { this.audio.error(); this.toast(result.reason ?? '当前无法执行'); }
    this.paintHud(true);if(result.ok){haptic();void this.persist();}return result;
  }
  point(x: number,targetId?: number) {
    if (!this.current || this.page!=='battle' || !this.selectedSkill || this.current.state.paused) return;
    const result=this.selectedSkill==='age-special' ? this.dispatch({type:'ageSpecial',side:0,x}) : this.selectedSkill.startsWith('item:') ? this.dispatch({type:'item',side:0,itemId:this.selectedSkill.slice(5) as ActiveItemId,x}) : this.dispatch({ type: 'cast',side: 0,skillId: this.selectedSkill,x,targetId });
    if (result?.ok) this.selectedSkill=null;
    this.paintHud(true);
  }
  private selectSkill(index: number) {
    if (!this.current || this.current.state.paused || this.current.state.winner!==null) return;
    const player=this.current.state.sides[0];
    const skillId=[catalog.heroes[player.loadout.heroId].signatureSkillId,...player.loadout.commonSkillIds][index];
    if (!skillId) return;
    const skill=catalog.skills[skillId];
    if(this.current.hero(0)?.garrisoned){this.toast('指挥官正在基地休整，选择掩护或冲锋即可归队。');return;}
    if(!this.current.hero(0) || (player.cooldowns[skillId] ?? 0)>this.current.state.tick || player.command<this.current.skillCost(0,skillId)*1000){this.toast('指挥官重建中、能量不足或技能尚未就绪。');return;}
    const heroX=worldX(this.current.hero(0)!);if(heroX<this.camera.x+40 || heroX>this.camera.x+this.camera.width-40){this.camera.tracking='free';this.camera.focus(heroX);this.paintCamera();}
    if (skill.targetMode==='self' || skill.targetMode==='direction_self') { this.dispatch({ type: 'cast',side: 0,skillId,x: worldX(this.current.hero(0) ?? this.current.base(0)) }); return; }
    this.selectedSkill=this.selectedSkill===skillId ? null : skillId;
    if (this.selectedSkill) this.toast(`${skill.name}：点战场确认；右键或Esc取消。`);
    this.paintHud(true);
  }
  private paintHud(force=false) {
    const battle=this.current; if (!battle) return;
    if (!force && this.hudTick===battle.state.tick) return; this.hudTick=battle.state.tick;
    const player=battle.state.sides[0],enemy=battle.state.sides[1],hero=catalog.heroes[player.loadout.heroId];
    const commander=battle.hero(0);
    if(commander?.garrisoned && this.selectedSkill!=='age-special')this.selectedSkill=null;
    if (this.uiEra!==player.eraId) {
      void this.audio.setMusic(`music.age${player.eraId[1]}`);
      this.uiEra=player.eraId;
      document.querySelector<HTMLElement>('#hud')!.innerHTML=battleHud(battle);
      this.queueKey='';this.mapTick=-1;
    }
    const labels: Record<string,string>={ population:`${battle.population(0)}/${battle.populationCap()}`,stance:{cover:'掩护',rush:'冲锋',retreat:'撤回'}[player.stance],heroStatus:battle.hero(0) ? `${Math.round(battle.hero(0)!.hp/battle.hero(0)!.maxHp*100)}%生命` : '重建后自动归队',allyEra: catalog.eras[player.eraId].name,enemyEra: catalog.eras[enemy.eraId].name,allyHp: `${battle.base(0).hp} / ${battle.base(0).maxHp}`,enemyHp: `${battle.base(1).hp} / ${battle.base(1).maxHp}`,gold: Math.floor(player.gold/1000).toString(),knowledge: Math.floor(player.knowledge/1000).toString(),command: `${Math.floor(player.command/1000)}`,time: clock(battle.state.tick),heroLife: battle.hero(0) ? `生命 ${battle.hero(0)!.hp}` : `重建 ${Math.max(0,Math.ceil((player.heroRespawnAt-battle.state.tick)/30))}秒`,evolveCost: player.eraId===battle.maxEraId ? 'MAX' : `${catalog.eras[player.eraId].nextEvolutionKnowledge} XP`,turretCount: `${player.turrets.length}/${player.unlockedSlots}` };
    for (const [key,text] of Object.entries(labels)) { const element=this.root.querySelector(`[data-text="${key}"]`); if (element) element.textContent=text; }
    if(commander?.garrisoned){const status=this.root.querySelector('[data-text="heroStatus"]');if(status)status.textContent=`驻营休整 ${Math.round(commander.hp/commander.maxHp*100)}%`;}
    const wave=reinforcementWindow(battle.state),waveLabel=this.root.querySelector<HTMLElement>('[data-text="wave"]');
    if(waveLabel && wave){waveLabel.textContent=wave.exhausted ? '增援结束' : wave.deploying ? wave.total ? `${wave.wave}/${wave.total}` : '交战' : `集结 ${wave.nextSec}s`;waveLabel.title=wave.total ? `敌方增援 ${wave.wave}/${wave.total} 波，${wave.deploying ? '本波出兵中' : wave.exhausted ? '已无后续增援' : '正在集结下一波'}` : `敌方${wave.deploying ? '出兵中' : '正在集结'}；每分钟组织下一轮攻势`;}
    for (const [id,base] of [['ally-hp',battle.base(0)],['enemy-hp',battle.base(1)]] as const) { const bar=document.getElementById(id) as HTMLProgressElement; bar.max=base.maxHp; bar.value=base.hp; }
    const inactive=battle.state.paused || battle.state.winner!==null;
    for (const unit of units.filter(item => item.eraId===player.eraId)) (document.getElementById(`unit-${unit.id}`) as HTMLButtonElement).disabled=inactive || (!unit.heavy || battle.heavyUnlocked(0)) && (player.gold<battle.unitCost(0,unit.id)*1000 || player.queue.length>=5);
    for (const stance of ['cover','rush','retreat']){const button=document.getElementById(`stance-${stance}`) as HTMLButtonElement|null;if(!button)continue;button.classList.toggle('active',player.stance===stance);button.setAttribute('aria-pressed',String(player.stance===stance));button.disabled=inactive || !battle.hero(0) || player.stanceReadyAt>battle.state.tick;}
    (document.getElementById('fort') as HTMLButtonElement).disabled=inactive;
    (this.root.querySelector('.pause-button') as HTMLButtonElement).disabled=battle.state.winner!==null;
    const heroBar=document.getElementById('hero-hp') as HTMLProgressElement|null;if(heroBar){heroBar.max=battle.hero(0)?.maxHp ?? 1;heroBar.value=battle.hero(0)?.hp ?? 0;}
    const skillIds=[hero.signatureSkillId,...player.loadout.commonSkillIds];
    for (const id of skillIds) {
      const cooldown=Math.max(0,Math.ceil(((player.cooldowns[id] ?? 0)-battle.state.tick)/30)),button=document.getElementById(`skill-${id}`) as HTMLButtonElement;
      if(!button)continue;
      button.disabled=!commander || commander.garrisoned===true || cooldown>0 || player.command<battle.skillCost(0,id)*1000 || inactive;
      (document.getElementById(`cooldown-${id}`) as HTMLElement).style.height=`${Math.min(100,cooldown/catalog.skills[id].cooldownSec*100)}%`;
      button.classList.toggle('aiming',this.selectedSkill===id); document.getElementById(`skill-state-${id}`)!.textContent=`${cooldown ? cooldown+'s' : battle.skillCost(0,id)}`;
    }
    (document.getElementById('evolve') as HTMLButtonElement).disabled=player.eraId===battle.maxEraId || player.knowledge<(catalog.eras[player.eraId].nextEvolutionKnowledge ?? Infinity)*1000 || inactive;
    const evolve=document.getElementById('evolve') as HTMLButtonElement;
    const xpProgress=Math.min(100,player.knowledge/1000/(catalog.eras[player.eraId].nextEvolutionKnowledge ?? Infinity)*100);
    (document.getElementById('evolve-progress') as HTMLElement).style.background=`conic-gradient(#ffcf69 ${xpProgress}%,#c9b17a ${xpProgress}% 100%)`;
    evolve.classList.toggle('ready',!evolve.disabled);
    const special=ageSpecials[player.eraId as keyof typeof ageSpecials],cooldown=Math.max(0,Math.ceil((player.ageSpecialReadyAt-battle.state.tick)/30));
    const specialButton=document.getElementById('age-special') as HTMLButtonElement;
    specialButton.disabled=inactive || cooldown>0 || player.knowledge<special.cost*1000;specialButton.classList.toggle('aiming',this.selectedSkill==='age-special');
    document.getElementById('age-special-state')!.textContent=cooldown>0 ? `${cooldown}s` : `${special.cost} XP`;
    for(const id of activeItemIds){
      const item=activeItems[id],charges=player.activeItems[id] ?? 0,itemCooldown=Math.max(0,Math.ceil(((player.itemCooldowns[id] ?? 0)-battle.state.tick)/30));
      const button=document.getElementById(`item-${id}`) as HTMLButtonElement|null;if(!button)continue;
      button.disabled=inactive || charges<=0 || itemCooldown>0;
      button.classList.toggle('aiming',this.selectedSkill===`item:${id}`);
      const count=document.getElementById(`item-count-${id}`);if(count)count.textContent=String(charges);
      const state=document.getElementById(`item-state-${id}`);if(state)state.textContent=itemCooldown>0 ? `${itemCooldown}s` : item.shortName;
      const mask=document.getElementById(`item-cooldown-${id}`) as HTMLElement|null;if(mask)mask.style.height=`${Math.min(100,itemCooldown/item.cooldownSec*100)}%`;
    }
    (document.getElementById('research') as HTMLButtonElement).disabled=inactive;
    const aim=document.getElementById('aim-instruction')!;aim.hidden=!this.selectedSkill;if(this.selectedSkill){const itemId=this.selectedSkill.startsWith('item:') ? this.selectedSkill.slice(5) as ActiveItemId : null,skill=itemId ? null : catalog.skills[this.selectedSkill];document.getElementById('aim-description')!.textContent=this.selectedSkill==='age-special' ? `${special.name} · 点选轰击位置 · 消耗 ${special.cost} XP` : itemId ? `${activeItems[itemId].name} · 点选落点` : `${skill!.name} · ${skill!.targetMode==='enemy_entity' ? '点选敌方单位' : skill!.targetMode.startsWith('ally') ? '点选己方军团附近' : '点选战线落点'}`; }
    const hint=document.getElementById('battle-hint')!;hint.hidden=(battle.state.config.missionId!=='M01' && (this.profile.tutorialComplete || battle.state.tick>600)) || battle.state.tick>2700 || inactive;
    if(!hint.hidden)hint.textContent=battle.population(0)<2 ? '点盾兵建立前排，再点投石兵叠加火力。' : player.knowledge>=(catalog.eras[player.eraId].nextEvolutionKnowledge ?? Infinity)*1000 ? '进化已经就绪：点击金色时代按钮，派出新时代军团。' : '交战带来 XP；进化与大招共享经验。长矛能隔着一名前排攻击。';
    this.paintCamera();
    const queueKey=player.queue.map(item => `${item.id}:${item.remaining===0}`).join(',');
    if (queueKey!==this.queueKey) { document.getElementById('training-queue')!.innerHTML=player.queue.map(item => `<span class="queue-item" title="${catalog.units[item.unitId].name}">${icon(`icon.${item.unitId}`,catalog.units[item.unitId].name)}<span id="queue-time-${item.id}"></span><i id="queue-progress-${item.id}"></i></span>`).join('') || '<span class="queue-empty">＋ ＋ ＋ ＋ ＋</span>'; this.queueKey=queueKey; }
    for (const [index,item] of player.queue.entries()) {
      const blocked=item.remaining===0 ? battle.spawnBlocked(0,item.unitId) : null,element=document.getElementById(`queue-time-${item.id}`)!;
      if(blocked)element.innerHTML=uiIcon(blocked==='exit' ? 'door' : 'people');else element.textContent=index===0 ? `${Math.ceil(item.remaining/30)}` : '·';
      const chip=element.closest<HTMLElement>('.queue-item')!;chip.classList.toggle('exit-blocked',blocked==='exit');chip.title=`${catalog.units[item.unitId].name} · ${blocked==='exit' ? '出口被占用，等待前方腾出位置' : blocked==='population' ? '人口已满，等待空位' : '训练中，可在队列管理中取消'}`;
      (document.getElementById(`queue-progress-${item.id}`) as HTMLElement).style.width=`${100*(1-item.remaining/item.duration)}%`;
    }
  }

  canNavigate(){return this.page==='battle' && !!this.current && !this.current.state.paused && this.current.state.winner===null && document.getElementById('overlay')!.hidden===true;}
  paintCamera(){
    const frame=document.getElementById('map-window'),map=document.getElementById('battle-minimap');
    if(frame){frame.style.left=`${this.camera.x/1600*100}%`;frame.style.width=`${this.camera.width/1600*100}%`;}
    map?.setAttribute('aria-valuenow',String(Math.round(this.camera.x)));
    document.getElementById('follow-hero')?.setAttribute('aria-pressed',String(this.camera.tracking==='hero'));
    document.getElementById('follow-front')?.setAttribute('aria-pressed',String(this.camera.tracking==='front'));
    const fighters=document.getElementById('map-fighters');
    if(fighters && this.current && this.current.state.tick%6===0 && this.mapTick!==this.current.state.tick){fighters.innerHTML=this.current.living().filter(e=>e.kind!=='base').map(e=>`<i class="${e.side===0 ? 'friend' : 'foe'} ${e.kind==='hero' ? 'hero' : ''}" style="left:${worldX(e)/1600*100}%"></i>`).join('');this.mapTick=this.current.state.tick;}
  }
  private hideModal(){
    const overlay=document.getElementById('overlay');if(overlay){overlay.hidden=true;overlay.innerHTML='';}
    for(const id of ['page','hud']){const element=document.getElementById(id);if(element)element.inert=false;}
    if(this.modalFocus?.isConnected)this.modalFocus.focus({preventScroll:true});this.modalFocus=null;
  }
  private modal(body:string,kind='notice'){
    const overlay=document.getElementById('overlay')!;
    if(overlay.hidden)this.modalFocus=document.activeElement instanceof HTMLElement ? document.activeElement : null;
    overlay.hidden=false;overlay.dataset.kind=kind;overlay.innerHTML=`<div class="modal" role="dialog" aria-modal="true" aria-labelledby="dialog-title">${body}</div>`;
    overlay.querySelector('h2')?.setAttribute('id','dialog-title');
    for(const id of ['page','hud'])document.getElementById(id)!.inert=true;
    overlay.querySelector<HTMLButtonElement>('button:not(:disabled)')?.focus({preventScroll:true});
  }

  private evolution() {
    const battle=this.current!;
    if (document.getElementById('era-options')) return;
    const era=battle.state.sides[0].eraId;
    this.modal(`<span class="eyebrow">文明的新篇章</span><h2>${catalog.eras[era].name}</h2><p>选择这次进化的军团策略，随后前三名新时代新兵将获得换代冲锋。</p><div class="era-options" id="era-options">${upgrades.filter(upgrade => upgrade.eraId===era).map(upgrade => `<button data-action="upgrade" data-value="${upgrade.id}"><strong>${upgrade.name.split('·')[0]}</strong><span>${upgrade.description}</span><small>仅本局生效</small></button>`).join('')}</div>`,'upgrade');
  }
  pause() {
    if (!this.current || this.page!=='battle' || this.current.state.winner!==null || this.current.state.sides[0].awaitingUpgrade) return;
    if(this.current.state.paused && !document.getElementById('overlay')!.hidden)return;
    this.current.state.paused=true; this.accumulator=0; this.selectedSkill=null; this.audio.suspend();
    const trial=this.current.state.config.mode==='trial';
    this.modal(`<span class="eyebrow">军令暂歇</span><h2>战线已暂停</h2><p>${innerWidth<700 && innerHeight>innerWidth ? '请将设备转为横屏，再继续进军。<br>' : ''}资源、冷却与战斗均已停止。</p><div class="modal-actions"><button class="primary" data-action="continue">继续进军</button>${trial ? '' : '<button class="secondary" data-action="export">导出对局</button>'}<button class="text-button" data-action="saveMenu">${trial ? '结束演练并返回营地' : '保存并返回营地'}</button></div>`,'pause');
    void this.persist(); this.paintHud(true);
  }
  private continue() {
    if (!this.current || this.current.state.winner!==null || this.current.state.sides[0].awaitingUpgrade) return;
    if(innerWidth<700 && innerHeight>innerWidth){this.toast('请将设备转为横屏，再继续进军。');return;}
    this.current.state.paused=false; this.accumulator=0;this.hideModal();
    void this.audio.unlock(); this.paintHud(true);
  }
  private async result() {
    const battle=this.current!,winner=battle.state.winner,player=battle.state.sides[0]; this.ended=true; this.selectedSkill=null;
    void this.audio.setMusic(winner===0 ? 'music.victory' : 'music.defeat');
    let receipt:RewardReceipt | null=null;
    const feedback=new Promise<void>(resolve=>setTimeout(resolve,900));this.paintHud(true);
    try {await this.matchSaver.flush();if(battle.state.config.mode!=='trial'){const result=await this.profiles.commit(battle.snapshot());this.profile=result.profile;receipt=result.receipt;this.saved=null;}}
    catch(error){this.modal(`<h2>军报尚未收录</h2><p>${html(error instanceof Error ? error.message : '保存失败')}。对局记录已保留，可重试。</p><button class="primary" data-action="retryResult">重试收录</button>`);return;}
    await feedback;
    this.modal(`<span class="eyebrow">${winner===0 ? '续火盟军报' : winner==='draw' ? '双方战线同时崩塌' : '下一场还有新的答案'}</span><h2>${winner===0 ? '战线突破' : winner==='draw' ? '同归于尽' : '战线失守'}</h2><p>${winner===0 ? battle.state.config.missionId==='M15' ? '定序核心已经瓦解。万年档案重新向每个人敞开，文明的下一步，由你决定。' : '定序军堡垒已被攻破，这段历史由你写下。' : player.eraId!==battle.state.sides[1].eraId ? '对手进入了更高时代。下一局可以留出金币，为换代兵团准备一次反推。' : '带着这局的经验，重新安排军团与技能时机。'}</p><div class="result-stats"><span><b>${clock(battle.state.tick)}</b>交战时长</span><span><b>${player.kills}</b>敌兵击破</span><span><b>${player.comboHits}</b>技能配合命中</span></div>
      ${receipt ? `<div class="reward-strip">${receipt.relics.map(item=>`<div>${icon(`relic.${item.id}`,catalog.relics[item.id].name)}<strong>${catalog.relics[item.id].name}</strong><small>${item.duplicate ? '重复 · 转为1碎片' : item.source==='first_clear' ? '首通收藏' : '藏品箱收藏'}</small></div>`).join('')}</div><p class="reward-notes">熟练度 +${receipt.proficiency}${receipt.fragments ? ` · 碎片 +${receipt.fragments}` : ''}${receipt.mastery ? ` · 传承 +${receipt.mastery}` : ''}${receipt.heroUnlocks.length ? `<br>${receipt.heroUnlocks.map(id=>catalog.heroes[id].name).join('、')}加入续火盟` : ''}${receipt.firstClear && battle.state.config.missionId==='M01' ? '<br>全部通用技能已开放，前往军议搭配你的第一套组合。' : ''}</p>` : '<p>演练战场不发放档案奖励。</p>'}
      <div class="modal-actions"><button class="primary" data-action="rematch">再战一局</button>${battle.state.config.mode==='campaign' ? '<button class="secondary" data-action="campaign">回到战役地图</button>' : ''}<button class="text-button" data-action="menu">返回营地</button></div>`,'result');
  }
  private fort() {
    if (!this.current || this.current.state.winner!==null) return;
    this.current.state.paused=true; this.accumulator=0;this.selectedSkill=null;this.audio.suspend();
    const player=this.current.state.sides[0],era=player.eraId;
    this.modal(`<span class="eyebrow">基地防务 · ${Math.floor(player.gold/1000)}军资</span><h2>炮塔阵地</h2><p>选择一项建造或拆除军令，返回战场后立即执行。</p><div class="fort-slots">${Array.from({ length: player.unlockedSlots },(_,slot) => { const turret=player.turrets.find(item => item.slot===slot); return `<div><strong>阵地 ${slot+1}</strong>${turret ? `${icon(`turret.${turret.contentId}`,catalog.turrets[turret.contentId].name)}<p>${catalog.turrets[turret.contentId].name}</p><button data-action="sell" data-value="${slot}">拆除 · 返还${Math.floor(turret.paid*.6)/1000}军资</button>` : ['1','2'].map((suffix,index) => { const id=`TR${era[1]}${suffix}`,cost=Math.ceil(catalog.turrets[id].costBase*catalog.eras[era].costMultiplier); return `<button data-action="buy" data-value="${slot}:${id}" ${player.gold<cost*1000 ? 'disabled' : ''}>${index===0 ? '近防' : '远轰'} · ${cost}军资</button>`; }).join('')}</div>`; }).join('')}</div>${player.unlockedSlots<3 ? `<button class="secondary" data-action="unlockSlot" ${player.gold<(player.unlockedSlots===1 ? 90000 : 180000) ? 'disabled' : ''}>开放下一阵地 · ${player.unlockedSlots===1 ? 90 : 180}军资</button>` : ''}<button class="text-button" data-action="continue">返回战场</button>`,'fort');
    this.paintHud(true);
  }
  private researchMenu(){
    if(!this.current || this.current.state.winner!==null)return;
    this.current.state.paused=true;this.accumulator=0;this.selectedSkill=null;this.audio.suspend();
    const player=this.current.state.sides[0];
    this.modal(`<span class="eyebrow">${uiIcon('coin')} ${Math.floor(player.gold/1000)} 金币</span><h2>军团强化</h2><div class="research-grid">${researches.map(row=>{
      const level=researchLevel(player,row.id),cost=researchCost(player,row.id),maxed=level>=row.max;
      return `<button class="research-card" data-action="buyResearch" data-value="${row.id}" ${maxed || player.gold<cost*1000 || row.id==='heavy-attack' && !this.current!.heavyUnlocked(0) ? 'disabled' : ''}>${uiIcon(row.icon)}<span><strong>${row.name} <small>${level}/${row.max}</small></strong><small>${row.description}</small></span><b>${maxed ? uiIcon('check') : cost}</b></button>`;
    }).join('')}</div><p>强化消耗金币，跨时代保留；进化和时代大招消耗 XP。</p><button class="text-button" data-action="continue">${uiIcon('back')}返回战场</button>`,'research');
    this.paintHud(true);
  }
  private unitHelp(){
    if(!this.current || this.current.state.winner!==null)return;
    this.current.state.paused=true;this.accumulator=0;this.selectedSkill=null;this.audio.suspend();
    const era=catalog.eras[this.current.state.sides[0].eraId],roles:Record<string,string>={front:'步兵 → 克制支援',ranged:'支援 → 克制反装甲',anti_armor:'反装甲 → 克制重型',heavy:'重型 → 克制步兵'};
    this.modal(`<span class="eyebrow">${era.name}</span><h2>当前军团</h2><div class="unit-help-grid">${units.filter(u=>u.eraId===era.id).map(u=>{const special=typeof u.special.auraLabel==='string' ? u.special.auraLabel : u.special.firstContactBonus ? '猎袭：奔袭后的首次命中更重' : '';return `<article>${icon(`icon.${u.id}`,u.name)}<div><strong>${u.name}</strong><p>${roles[u.role]}${special ? ` · ${special}` : ''}</p><small>${Math.round(u.hpBase*era.hpAttackMultiplier)} HP · 射程 ${u.range}</small></div></article>`;}).join('')}</div><p>短兵在前排接敌，长矛可隔一名前排攻击；远程在射程内同时输出。特种单位用光环、首击或支援效果改变战线节奏。基地门口被占用时，训练完成的兵会等待出口。指挥官撤回后驻营休整，每秒恢复 2.5% 生命；选择掩护或冲锋后，从空闲出口归队。</p><button class="text-button" data-action="continue">${uiIcon('back')}返回战场</button>`,'unitHelp');
    this.paintHud(true);
  }
  private trainingMenu(){
    if(!this.current || this.current.state.winner!==null)return;
    this.current.state.paused=true;this.accumulator=0;this.selectedSkill=null;
    const queue=this.current.state.sides[0].queue;
    this.modal(`<span class="eyebrow">出营顺序 · ${queue.length}/5</span><h2>训练队列</h2><div class="training-list">${queue.length ? queue.map((q,i)=>`<article>${icon(`icon.${q.unitId}`,catalog.units[q.unitId].name)}<div><strong>${catalog.units[q.unitId].name}</strong><small>${catalog.eras[q.eraId].name} · ${q.remaining===0 ? '完成训练，等待出营' : i===0 ? `还需 ${Math.ceil(q.remaining/30)} 秒` : '等待前一项完成'}</small></div><button data-action="cancelTraining" data-value="${q.id}" aria-label="取消${catalog.units[q.unitId].name}训练">${uiIcon('back')}<small>返还 ${Math.floor(q.paid*(q.remaining===q.duration ? 1 : .75)/1000)}</small></button></article>`).join('') : '<p>选择兵卡即可训练部队。</p>'}</div><p>按付费时的时代出营。未开始全额退款，已开始返还 75%。</p><button class="text-button" data-action="continue">${uiIcon('back')}返回战场</button>`,'training');
  }
  private selectAgeSpecial(){
    if(!this.current || this.current.state.paused)return;
    const player=this.current.state.sides[0],special=ageSpecials[player.eraId as keyof typeof ageSpecials];
    if(player.knowledge<special.cost*1000 || player.ageSpecialReadyAt>this.current.state.tick)return;
    this.selectedSkill=this.selectedSkill==='age-special' ? null : 'age-special';this.paintHud(true);
  }
  private selectActiveItem(itemId: ActiveItemId){
    if(!this.current || this.current.state.paused || this.current.state.winner!==null)return;
    const item=activeItems[itemId],player=this.current.state.sides[0];
    if(!item || (player.activeItems[itemId] ?? 0)<=0 || (player.itemCooldowns[itemId] ?? 0)>this.current.state.tick){this.toast('主动道具尚未就绪。');return;}
    if(item.targetMode==='self'){this.dispatch({type:'item',side:0,itemId});return;}
    this.selectedSkill=this.selectedSkill===`item:${itemId}` ? null : `item:${itemId}`;
    if(this.selectedSkill)this.toast(`${item.name}：点战场选择落点；右键或 Esc 取消。`);
    this.paintHud(true);
  }
  private encyclopedia(){
    this.bookPage('从投石到磁轨','万年档案 · 军团图鉴',`<p>前排护阵，远程输出，破甲克制重型；招牌兵带来时代独有的交战节奏。</p><div class="catalog-eras">${eras.map(era=>`<section><h3><small>${era.id.replace('A','0')}</small>${era.name}</h3><div class="catalog-units">${units.filter(unit=>unit.eraId===era.id).map(unit=>`<article>${icon(`unit.${unit.id}`,unit.name)}<div><strong>${unit.name}</strong><p>${Math.floor(unit.hpBase*era.hpAttackMultiplier)}生命 · ${unit.range}射程</p><small>${html(unit.visual)}</small></div></article>`).join('')}</div></section>`).join('')}</div>`);
  }
  private settings(){
    document.body.classList.toggle('reduce-motion',this.reducedMotion);
    this.bookPage('行军偏好','声音、动态与档案',`<div class="settings-page"><button class="setting-row" data-action="sound"><span>战斗声音<small>军团、技能与时代音乐</small></span><strong>${this.audio.muted ? '关闭' : '开启'}</strong></button><button class="setting-row" data-action="motion"><span>降低动态效果<small>减少镜头震动与装饰动效</small></span><strong>${this.reducedMotion ? '开启' : '关闭'}</strong></button><div class="instructions"><h3>战场指挥手册</h3><p>拖动战场、滚轮或 ← → 平移视野；Home / End 定位双方基地。点击小地图定位，点击「前线」或「指挥官」持续跟随。</p><p>1–5 训练 · G 战鼓 · V 烟幕 · N 补给 · R 进化 · F 时代大招 · T 强化 · B 炮塔 · I 兵种说明 · Esc 暂停或取消瞄准。开启指挥官后，Q/W/E 技能，Z/X/C 站位。</p><p>触屏点技能或道具后再点目标；拖动只移动视野。点人数图标管理队列，未开始全额退款，训练中退75%。</p></div><div class="archive-actions"><h3>你的万年档案</h3><p>档案包含战役、指挥官、构筑和收藏；对局文件用于恢复未结束的战线。</p><div class="modal-actions"><button class="secondary" data-action="exportProfile">导出完整档案</button><button class="secondary" data-action="importProfile">导入完整档案</button><button class="text-button" data-action="import">导入对局文件</button></div></div><input id="save-file" type="file" accept=".json,application/json" hidden></div>`);
  }

  private download(data:unknown,name:string) {
    void exportFile(data,name).catch(error=>this.toast(error instanceof Error ? error.message : '文件导出失败'));
  }
  private async persist():Promise<boolean>{
    if(!this.current || this.current.state.winner!==null || this.current.state.config.mode==='trial'){await this.matchSaver.flush();return true;}
    try{this.saved=await this.matchSaver.save(this.current.snapshot());return true;}
    catch(error){this.toast(error instanceof Error ? error.message : '存档写入失败，请重试');return false;}
  }

  private async handle(action: string,value?: string) {
    void this.audio.unlock().catch(()=>this.toast('点击声音设置可再次尝试开启音频。'));
    if(this.editingLoadout && this.draftDirty() && ['menu','draftHero'].includes(action)){
      this.pendingNavigation={action,value};this.modal('<h2>这套军令还未保存</h2><p>保存后可在下一场对局使用，也可以舍弃本次调整。</p><div class="modal-actions"><button class="primary" data-action="saveAndLeave">保存并继续</button><button class="secondary" data-action="discardAndLeave">舍弃调整</button><button class="text-button" data-action="closeModal">继续编辑</button></div>');return;
    }
    if(action==='saveAndLeave' || action==='discardAndLeave'){
      if(action==='saveAndLeave'){await this.handle('saveLoadout');if(this.draftDirty())return;}
      const next=this.pendingNavigation;this.pendingNavigation=null;this.editingLoadout=false;this.hideModal();if(next)await this.handle(next.action,next.value);return;
    }
    if (action==='start') {if(this.mode==='campaign') this.campaign();else await this.start();}
    else if(action==='startMission' || action==='rematch') await this.start();
    else if(action==='replaceMatch')await this.start(true);
    else if(action==='retryResult') await this.result();
    else if(action==='campaign'){this.current=null;this.campaign();}
    else if(action==='mission' && value) this.missionBrief(value);
    else if(action==='mode' && value){this.mode=value as MatchConfig['mode'];this.menu();}
    else if(action==='heroToggle'){this.heroEnabled=!this.heroEnabled;this.menu();}
    else if(action==='closeModal'){this.importCandidate=null;this.pendingNavigation=null;this.hideModal();}
    else if(action==='loadout') this.loadoutPage();
    else if(action==='collection') this.collection();
    else if(action==='draftHero' && value && this.profile.unlockedHeroIds.includes(value)){this.selectedHero=value;this.loadoutPage();}
    else if(action==='skillSlot' && value){this.skillSlot=Number(value);this.loadoutPage(false);}
    else if(action==='spec' && value && this.draft){this.draft.specializationId=value;this.loadoutPage(false);}
    else if(action==='draftSkill' && value && this.draft){
      if(!this.profile.unlockedSkillIds.includes(value)) return;
      const previous=this.draft.commonSkillIds[this.skillSlot],existing=this.draft.commonSkillIds.indexOf(value);
      if(existing>=0)this.draft.commonSkillIds[existing]=previous;this.draft.commonSkillIds[this.skillSlot]=value;this.loadoutPage(false);
    } else if(action==='draftRelic' && value && this.draft){
      if(!this.profile.ownedRelicIds.includes(value)) return;
      if(this.draft.relicIds.includes(value)) this.draft.relicIds=this.draft.relicIds.filter(id=>id!==value);
      else if(this.draft.relicIds.length<2)this.draft.relicIds.push(value);else{this.toast('先卸下一件遗物，再换上新藏品。');return;}this.loadoutPage(false);
    } else if(action==='talent' && value && this.draft){
      const candidate={...this.draft,talentIds:this.draft.talentIds.includes(value) ? this.draft.talentIds.filter(id=>id!==value) : [...this.draft.talentIds,value]},errors=loadoutErrors(candidate,this.profile.masteryPoints,availability(this.profile));
      if(errors.length){this.toast(errors[0]);return;}this.draft=candidate;this.loadoutPage(false);
    } else if(action==='resetTalents' && this.draft){this.draft.talentIds=[];this.loadoutPage(false);}
    else if(action==='recommended'){this.draft=fitLoadout(builds.find(build=>build.heroId===this.selectedHero)!,this.profile.masteryPoints,this.profile.unlockedSkillIds,this.profile.ownedRelicIds);this.loadoutPage(false);this.toast(this.profile.tutorialComplete ? '已按当前传承与收藏应用推荐。' : '教程阶段使用护盾与鼓舞，首关后可搭配更多组合。');}
    else if(action==='saveLoadout' && this.draft){
      const draft=structuredClone(this.draft),errors=loadoutErrors(draft,this.profile.masteryPoints,availability(this.profile));if(errors.length){this.toast(errors[0]);return;}
      try{this.profile=await this.profiles.update(p=>{p.loadouts=[...p.loadouts.filter(l=>l.heroId!==draft.heroId),draft];return p;});if(this.editingLoadout)this.loadoutPage(false);this.toast('军令已保存，下场对局使用这套构筑。');}catch(error){this.toast(error instanceof Error ? error.message : '保存军令失败');}
    } else if(action==='craft' && value){try{this.profile=await this.profiles.update(p=>craft(p,value));this.collection();this.toast('新遗物已收录。');}catch(error){this.toast(error instanceof Error ? error.message : '制作失败');}}
    else if (action==='hero' && value) { this.selectedHero=value; this.menu(); this.audio.confirm(); }
    else if (action==='difficulty' && value) { this.difficulty=value; this.menu(); }
    else if (action==='menu') { this.current=null; this.menu(); }
    else if (action==='resumeSaved' && this.assetsReady && this.saved) { this.current=new Battle(this.saved.config,validateSnapshot(this.saved)); this.current.state.paused=this.current.state.sides[0].awaitingUpgrade; this.enterBattle(); }
    else if(action==='camera' && value && this.current && this.canNavigate()){if(value==='left' || value==='right')this.camera.pan(value==='left' ? -180 : 180);else this.camera.jump(value as CameraAnchor,this.current);this.paintCamera();}
    else if(action==='cancelAim'){this.selectedSkill=null;this.paintHud(true);}
    else if(action==='mapToggle'){const map=this.root.querySelector<HTMLElement>('.map-controls');if(map){map.hidden=!map.hidden;this.root.querySelector('[data-action=mapToggle]')?.setAttribute('aria-expanded',String(!map.hidden));}}
    else if(action==='heroOrders'){const orders=this.root.querySelector<HTMLElement>('.hero-orders');if(orders){orders.hidden=!orders.hidden;document.getElementById('hero-orb')?.setAttribute('aria-expanded',String(!orders.hidden));}}
    else if(action==='orders'){const orders=document.getElementById('stance-options')!;orders.classList.toggle('expanded');this.root.querySelector('[data-action=orders]')!.setAttribute('aria-expanded',String(orders.classList.contains('expanded')));}
    else if (action==='train' && value) this.dispatch({ type: 'train',side: 0,unitId: value });
    else if (action==='cancel' && value) this.dispatch({ type: 'cancel',side: 0,queueId: Number(value) });
    else if (action==='stance' && value){this.dispatch({ type: 'stance',side: 0,stance: value as 'cover' | 'rush' | 'retreat' });document.getElementById('stance-options')?.classList.remove('expanded');this.root.querySelector('[data-action=orders]')?.setAttribute('aria-expanded','false');}
    else if (action==='skill' && value) this.selectSkill(Number(value));
    else if(action==='ageSpecial')this.selectAgeSpecial();
    else if(action==='item' && value && activeItems[value as ActiveItemId])this.selectActiveItem(value as ActiveItemId);
    else if(action==='researchMenu')this.researchMenu();
    else if(action==='unitHelp')this.unitHelp();
    else if(action==='trainingMenu')this.trainingMenu();
    else if(action==='cancelTraining' && value){this.continue();this.dispatch({type:'cancel',side:0,queueId:Number(value)});this.trainingMenu();}
    else if(action==='buyResearch' && value){this.continue();const result=this.dispatch({type:'research',side:0,researchId:value});if(result?.ok){this.uiEra='';this.paintHud(true);}}
    else if (action==='evolve') this.dispatch({ type: 'evolve',side: 0 });
    else if (action==='upgrade' && value) { const result=this.dispatch({ type: 'upgrade',side: 0,upgradeId: value }); if (result?.ok) { this.hideModal();this.accumulator=0;void this.audio.unlock(); } }
    else if (action==='pause') this.pause();
    else if (action==='continue') this.continue();
    else if (action==='saveMenu') {if(await this.persist()){this.current=null;this.menu();}}
    else if (action==='fort') this.fort();
    else if (action==='buy' && value) { const [slot,turretId]=value.split(':'); this.continue(); this.dispatch({ type: 'turret',side: 0,turretId,slot: Number(slot) }); }
    else if (action==='sell' && value) { this.continue(); this.dispatch({ type: 'sell',side: 0,slot: Number(value) }); }
    else if (action==='unlockSlot') { this.continue(); this.dispatch({ type: 'unlockSlot',side: 0 }); }
    else if (action==='encyclopedia') this.encyclopedia();
    else if (action==='settings') this.settings();
    else if (action==='sound') {this.audio.setMuted(!this.audio.muted);this.profile=await this.profiles.update(p=>{p.settings.muted=this.audio.muted;return p;});this.settings();}
    else if (action==='motion') {this.reducedMotion=!this.reducedMotion;this.profile=await this.profiles.update(p=>{p.settings.reducedMotion=this.reducedMotion;return p;});document.body.classList.toggle('reduce-motion',this.reducedMotion);this.settings();}
    else if (action==='export' && this.current) {
      this.download(this.current.snapshot(),`epoch-rush-${this.current.state.config.matchId}.json`);
    } else if(action==='exportProfile') this.download(this.profile,'epoch-rush-profile.json');
    else if(action==='confirmImport' && this.importCandidate){try{await this.matchSaver.flush();this.profile=await this.profiles.import(this.importCandidate);this.importCandidate=null;this.saved=null;this.audio.setMuted(this.profile.settings.muted);this.reducedMotion=this.profile.settings.reducedMotion;document.body.classList.toggle('reduce-motion',this.reducedMotion);this.menu();this.toast('档案已导入，本机原档案保留为备份。');}catch(error){this.toast(error instanceof Error ? error.message : '档案导入失败');}}
    else if(action==='restoreBackup'){try{await this.profiles.restoreBackup();location.reload();}catch(error){this.toast(error instanceof Error ? error.message : '没有可恢复的完整备份');}}
    else if(action==='reload')location.reload();
    else if (action==='import' || action==='importProfile') {
      const input=document.querySelector<HTMLInputElement>('#save-file')!;
      input.value='';input.onchange=async()=>{
        if(!input.files?.[0])return;
        try{const file=input.files[0];if(file.size>4*1024*1024)throw new Error('文件超出允许大小');const data=JSON.parse(await file.text());
          if(action==='importProfile'){this.importCandidate=validateProfile(data);const p=this.importCandidate;this.modal(`<h2>导入档案预览</h2><p>战役 ${p.clearedMissionIds.length}/15 · 指挥官 ${p.unlockedHeroIds.length}/6<br>遗物 ${p.ownedRelicIds.length}/12 · 传承 ${p.masteryPoints}点<br>原本机档案将保留为备份。</p><div class="modal-actions"><button class="primary" data-action="confirmImport">确认导入</button><button class="text-button" data-action="closeModal">取消</button></div>`);}
          else{const snapshot=validateSnapshot(data);if(snapshot.config.profileId!==this.profile.profileId || (snapshot.config.rewardSequence ?? 0)<=this.profile.rewardJournal.lastCommittedSequence || (snapshot.config.rewardSequence ?? Infinity)>this.profile.rewardJournal.lastReservedSequence)throw new Error('该对局不属于当前档案，或已经结算');await this.matchSaver.flush();await this.storage.writeAtomic('match',snapshot);this.saved=snapshot;this.menu();this.toast('已导入对局，可从营地继续。');}
        }catch(error){this.toast(error instanceof Error ? error.message : '导入失败，原档案已保留');}
      };
      input.click();
    }
  }
  private keyboard(event: KeyboardEvent) {
    if (event.repeat && !['ArrowLeft','ArrowRight'].includes(event.key) || (event.target as HTMLElement)?.matches('input,textarea,select')) return;
    const overlay=document.getElementById('overlay')!;
    if(!overlay.hidden){const buttons=[...overlay.querySelectorAll<HTMLElement>('button:not(:disabled),summary,input,a[href]')];if(event.key==='Tab' && buttons.length){event.preventDefault();const index=buttons.indexOf(document.activeElement as HTMLElement);buttons[index<0 ? event.shiftKey ? buttons.length-1 : 0 : (index+(event.shiftKey ? buttons.length-1 : 1))%buttons.length].focus();return;}if(event.key==='Escape'){event.preventDefault();if(['pause','fort','research','unitHelp','training'].includes(overlay.dataset.kind ?? ''))this.continue();else if(overlay.dataset.kind==='notice')this.hideModal();}return;}
    if (this.page!=='battle' || !this.current || this.current.state.winner!==null) return;
    const key=event.key.toLowerCase();
    if (key==='escape') { event.preventDefault(); if (this.selectedSkill) { this.selectedSkill=null; this.paintHud(true); } else if (this.current.state.paused && !this.current.state.sides[0].awaitingUpgrade) this.continue(); else this.pause(); return; }
    if (this.current.state.paused) return;
    if(['arrowleft','arrowright','home','end'].includes(key)){event.preventDefault();if(key==='home' || key==='end')this.camera.jump(key==='home' ? 'ally' : 'enemy',this.current);else this.camera.pan(key==='arrowleft' ? -130 : 130);this.paintCamera();return;}
    const card=Number(key)-1;
    if (card>=0 && card<5) { event.preventDefault(); const unit=units.filter(item => item.eraId===this.current!.state.sides[0].eraId)[card]; if(unit && unit.heavy && !this.current.heavyUnlocked(0))this.researchMenu();else if(unit)this.dispatch({ type: 'train',side: 0,unitId: unit.id }); }
    if (['q','w','e'].includes(key)) { event.preventDefault(); this.selectSkill(['q','w','e'].indexOf(key)); }
    if (['z','x','c'].includes(key)) { event.preventDefault(); this.dispatch({ type: 'stance',side: 0,stance: ['cover','rush','retreat'][['z','x','c'].indexOf(key)] as 'cover' | 'rush' | 'retreat' }); }
    if (key==='r') { event.preventDefault(); this.dispatch({ type: 'evolve',side: 0 }); }
    if(key==='f'){event.preventDefault();this.selectAgeSpecial();}
    if(key==='g'){event.preventDefault();this.selectActiveItem('war-drum');}
    if(key==='v'){event.preventDefault();this.selectActiveItem('smoke-bomb');}
    if(key==='n'){event.preventDefault();this.selectActiveItem('chrono-crate');}
    if(key==='t'){event.preventDefault();this.researchMenu();}
    if(key==='b'){event.preventDefault();this.fort();}
    if(key==='i'){event.preventDefault();this.unitHelp();}
  }
  private toast(text: string) {
    const element=document.getElementById('toast'); if (!element) return;
    element.textContent=text; element.classList.add('visible'); clearTimeout(this.toastTimer);
    this.toastTimer=window.setTimeout(() => element.classList.remove('visible'),3000);
  }
}
