import { catalog } from '../content/catalog';
import { position, ticks, worldX } from './types';
import type { Battle } from './battle';
export const ageSpecials = {
  A1: { name: '陨石雨', cost: 25, cooldown: 26, radius: 145, damage: 75, pulses: 3, type: 'blast' },
  A2: { name: '烈焰齐射', cost: 40, cooldown: 26, radius: 170, damage: 85, pulses: 3, type: 'pierce' },
  A3: { name: '王国箭雨', cost: 60, cooldown: 24, radius: 195, damage: 90, pulses: 4, type: 'pierce' },
  A4: { name: '空袭轰炸', cost: 90, cooldown: 28, radius: 215, damage: 125, pulses: 3, type: 'blast' },
  A5: { name: '轨道审判', cost: 130, cooldown: 30, radius: 240, damage: 125, pulses: 3, type: 'energy' },
} as const;
export function updateAgeSpecials(battle: Battle) {
  for (const strike of battle.state.ageStrikes) {
    if (strike.due > battle.state.tick || strike.remaining <= 0) continue;
    const special = ageSpecials[strike.eraId as keyof typeof ageSpecials];
    const targets = battle.living(strike.side === 0 ? 1 : 0).filter(target => target.kind !== 'base' && Math.abs(target.x - position(strike.x)) <= position(special.radius)).sort((a, b) => Math.abs(a.x - position(strike.x)) - Math.abs(b.x - position(strike.x)) || a.id - b.id).slice(0, 6);
    const castId = battle.id();
    for (const target of targets) battle.state.pendingHits.push({ sourceId: battle.base(strike.side).id, side: strike.side, targetId: target.id, raw: special.damage * catalog.eras[strike.eraId].hpAttackMultiplier, damageType: special.type, projectile: false, conductive: false, castId });
    battle.event('ageImpact', strike.x, strike.side, { text: strike.eraId, amount: special.radius });
    for (const target of targets) battle.event('ageTrail', worldX(target), strike.side, { text: strike.eraId, targetId: target.id });
    strike.remaining--; strike.due += ticks(.28);
  }
  battle.state.ageStrikes = battle.state.ageStrikes.filter(strike => strike.remaining > 0);
}
