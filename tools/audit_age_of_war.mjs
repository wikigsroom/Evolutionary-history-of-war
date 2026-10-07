import { createServer } from 'vite';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

// Offline diagnostic fixtures: these do not open the game, change a profile,
// unlock content or represent an end-to-end playthrough of either reference game.
const server = await createServer({ configFile: false, appType: 'custom', logLevel: 'error', server: { middlewareMode: true } });
try {
  const { Battle } = await server.ssrLoadModule('/src/core/battle.ts');
  const { updateCombat, damageFor } = await server.ssrLoadModule('/src/core/combat.ts');
  const { catalog, units, eras, rules } = await server.ssrLoadModule('/src/content/catalog.ts');
  const { fighterPose } = await server.ssrLoadModule('/src/presentation/motion.ts');
  const loadout = { heroId: 'H01', specializationId: 'P011', commonSkillIds: ['S01', 'S02'], relicIds: [], talentIds: ['T11', 'T12'] };
  const match = (overrides = {}) => new Battle({ matchId: 'AUDIT-FIXTURE', mode: 'trial', seed: 1234, loadout, enemyLoadout: { ...loadout, heroId: 'H03', specializationId: 'P031' }, enemyProfileId: 'AP01', difficultyId: 'D02', ...overrides });
  const baseOnly = (battle) => { battle.state.entities = battle.state.entities.filter(e => e.kind === 'base'); battle.state.events = []; return battle; };
  const describe = e => ({ id: e.id, contentId: e.contentId, x: e.x / 100, radius: e.radius, laneById: e.id % 3, phase: e.phase, targetId: e.targetId });
  const overlaps = entities => entities.flatMap((a, i) => entities.slice(i + 1).flatMap(b => {
    const penetration = a.radius + b.radius - Math.abs(a.x - b.x) / 100;
    return penetration > 0 ? [{ ids: [a.id, b.id], penetration }] : [];
  }));

  const mission = match({ missionId: 'M01' });
  mission.state.sides[0].knowledge = 160000;
  const missionEvolution = { fixture: 'Grant the first evolution threshold, then invoke the real evolve action in M01.', start: mission.state.sides[0].eraId, maximum: mission.maxEraId, result: mission.act({ type: 'evolve', side: 0 }) };

  const idle = baseOnly(match());
  idle.step(3200);
  const idleEvolution = { fixture: 'Only two bases, trial AI disabled, no units or deaths.', elapsedSeconds: idle.state.tick / 30, kills: idle.state.sides[0].kills, knowledge: idle.state.sides[0].knowledge / 1000, gold: idle.state.sides[0].gold / 1000, result: idle.act({ type: 'evolve', side: 0 }), resultingEra: idle.state.sides[0].eraId };

  const marching = baseOnly(match());
  const leader = marching.spawn(0, 'U11', 'A1'), follower = marching.spawn(0, 'U11', 'A1'), blocker = marching.spawn(1, 'U11', 'A1');
  leader.x = 60000; follower.x = 54000; blocker.x = 66000;
  for (const e of [leader, follower, blocker]) { e.hp = e.maxHp = 100000; e.baseAttack = 0; }
  blocker.speed = 0;
  const beforeMarch = [leader, follower].map(describe);
  marching.step(90);
  const overtaking = { fixture: 'Front unit fights a stationary enemy; its allied follower has a different ID remainder. High HP and zero attack prevent fixture deaths.', before: beforeMarch, after: [leader, follower].map(describe), bodyOverlaps: overlaps([leader, follower]) };

  const exit = baseOnly(match());
  const exitBlocker = exit.spawn(1, 'U11', 'A1');
  exitBlocker.x = 20000; exitBlocker.speed = 0; exitBlocker.hp = exitBlocker.maxHp = 100000; exitBlocker.baseAttack = 0;
  const paidOrders = Array.from({ length: 3 }, () => exit.act({ type: 'train', side: 0, unitId: 'U11' }));
  exit.step(150);
  const trained = exit.living(0).filter(e => e.kind === 'unit');
  const exitOverlap = { fixture: 'Enemy holds the base exit at x=200. Three normal paid training orders run through the production queue.', paidOrders, remainingQueue: exit.state.sides[0].queue.length, units: trained.map(describe), bodyOverlaps: overlaps(trained) };

  const contacts = baseOnly(match());
  const attackers = Array.from({ length: 3 }, () => contacts.spawn(0, 'U11', 'A1'));
  const target = contacts.spawn(1, 'U11', 'A1');
  for (const e of attackers) e.x = 60000;
  target.x = 64000;
  updateCombat(contacts);
  const stackedAttacks = { fixture: 'Three allied melee units begin at the same coordinate, within reach of one enemy.', units: attackers.map(describe), concurrentWindups: attackers.filter(e => e.phase === 'windup' && e.targetId === target.id).length, bodyOverlaps: overlaps(attackers), configuredContactCap: rules.world.maxMeleeContacts };

  const death = baseOnly(match({ mode: 'standard' }));
  const casualty = death.spawn(0, 'U11', 'A1');
  death.kill(casualty);
  const deathExperience = { fixture: 'Call the real death handler for one player unit, without advancing time.', ownerKnowledge: death.state.sides[0].knowledge / 1000, opponentKnowledge: death.state.sides[1].knowledge / 1000 };

  const generation = match();
  const oldUnit = generation.spawn(0, 'U11', 'A1');
  generation.act({ type: 'train', side: 0, unitId: 'U12' });
  generation.state.sides[0].knowledge = 160000;
  generation.act({ type: 'evolve', side: 0 });
  const generationChange = { fixture: 'A living old unit and a paid old training item exist at evolution.', currentEra: generation.state.sides[0].eraId, trainedCatalog: units.filter(u => u.eraId === generation.state.sides[0].eraId).map(u => u.id), existingUnit: { contentId: oldUnit.contentId, eraId: oldUnit.eraId }, paidQueue: generation.state.sides[0].queue.map(q => ({ unitId: q.unitId, eraId: q.eraId })), pausesForChoice: generation.state.paused, hero: { contentId: generation.hero(0).contentId, eraId: generation.hero(0).eraId } };

  const counterBattle = baseOnly(match());
  const source = counterBattle.spawn(0, 'U11', 'A1');
  const lightRoleDamage = ['U11', 'U12', 'U13'].map(unitId => {
    const victim = counterBattle.spawn(1, unitId, 'A1'); victim.armor = 0;
    return { targetRole: victim.role, damage: damageFor(counterBattle, { sourceId: source.id, side: 0, targetId: victim.id, raw: 100, damageType: 'physical', projectile: false, conductive: false }, victim) };
  });

  const actor = match().hero(0);
  actor.phase = 'windup'; actor.releaseAt = 5;
  const poseContext = { now: 4, releasedAt: -100, hitAt: -100, hitDirection: 1, skillAt: -100, motionClass: 'biped' };
  const motionReduction = { fixture: 'Identical attacking actor and tick; toggle only reducedMotion.', normalParts: Object.keys(fighterPose(actor, { ...poseContext, reducedMotion: false }).parts), reducedParts: Object.keys(fighterPose(actor, { ...poseContext, reducedMotion: true }).parts) };

  const report = {
    inspectedOn: '2026-10-05', inspectedGameVersion: '0.2.0', evidenceKind: 'offline-controlled-fixtures',
    boundary: 'These results verify current project rules only. They are not fixes, normal gameplay recordings, quality approval, or reference-game playthroughs.',
    missionEvolution, idleEvolution, overtaking, exitOverlap, stackedAttacks, deathExperience, generationChange, lightRoleDamage, motionReduction,
    eraRoster: eras.map(e => ({ id: e.id, name: e.name, units: units.filter(u => u.eraId === e.id).map(u => ({ id: u.id, name: u.name, role: u.role, heavy: u.heavy, weapon: u.weaponId, range: u.range, special: u.special })) })),
  };
  const output = resolve('output/qa/core-audit-2026-10-05/core-fixtures.json');
  await mkdir(resolve('output/qa/core-audit-2026-10-05'), { recursive: true });
  await writeFile(output, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ output, missionEvolution, idleEvolution, overtaking, exitOverlap, stackedAttacks, deathExperience, generationChange, lightRoleDamage, motionReduction }, null, 2));
} finally {
  await server.close();
}
