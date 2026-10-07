import { catalog } from '../content/catalog';
import type { SideState } from './types';
export interface Research { id: string; name: string; icon: string; role: string; max: number; price: number; description: string }
export const researches: Research[] = [
  { id: 'front-attack', name: '步兵锋刃', icon: 'sword', role: 'front', max: 2, price: 75, description: '每级使步兵攻击提高 15%。' },
  { id: 'front-armor', name: '步兵甲胄', icon: 'shield', role: 'front', max: 3, price: 60, description: '每级增加步兵护甲 10 点。' },
  { id: 'ranged-attack', name: '支援火力', icon: 'target', role: 'ranged', max: 2, price: 85, description: '每级使支援兵攻击提高 15%。' },
  { id: 'ranged-range', name: '远程校准', icon: 'scope', role: 'ranged', max: 3, price: 70, description: '每级增加支援兵射程 25。' },
  { id: 'anti-attack', name: '破甲技术', icon: 'pierce', role: 'anti_armor', max: 2, price: 85, description: '每级使反装甲兵攻击提高 15%。' },
  { id: 'heavy-unlock', name: '重型军团', icon: 'heavy', role: 'heavy', max: 1, price: 105, description: '开放当前及后续时代的重型兵种。' },
  { id: 'heavy-attack', name: '重型冲击', icon: 'blast', role: 'heavy', max: 2, price: 115, description: '每级使重型兵攻击提高 15%。' },
  { id: 'tower-attack', name: '炮塔强化', icon: 'tower', role: 'tower', max: 2, price: 95, description: '每级使基地炮塔攻击提高 15%。' },
];
export const researchById = Object.fromEntries(researches.map(row => [row.id, row]));
export const researchLevel = (player: SideState, id: string) => player.research[id] ?? 0;
export const researchCost = (player: SideState, id: string) => Math.ceil(researchById[id].price * (1 + researchLevel(player, id) * .65) * catalog.eras[player.eraId].costMultiplier);
export const attackResearch = (player: SideState, role: string) => researchLevel(player, `${role === 'anti_armor' ? 'anti' : role}-attack`) * .15;
