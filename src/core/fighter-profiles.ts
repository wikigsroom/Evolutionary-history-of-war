// Footprints describe bodies, not the long weapons, capes or shadows in the art.
// The same profile supplies the renderer's contact and muzzle sockets.
import animationManifest from '../content/animation-manifest.json';
export interface FighterProfile {
  radius: number; height: number; muzzle: [number, number]; hit: [number, number];
  overShoulder: boolean; material: 'flesh' | 'wood' | 'metal'; family: string;
}
export const visualActorId = (id: string) => id;
const infantry = (family: string, extra: Partial<FighterProfile> = {}): FighterProfile => ({ radius: 16, height: 96, muzzle: [36, 57], hit: [0, 54], overShoulder: false, material: 'flesh', family, ...extra });
export const fighterProfiles: Record<string, FighterProfile> = {
  U11: infantry('shield'), U12: infantry('throw', { radius: 14, muzzle: [24, 72] }),
  U13: infantry('spear', { overShoulder: true, muzzle: [63, 55] }),
  U14: infantry('mounted', { radius: 36, height: 122, muzzle: [56, 73] }),
  U21: infantry('shield'), U22: infantry('bow', { radius: 14, muzzle: [29, 62] }),
  U23: infantry('spear', { overShoulder: true, muzzle: [65, 55] }),
  U24: infantry('mounted', { radius: 40, height: 116, material: 'wood', muzzle: [54, 67] }),
  U31: infantry('shield', { material: 'metal' }), U32: infantry('bow', { radius: 14, muzzle: [29, 62] }),
  U33: infantry('spear', { overShoulder: true, muzzle: [68, 55] }),
  U34: infantry('mounted', { radius: 36, height: 126, material: 'metal', muzzle: [62, 80] }),
  U41: infantry('gun', { material: 'metal', muzzle: [35, 61] }),
  U42: infantry('gun', { radius: 14, muzzle: [39, 63] }),
  U43: infantry('gun', { radius: 17, muzzle: [40, 69] }),
  U44: infantry('cannon', { radius: 42, height: 98, muzzle: [63, 56], hit: [0, 43], material: 'metal' }),
  U51: infantry('shield', { material: 'metal', muzzle: [43, 65] }),
  U52: infantry('gun', { radius: 15, muzzle: [42, 65], material: 'metal' }),
  U53: infantry('spear', { radius: 18, overShoulder: true, material: 'metal', muzzle: [70, 59] }),
  U54: infantry('mech', { radius: 36, height: 128, muzzle: [46, 87], hit: [0, 76], material: 'metal' }),
  U15: infantry('drum', { radius: 18, height: 102, muzzle: [24, 52] }),
  U25: infantry('shield', { radius: 19, height: 108, muzzle: [42, 64], material: 'wood' }),
  U35: infantry('bow', { radius: 16, height: 100, muzzle: [48, 64] }),
  U45: infantry('gun', { radius: 15, height: 100, muzzle: [42, 62], material: 'metal' }),
  U55: infantry('mech', { radius: 20, height: 112, muzzle: [44, 70], material: 'metal' }),
  H01: infantry('shield', { radius: 20, height: 120, muzzle: [42, 69] }),
  H02: infantry('bow', { radius: 18, height: 120, muzzle: [36, 76] }),
  H03: infantry('shield', { radius: 23, height: 126, material: 'metal', muzzle: [45, 70] }),
  H04: infantry('gun', { radius: 20, height: 120, muzzle: [43, 73] }),
  H05: infantry('mech', { radius: 19, height: 122, muzzle: [40, 81] }),
  H06: infantry('bow', { radius: 19, height: 120, muzzle: [37, 74] }),
  'summon-H04': infantry('cannon', { radius: 27, height: 74, muzzle: [42, 45], hit: [0, 34], material: 'metal' }),
};
type SocketReview = {review?:string;muzzle?:[number,number];hit?:[number,number];bodyRadius?:number};
const socketReviews=animationManifest.actors as unknown as Record<string,SocketReview>;
const inspectPending=import.meta.env.DEV && typeof location!=='undefined' && new URLSearchParams(location.search).get('review')==='combat';
export const fighterProfile = (id: string): FighterProfile => {
  const profile=fighterProfiles[id] ?? fighterProfiles[visualActorId(id)] ?? infantry('shield'),sheet=socketReviews[visualActorId(id)];
  if(sheet && (sheet.review==='accepted' || inspectPending && sheet.review==='pending'))return {...profile,muzzle:sheet.muzzle ?? profile.muzzle,hit:sheet.hit ?? profile.hit,radius:sheet.bodyRadius ?? profile.radius};
  return profile;
};
