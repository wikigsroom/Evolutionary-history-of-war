import Phaser from 'phaser';
import { GameApp } from './ui/app';
import { BattleScene } from './presentation/battle-scene';
import './ui/command-theme.css';
import './ui/rounded-theme.css';

async function boot(){
let initialize:()=>void=()=>{};
let bridge:import('./presentation/battle-scene').SceneBridge;
if(import.meta.env.DEV && new URLSearchParams(location.search).get('review')==='combat'){
  bridge=(await import('./qa/review')).createReviewBridge();
}else{
  const app=new GameApp();
  bridge={battle:()=>app.current,advance:delta=>app.advance(delta),point:(x,targetId)=>app.point(x,targetId),selectedSkill:()=>app.selectedSkill,reducedMotion:()=>app.reducedMotion,interpolation:()=>app.interpolation(),ready:errors=>app.ready(errors),camera:app.camera,canNavigate:()=>app.canNavigate(),cameraChanged:()=>app.paintCamera()};
  initialize=()=>{void app.init();};
}
const viewportHeight=()=>Math.max(420,Math.round(1000*innerHeight/innerWidth));
const game=new Phaser.Game({
  type: Phaser.AUTO,
  parent: 'game-world',
  width: 1000,height: viewportHeight(),
  backgroundColor: '#102333',
  render: { antialias: true,pixelArt: false,roundPixels: true },
  scale: { mode: Phaser.Scale.FIT,autoCenter: Phaser.Scale.CENTER_BOTH },
  audio: { noAudio: true },
  scene: [new BattleScene(bridge)],
});
window.addEventListener('resize',()=>{game.scale.setGameSize(1000,viewportHeight());game.scale.setParentSize(innerWidth,innerHeight);});
initialize();
}
void boot();
