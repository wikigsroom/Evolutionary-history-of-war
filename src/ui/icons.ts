/**
 * Epoch Rush icon family.
 *
 * The battle HUD uses a generated 4x4 pixel atlas for the high-frequency
 * commands. Less common semantic icons keep an inline, deliberately angular
 * SVG fallback so every control still shares the same crisp, square-ended
 * visual language when the atlas does not contain a dedicated glyph.
 */
const atlasIcons = new Set([
  'flag','sword','shield','book',
  'relic','gear','arrow','pause',
  'play','coin','spark','crown',
  'tower','upgrade','target','map',
]);

const paths:Record<string,string>={
  back:'M20 12H4m6-6-6 6 6 6',
  home:'M3 10 12 3l9 7M5 9v12h14V9m-9 12v-7h4v7',
  check:'M5 12 9 16 19 6',
  lock:'M6 10V7a6 6 0 0 1 12 0v3M4 10h16v12H4V10Zm8 4v4',
  chevron:'M7 10 12 15 17 10',
  scope:'M3 12h5m8 0h5M12 3v5m0 8v5M5 5l3 3m8 8 3 3M5 19l3-3m8-8 3-3',
  pierce:'M3 21 18 6m-8 0h8v8M4 10l10 10',
  heavy:'M4 17 7 7h10l3 10M3 17h18v4H3v-4Zm6-4h6',
  blast:'M12 2 14 8l6-3-3 6 5 3-6 2 2 6-6-4-4 4 1-7-6-1 6-4-2-5 5 3Z',
  people:'M9 10a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm6-1a2 2 0 1 0 0-4M3 20v-4c0-5 12-5 12 0v4m3-7c3 0 3 4 3 7',
  door:'M4 21h16M6 21V3h12v18m-4-9h1',
  info:'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18ZM12 10v7m0-11v1',
  stone:'M3 13 8 5l9-2 5 10-4 8H6l-3-8Zm5-8 3 9 11-1',
  bronze:'M5 5h14v12l-7 5-7-5V5Zm7-3v14m-6-6h12',
  factory:'M3 21V10l6 3V8l6 4V4h5v17H3Zm3-4h1m4 0h1m4 0h1',
  orbit:'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Zm-9 9c-3-6 17-19 19-12s-17 18-19 12Z',
  meteor:'M5 18 7 13l5-2 3 3-2 5-5 2-3-3Zm4-9 7-7m-3 8 7-7m-3 10 5-5',
  flame:'M12 2c2 6 7 7 7 13a7 7 0 0 1-14 0c0-4 2-5 4-8v6c3-2 4-5 3-11Z',
  arrows:'M5 3v17m-3-4 3 5 3-5M12 3v17m-3-4 3 5 3-5M19 3v17m-3-4 3 5 3-5',
  plane:'M2 14 10 11l2-8h2l1 8 7 3v2l-8-1-1 6h-2l-1-6-8 1v-2Z',
  beam:'M7 3h10l-2 5H9L7 3Zm5 5v12M4 21l4-5m12 5-4-5M9 12l-3 6m9-6 3 6',
  drum:'M4 9h16m-14 0v7c0 3 12 3 12 0V9M6 7c0-3 12-3 12 0S6 10 6 7Zm3 9v2m6-2v2M12 4v3',
  smoke:'M5 19c2-4 5-4 7-1s6 3 7-1M4 14c2-4 5-4 7-1s6 3 8-1M8 8c1-3 4-4 6-1',
  crate:'M4 7 12 3l8 4v10l-8 4-8-4V7Zm8-4v8m8-4-8 4-8-4m8 4v10',
};

/** Returns either an atlas-backed pixel glyph or an angular SVG fallback. */
export function uiIcon(name:string){
  if(atlasIcons.has(name)) return `<span class="ui-icon pixel-atlas pixel-atlas-${name}" aria-hidden="true"></span>`;
  const path=paths[name] ?? paths.flag;
  return `<svg class="ui-icon pixel-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" stroke-linejoin="miter" shape-rendering="crispEdges" aria-hidden="true"><path d="${path}"/></svg>`;
}


