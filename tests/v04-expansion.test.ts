import { describe, expect, test } from 'vitest';
import { Battle } from '../src/core/battle';
import { builds } from '../src/content/catalog';
import { position } from '../src/core/types';
import { validateSnapshot } from '../src/services/save-validation';

const game = (startingEraId = 'A1') => new Battle({
  matchId: 'V04-EXPANSION', mode: 'trial', heroEnabled: false, seed: 77,
  loadout: builds[0], enemyLoadout: builds[2], enemyProfileId: 'AP01', difficultyId: 'D02',
  startingEraId, maximumEraId: 'A5',
});

describe('主动道具与特种军团', () => {
  test('战鼓令同时强化前线并推进训练队列，消耗一枚并进入冷却', () => {
    const battle = game();
    battle.state.sides[0].gold = 400000;
    expect(battle.act({ type: 'train', side: 0, unitId: 'U11' }).ok).toBe(true);
    const queue = battle.state.sides[0].queue[0];
    const before = queue.remaining;
    expect(battle.act({ type: 'item', side: 0, itemId: 'war-drum' }).ok).toBe(true);
    expect(queue.remaining).toBeLessThan(before);
    expect(battle.state.sides[0].activeItems['war-drum']).toBe(1);
    expect(battle.state.sides[0].itemCooldowns['war-drum']).toBeGreaterThan(0);
    expect(battle.state.events.some(event => event.type === 'itemCast' && event.text === 'war-drum')).toBe(true);
  });

  test('烟幕罐按落点给范围内敌军施加减速，落点越界会被拒绝', () => {
    const battle = game();
    const enemy = battle.spawn(1, 'U11', 'A1'); enemy.x = position(520);
    expect(battle.act({ type: 'item', side: 0, itemId: 'smoke-bomb', x: 520 }).ok).toBe(true);
    expect(enemy.statuses.some(status => status.id === 'ST03')).toBe(true);
    expect(battle.act({ type: 'item', side: 0, itemId: 'smoke-bomb', x: 520 }).ok).toBe(false);
    expect(battle.act({ type: 'item', side: 0, itemId: 'smoke-bomb', x: 20 }).ok).toBe(false);
  });

  test('时序补给增加军资军令并能安全恢复存档', () => {
    const battle = game();
    const gold = battle.state.sides[0].gold, command = battle.state.sides[0].command;
    expect(battle.act({ type: 'item', side: 0, itemId: 'chrono-crate' }).ok).toBe(true);
    expect(battle.state.sides[0].gold).toBe(gold + 65000);
    expect(battle.state.sides[0].command).toBe(command + 15000);
    expect(validateSnapshot(battle.snapshot())).toEqual(battle.state);
  });

  test('五个时代各增加一名特种单位，支援光环会改变真实战斗状态', () => {
    const cases: Array<[string, string]> = [['A1', 'U15'], ['A2', 'U25'], ['A3', 'U35'], ['A4', 'U45'], ['A5', 'U55']];
    for (const [era, unitId] of cases) {
      const battle = game(era), unit = battle.spawn(0, unitId, era);
      battle.state.sides[0].gold = 1000000;
      expect(unit.contentId).toBe(unitId);
      expect(battle.act({ type: 'train', side: 0, unitId })).toEqual({ok:true});
    }
    const medic = game('A4'), target = medic.spawn(0, 'U11', 'A4'), healer = medic.spawn(0, 'U45', 'A4');
    healer.x = target.x = position(420); target.hp = 1;
    medic.step();
    expect(target.hp).toBeGreaterThan(1);
    const engineer = game('A5'), ally = engineer.spawn(0, 'U11', 'A5'), field = engineer.spawn(0, 'U55', 'A5');
    field.x = ally.x = position(420); engineer.step(60);
    expect(ally.shields.length).toBeGreaterThan(0);
  });
});
