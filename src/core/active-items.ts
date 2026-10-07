import type { ActiveItemId } from './types';
export type { ActiveItemId } from './types';

/**
 * Small, readable combat verbs that sit beside the era strike. They are
 * deliberately limited by charges and cooldowns so the player makes a few
 * meaningful timing decisions instead of opening another menu every wave.
 */
export interface ActiveItem {
  id: ActiveItemId;
  name: string;
  shortName: string;
  description: string;
  icon: string;
  cooldownSec: number;
  charges: number;
  targetMode: 'self' | 'point';
  radius?: number;
}

export const activeItems: Record<ActiveItemId, ActiveItem> = {
  'war-drum': {
    id: 'war-drum', name: '战鼓令', shortName: '鼓',
    description: '全军加速并提前推进一项训练队列。', icon: 'drum',
    cooldownSec: 22, charges: 2, targetMode: 'self',
  },
  'smoke-bomb': {
    id: 'smoke-bomb', name: '烟幕罐', shortName: '烟',
    description: '在战线制造烟幕，减速范围内敌军。', icon: 'smoke',
    cooldownSec: 28, charges: 2, targetMode: 'point', radius: 135,
  },
  'chrono-crate': {
    id: 'chrono-crate', name: '时序补给', shortName: '补',
    description: '立即获得军资与军令，并压缩当前训练队列。', icon: 'crate',
    cooldownSec: 30, charges: 3, targetMode: 'self',
  },
};

export const activeItemIds = Object.keys(activeItems) as ActiveItemId[];
export const defaultActiveItems = (): Record<ActiveItemId, number> => ({
  'war-drum': activeItems['war-drum'].charges,
  'smoke-bomb': activeItems['smoke-bomb'].charges,
  'chrono-crate': activeItems['chrono-crate'].charges,
});
export const defaultItemCooldowns = (): Record<ActiveItemId, number> => ({
  'war-drum': 0,
  'smoke-bomb': 0,
  'chrono-crate': 0,
});
