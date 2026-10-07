import { catalog, rules } from '../content/catalog';
import { clamp, value, type Effects, type Loadout } from './types';

export function loadoutErrors(loadout: Loadout, budget = 6, availability?: { heroes: string[]; skills: string[]; relics: string[] }): string[] {
  const errors: string[] = [];
  if (!catalog.heroes[loadout.heroId] || availability && !availability.heroes.includes(loadout.heroId)) errors.push('角色尚未解锁');
  if (catalog.specializations[loadout.specializationId]?.heroId !== loadout.heroId) errors.push('专精不属于该角色');
  if (loadout.commonSkillIds.length !== 2 || new Set(loadout.commonSkillIds).size !== 2 || loadout.commonSkillIds.some(id => catalog.skills[id]?.category !== 'common' || availability && !availability.skills.includes(id))) errors.push('需要两个不同的已解锁通用技能');
  if (loadout.relicIds.length > 2 || new Set(loadout.relicIds).size !== loadout.relicIds.length || loadout.relicIds.some(id => !catalog.relics[id] || availability && !availability.relics.includes(id))) errors.push('遗物需已拥有且不可重复，最多两件');
  if (new Set(loadout.talentIds).size !== loadout.talentIds.length || loadout.talentIds.some(id => !catalog.talents[id])) errors.push('天赋配置无效');
  const points: Record<string, number> = {};
  let spent = 0;
  for (const id of [...loadout.talentIds].sort((a,b) => (catalog.talents[a]?.tier ?? 0) - (catalog.talents[b]?.tier ?? 0))) {
    const talent = catalog.talents[id];
    if (!talent) continue;
    if ((points[talent.branch] ?? 0) < rules.mastery.tiersRequirePoints[talent.tier - 1]) errors.push(`${talent.name}需要同路线前层天赋`);
    spent += talent.cost;
    points[talent.branch] = (points[talent.branch] ?? 0) + talent.cost;
  }
  if (spent > budget) errors.push(`传承点不足：已用${spent}，可用${budget}`);
  return [...new Set(errors)];
}

export function fitLoadout(template: Loadout, budget: number, availableSkills: string[], availableRelics: string[]): Loadout {
  const commonSkillIds = template.commonSkillIds.filter(id => availableSkills.includes(id));
  for (const id of [...availableSkills].sort()) if (commonSkillIds.length < 2 && !commonSkillIds.includes(id)) commonSkillIds.push(id);
  const fitted: Loadout = { ...template, commonSkillIds, relicIds: template.relicIds.filter(id => availableRelics.includes(id)), talentIds: [] };
  for (const id of template.talentIds) {
    const candidate = { ...fitted, talentIds: [...fitted.talentIds, id] };
    if (loadoutErrors(candidate, budget).length === 0) fitted.talentIds.push(id);
  }
  return fitted;
}

export function effects(loadout: Loadout, runUpgrades: string[] = []): Effects {
  const result: Effects = {};
  for (const id of [...loadout.talentIds, ...loadout.relicIds, ...runUpgrades]) {
    const item = catalog.talents[id] ?? catalog.relics[id] ?? catalog.upgrades[id];
    if (!item) throw new Error(`未知构筑项：${id}`);
    for (const [key, field] of Object.entries(item.effects)) {
      if (typeof field === 'number') result[key] = value(result, key) + field;
      else if (typeof field === 'object' && field !== null) result[key] = { ...(result[key] as object ?? {}), ...field as object };
      else result[key] = field;
    }
  }
  return result;
}
export const capped = (modifiers: Effects, key: keyof typeof rules.caps) => clamp(value(modifiers, key), -0.9, rules.caps[key]);
