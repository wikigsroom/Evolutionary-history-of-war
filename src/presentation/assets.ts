import rawManifest from '../content/runtime-manifest.json';

export interface Asset { key: string; path: string; kind: string; size: number[]; anchor?: number[]; status: string; derivedFrom?: string }
export const assetEntries = (Object.values(rawManifest.entries) as Asset[]).filter(asset => asset.status!=='rejected');
export const assetMap = Object.fromEntries(assetEntries.map(asset => [asset.key,asset])) as Record<string,Asset>;
export const assetPath = (key: string) => assetMap[key] ? `./assets/${assetMap[key].path}` : '';
