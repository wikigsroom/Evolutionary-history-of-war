import { describe, expect, test } from 'vitest';
import { Battle } from '../src/core/battle';
import { type MatchConfig, type Side } from '../src/core/types';

const loadout = { heroId: 'H01', specializationId: 'P011', commonSkillIds: ['S01', 'S02'], relicIds: [], talentIds: ['T11', 'T12'] };

function match(overrides: Partial<MatchConfig> = {}) {
  return new Battle({
    matchId: 'ERA-INDEPENDENCE',
    mode: 'standard',
    seed: 90210,
    loadout,
    enemyLoadout: { ...loadout, heroId: 'H03', specializationId: 'P031' },
    enemyProfileId: 'AP01',
    difficultyId: 'D02',
    ...overrides,
  });
}

describe('双方时代独立推进', () => {
  test.each([[0, 1], [1, 0]] as [Side, Side][])('一方手动进化不会改变另一方时代、基地或英雄 (%s → %s)', (evolving, other) => {
    const battle = match();
    const otherBase = battle.base(other);
    const otherHero = battle.hero(other)!;
    battle.state.sides[evolving].knowledge = 85_000;

    expect(battle.state.sides.map(side => side.eraId)).toEqual(['A1', 'A1']);
    expect(battle.act({ type: 'evolve', side: evolving }).ok).toBe(true);

    expect(battle.state.sides[evolving].eraId).toBe('A2');
    expect(battle.state.sides[other].eraId).toBe('A1');
    expect(battle.base(evolving).eraId).toBe('A2');
    expect(otherBase.eraId).toBe('A1');
    expect(otherHero.eraId).toBe('A1');
    battle.step(30);
    expect(battle.state.sides[other].eraId).toBe('A1');
  });

  test('敌方只会因自己的经验进化，不能把进化传给我方', () => {
    const battle = match();
    battle.state.sides[0].knowledge = 0;
    battle.state.sides[1].knowledge = 85_000;

    battle.step(30);

    expect(battle.state.sides.map(side => side.eraId)).toEqual(['A1', 'A2']);
    expect(battle.base(0).eraId).toBe('A1');
    expect(battle.base(1).eraId).toBe('A2');
    expect(battle.state.events.filter(event => event.type === 'evolve').map(event => event.side)).toEqual([1]);
  });
});
