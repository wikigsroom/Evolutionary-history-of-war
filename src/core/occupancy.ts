import { rules } from '../content/catalog';
import { fighterProfile } from './fighter-profiles';
import { clamp, position, type BattleState, type Entity, type Side } from './types';

export const BODY_GAP = 4;
export const grounded = (entity: Entity) => entity.hp > 0 && entity.kind !== 'base' && !entity.garrisoned && !entity.charge && !entity.yielding;
export const bounds = (radius: number) => [position(rules.world.basePositions[0] + 55 + radius + BODY_GAP), position(rules.world.basePositions[1] - 55 - radius - BODY_GAP)] as const;
export function spawnX(side: Side, contentId: string) {
  const radius = fighterProfile(contentId).radius;
  return bounds(radius)[side];
}
export function spaceFree(state: BattleState, x: number, radius: number, except?: number) {
  const [min, max] = bounds(radius);
  return x >= min && x <= max && state.entities.every(other => !grounded(other) || other.id === except || Math.abs(other.x - x) >= position(radius + other.radius + BODY_GAP));
}
// Every legal gap is examined, including the gap behind the army. No ID-based lanes.
export function nearestSpace(state: BattleState, x: number, radius: number, except?: number): number | undefined {
  const [min, max] = bounds(radius);
  const candidates = [clamp(x, min, max), min, max];
  for (const other of state.entities.filter(grounded)) if (other.id !== except) {
    candidates.push(other.x - position(radius + other.radius + BODY_GAP), other.x + position(radius + other.radius + BODY_GAP));
  }
  return candidates.filter(candidate => spaceFree(state, candidate, radius, except)).sort((a, b) => Math.abs(a - x) - Math.abs(b - x) || a - b)[0];
}
// Spawn placement must include bodies that are currently yielding or charging:
// those bodies still occupy pixels even though movement collision treats them
// as transient. Without this distinction a newly completed order could appear
// inside a withdrawing commander and create a permanent overlap.
export function spawnSpaceFree(state: BattleState, x: number, radius: number, side: Side, except?: number, ignoreOwnUnits = false, keepOwnUnit?: number) {
  const [min, max] = bounds(radius);
  return x >= min && x <= max && state.entities.every(other => !other.hp || other.kind === 'base' || other.garrisoned || other.id === except || (ignoreOwnUnits && other.side === side && other.kind === 'unit' && other.id !== keepOwnUnit) || Math.abs(other.x - x) >= position(radius + other.radius + BODY_GAP));
}
export function nearestSpawnSpace(state: BattleState, x: number, radius: number, side: Side, except?: number, keepProductionOrder = true): number | undefined {
  let [min, max] = bounds(radius);
  // New soldiers enter behind every surviving soldier. A protected space
  // inside their own capital remains usable when an enemy reaches the gate.
  if (keepProductionOrder) for (const other of state.entities) {
    if (other.hp <= 0 || other.side !== side || other.kind !== 'unit' || other.garrisoned || other.id === except) continue;
    if (side === 0) max = Math.min(max, other.x - position(radius + other.radius + BODY_GAP));
    else min = Math.max(min, other.x + position(radius + other.radius + BODY_GAP));
  }
  // When the production lane is full, keep the completed order queued. Falling
  // back to the front of the line would reverse production order and create
  // overlapping bodies once the formation pass tries to restore the line.
  if (min > max) return undefined;
  const candidates = [clamp(x, min, max), min, max];
  for (const other of state.entities.filter(entity => entity.hp > 0 && entity.kind !== 'base' && !entity.garrisoned)) if (other.id !== except) {
    candidates.push(other.x - position(radius + other.radius + BODY_GAP), other.x + position(radius + other.radius + BODY_GAP));
  }
  return candidates.filter(candidate => candidate >= min && candidate <= max && spawnSpaceFree(state, candidate, radius, side, except)).sort((a, b) => Math.abs(a - x) - Math.abs(b - x) || a - b)[0];
}
export function constrainedGoal(state: BattleState, entity: Entity, goal: number): number {
  const [min, max] = bounds(entity.radius);
  goal = clamp(goal, min, max);
  if (entity.yielding || entity.charge) return goal;
  const direction = Math.sign(goal - entity.x);
  for (const other of state.entities) {
    // A covering commander is a rear-line body. Let a newly produced unit
    // pass its old position so the commander cannot seal the recruitment lane.
    if (!grounded(other) || other.id === entity.id || (entity.kind === 'unit' && other.kind === 'hero' && other.side === entity.side && state.sides[entity.side].stance === 'cover') || (other.x - entity.x) * direction <= 0) continue;
    const stop = other.x - direction * position(entity.radius + other.radius + BODY_GAP);
    goal = direction > 0 ? Math.min(goal, Math.max(entity.x, stop)) : Math.max(goal, Math.min(entity.x, stop));
  }
  return goal;
}
export function legalContact(state: BattleState, entity: Entity, target: Entity): boolean {
  const profile = fighterProfile(entity.contentId);
  if (entity.range >= 100 && !profile.overShoulder) return true;
  const allies = state.entities.filter(other => grounded(other) && other.side === entity.side && other.id !== entity.id && (other.x - entity.x) * (target.x - entity.x) > 0 && Math.abs(other.x - entity.x) < Math.abs(target.x - entity.x));
  return allies.length === 0 || (profile.overShoulder && allies.length === 1);
}
export function displace(state: BattleState, entity: Entity, delta: number) {
  entity.x = constrainedGoal(state, entity, entity.x + delta);
}
export function settleExceptionalMove(state: BattleState, entity: Entity) {
  const x = nearestSpace(state, entity.x, entity.radius, entity.id);
  if (x !== undefined) { entity.x = x; entity.yielding = false; delete entity.settlementPending; }
  else {entity.yielding=true;entity.settlementPending=true;}
}
