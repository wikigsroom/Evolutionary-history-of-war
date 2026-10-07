export type Side = 0 | 1;
export type DamageType = 'physical' | 'pierce' | 'blast' | 'energy';
export type Stance = 'cover' | 'rush' | 'retreat';
export type ActiveItemId = 'war-drum' | 'smoke-bomb' | 'chrono-crate';
export type Effects = Record<string, unknown>;
export interface Named { id: string; name: string }
export interface Era extends Named { hpAttackMultiplier: number; costMultiplier: number; incomeMultiplier: number; baseHp: number; nextEvolutionKnowledge: number | null }
export interface Fighter extends Named { hpBase: number; attackBase: number; armor: number; range: number; moveSpeed: number; attackPeriodSec: number; damageType: DamageType; energyResistance: number; weaponId: string }
export interface Unit extends Fighter { eraId: string; role: string; windupSec: number; costBase: number; trainSec: number; heavy: boolean; bountyGold: number; killKnowledge: number; visual: string; special: Effects }
export interface Hero extends Fighter { title: string; signatureSkillId: string; unlockMissionId: string | null; specializationIds: string[]; defaultCommonSkillIds: string[] }
export interface Skill extends Named { category: string; heroId?: string; commandCost: number; cooldownSec: number; damageType: DamageType; damageBase: number; radius: number; maxTargets: number; castRange: number; statusIds: string[]; description: string; targetMode: string; canDamageBase: boolean; effects: Effects }
export interface Talent extends Named { branch: string; tier: number; cost: number; description: string; effects: Effects }
export interface Specialization extends Named { heroId: string; description: string; effects: Effects }
export interface Relic extends Named { rarity: string; description: string; effects: Effects }
export interface Upgrade extends Named { eraId: string; description: string; effects: Effects }
export interface Turret extends Named { eraId: string; mode: string; attackBase: number; damageType: DamageType; costBase: number; range: number; attackPeriodSec: number; maxTargets: number; splashRadius: number }
export interface Weapon extends Named { projectileSpeed: number; hitMode: string; visualFamily: string }
export interface Mission extends Named { chapter: number; startingEraId: string; maximumEraId: string; enemyProfileId: string; enemyStartingGold: number; playerStartingGold: number; teaching: string; boss: boolean; bossModifier: string | null; firstClearRelicId: string | null; firstClearMasteryPoints: number; heroUnlockIds: string[]; bossParameters?: Record<string, unknown>; reinforcements?: {waves:number;periodSec:number;deploySec:number} }
export interface Loadout { heroId: string; specializationId: string; commonSkillIds: string[]; relicIds: string[]; talentIds: string[] }
export interface Build extends Loadout, Named { description: string }
export interface EnemyProfile extends Named { heroId: string; buildId: string; roleWeights: Record<string, number>; description: string }
export interface Status { id: string; until: number; magnitude: number; sourceSide: Side; sourceId: number; charges?: number; nextTick?: number; eraMultiplier?: number }
export interface Shield { hp: number; until: number }
export interface Charge { until: number; destination: number; hitIds: number[]; skillId: string; distance: number; castId: number; raw: number; knockback: number }
export interface Entity {
  id: number; contentId: string; side: Side; kind: 'unit' | 'hero' | 'base' | 'summon'; eraId: string;
  x: number; previousX?:number; hp: number; maxHp: number; radius: number; attack: number; baseAttack: number; attackBonus: number; armor: number; energyResistance: number;
  range: number; speed: number; moveRemainder: number; weaponId: string; damageType: DamageType; heavy: boolean; role: string;
  period: number; windup: number; nextAttack: number; releaseAt: number; targetId: number | null;
  phase: 'idle' | 'move' | 'windup' | 'recover' | 'dead' | 'charge'; statuses: Status[]; shields: Shield[];
  bornTick: number; runDistance: number; rushUntil: number; rushFirstHit: boolean; rushArmed?: boolean; expiresAt?: number;
  staggerImmuneUntil: number; counterReadyAt: number; charge?: Charge; yielding?: boolean; settlementPending?:boolean; garrisoned?: boolean; garrisonHealRemainder?: number; attackStartedAt?: number; attackBuff?: { until: number; bonus: number }; moveBuff?: { until: number; bonus: number };
}
export interface QueueItem { id: number; unitId: string; eraId: string; paid: number; duration: number; remaining: number; advancedBy: string[]; progressUsed: number }
export interface TurretInstance { id: number; contentId: string; paid: number; nextAttack: number; slot: number }
export interface SideState {
  eraId: string; gold: number; knowledge: number; command: number; remainders: [number, number, number];
  loadout: Loadout; stance: Stance; stanceReadyAt: number; queue: QueueItem[]; cooldowns: Record<string, number>;
  upgrades: string[]; unlockedSlots: number; turrets: TurretInstance[]; heroRespawnAt: number;
  rushDeadline: number; rushSpawns: number; awaitingUpgrade: boolean; kills: number; comboHits: number;
  research: Record<string, number>; ageSpecialReadyAt: number;
  activeItems: Record<ActiveItemId, number>; itemCooldowns: Record<ActiveItemId, number>;
}
export interface Hit {
  sourceId: number; side: Side; targetId: number; raw: number; damageType: DamageType; projectile: boolean;
  skillId?: string; castId?: number; conditional?: number; statuses?: Status[]; displacement?: { center?: number; distance: number };
  conductive?: boolean; isRush?: boolean; attackerRole?:string; attackerHeavy?:boolean; attackerKind?:Entity['kind'];
}
export interface Projectile { id: number; sourceId: number; side: Side; x: number; previousX: number; targetId: number; speed: number; moveRemainder: number; expiresAt: number; hit: Hit; splash: number; maxTargets: number; weaponId: string; suppress: boolean; direction: number; pierceRemaining: number; hitIds: number[] }
export interface ScheduledSkill { id: number; side: Side; sourceId: number; skillId: string; x: number; targetId?: number; due: number; remaining: number; spacing: number; eraMultiplier: number; visited: number[]; sourceSnapshot: Entity; refunded?: boolean; fieldUntil?:number; fieldDamage?:number }
export interface BattleEvent { id: number; tick: number; type: string; x: number; side: Side; targetId?: number; sourceId?:number; weaponId?:string; damageType?:DamageType; amount?: number; absorbed?: number; skillId?: string; text?: string; fromX?: number }
export interface MatchConfig { mode: 'campaign' | 'standard' | 'trial' | 'challenge'; heroEnabled?: boolean; loadout: Loadout; enemyLoadout: Loadout; enemyProfileId: string; difficultyId: string; missionId?: string; startingEraId?: string; maximumEraId?: string; seed: number; matchId: string; profileId?: string; rewardSequence?: number; lootSeed?: number }
export interface AgeStrike { id: number; side: Side; eraId: string; x: number; due: number; remaining: number }
export interface BattleState { contentVersion: string; config: MatchConfig; tick: number; nextId: number; rng: number; paused: boolean; winner: Side | 'draw' | null; sides: [SideState, SideState]; entities: Entity[]; projectiles: Projectile[]; scheduledSkills: ScheduledSkill[]; ageStrikes: AgeStrike[]; pendingHits: Hit[]; events: BattleEvent[]; processedActionIds: number[]; lastActionSequence:number; bossThresholds: number[]; bossPending: number; castTargets: Record<number, { until: number; ids: number[] }> }
export type Action =
  | { type: 'train'; side: Side; unitId: string }
  | { type: 'cancel'; side: Side; queueId: number }
  | { type: 'stance'; side: Side; stance: Stance }
  | { type: 'evolve'; side: Side }
  | { type: 'research'; side: Side; researchId: string }
  | { type: 'ageSpecial'; side: Side; x: number }
  | { type: 'upgrade'; side: Side; upgradeId: string }
  | { type: 'turret'; side: Side; turretId: string; slot: number }
  | { type: 'sell'; side: Side; slot: number }
  | { type: 'unlockSlot'; side: Side }
  | { type: 'cast'; side: Side; skillId: string; x: number; targetId?: number }
  | { type: 'item'; side: Side; itemId: ActiveItemId; x?: number };
export const value = (effects: Effects, key: string, fallback = 0): number => typeof effects[key] === 'number' ? effects[key] as number : fallback;
export const ticks = (seconds: number) => Math.ceil(seconds * 30);
export const position = (worldX: number) => Math.round(worldX * 100);
export const worldX = (entity: { x: number }) => entity.x / 100;
export const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));
