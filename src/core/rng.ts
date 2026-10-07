export function nextRandom(state: number): number {
  let x = state || 0x9e3779b9;
  x ^= x << 13;
  x ^= x >>> 17;
  x ^= x << 5;
  return x >>> 0;
}
export function boundedRandom(seed: number, bound: number): { seed: number; value: number } {
  if (!Number.isInteger(bound) || bound < 1 || bound > 0x100000000) throw new Error('非法随机区间');
  const limit = Math.floor(0x100000000 / bound) * bound;
  let state = seed;
  do { state = nextRandom(state); } while (state >= limit);
  return { seed: state, value: state % bound };
}
