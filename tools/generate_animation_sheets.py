"""One whole-pose sheet per actor, through the user-designated Sub2 CLI only."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, sys, time
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/epoch-rush/v0.3-animation'
CLI = Path('C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py')
descriptions = {
 'U11': 'Stone-age muscular caveman, brown swept-back hair and beard, ivory wolf-skull shoulder pelt, brown fur loincloth, blue sash. Left hand carries an ivory bone shield, right hand carries a short stone club. Shield protects while club swings.',
 'U12': 'Redesign the reference into a STONE-AGE SLINGER, preserving only the youthful face, short dark ponytail and blue faction sash. OVERRIDE the reference hat, cream linen tunic and long cape: replace them with a rough short ochre-brown animal-fur tunic, bare forearms and calves, leather wraps and ONE small leather stone pouch at the hip. No hat, no linen coat, no metal armor. Weapon is exactly ONE flexible leather sling made from one pair of thin cords joined to one pouch; never draw a second sling, duplicate pouch, second cord pair, staff, bow or rigid slingshot. Right hand holds the two cords. Attack frame 1 draws the single cord behind the body; frame 2 whirls the one pouch overhead; frame 3 extends the hand forward and RELEASES one end of the cord, with the same single pouch hanging empty and no duplicate weapon; frame 4 follows through, frame 5 reloads one stone from the one leather bag, frame 6 returns to ready. The stone is absent from frames 3-6 because the engine renders it separately. The single sling remains short and fully inside its cell.',
 'U13': 'Stone-age slim spear infantry, dark hair, brown fur tunic, ivory bone shoulder guard and blue waist cloth. Both hands use a medium wooden spear with a chipped flint point and a short blue faction pennant tied near the rear. The COMPLETE spear, pennant and body must fit inside every six-column cell with at least 18 pixels of magenta margin; shorten the spear if necessary and never let its point touch a cell or the source canvas edge. Clear forward spear thrust, with frame 3 extending only to the right half of its cell.',
 'U14': 'Stone-age heavy beast rider: stocky caveman in brown fur and blue sash riding a compact woolly boar with ivory tusks. Rider uses a stone hammer. The boar trots, rears and lunges; all six walk frames include both rider and boar.',
 'U21': 'Preserve the reference bronze-age infantry: warm bronze helmet with a royal-blue crest, bronze chest armor, cream linen and blue trim, round bronze shield and short bronze sword. Shield braced, then decisive short sword slash.',
 'U22': 'Preserve the reference bronze-age archer: bronze helmet with a cream-and-blue plume, cream linen under bronze plates, blue waist sash, curved wooden bow and back quiver. Draw the bow with a visible string and arrow, release, lower it.',
 'U23': 'Bronze-age anti-armor spearman, bronze helmet, bronze shoulder plates, blue tunic, medium bronze-tipped wooden pike. Deep two-handed forward thrust, but keep the pike compact: the full spear point must stay at least 18 pixels inside its own cell and must never touch or overlap any neighboring frame. Do not draw a wall-length pike; shorten it for the six-column grid.',
 'U24': 'Bronze-age heavy war chariot: one compact sturdy horse attached to a two-wheel bronze wood chariot, blue triangular standard and armored charioteer carrying a SHORT spear. Entire horse plus chariot fits every cell with 18px clear magenta margin on every side; the spear point must stay inside the same cell and never touch a neighboring frame, even during attack. Trotting hooves and rolling wheels, attack lunge kept compact.',
 'U31': 'Preserve the reference medieval shield infantry: silver steel helmet and breastplate with brass trim, blue crest and gambeson, broad blue heraldic shield and a VERY SHORT steel arming sword ending near the soldier\'s knee. Shield braces while the short sword performs a compact close slash; do not extend the arm or blade far from the torso. Keep every sword and shield at least 24 pixels inside its own six-column cell; no weapon may touch or overlap a neighboring frame. Never draw a long sword or a lunge.',
 'U32': 'Preserve the reference medieval CROSSBOW soldier: silver steel helmet, blue scarf and banner, steel shoulder plates, brown leather belts, heavy wooden crossbow on its compact attached support. No longbow or hand-drawn bowstring. Aim the loaded crossbow, pull its trigger to release a single bolt on attack frame 3, recoil, operate the short cocking lever and recover. Keep the soldier and entire supported crossbow together in every frame; fold or carry its support during the walk cycle.',
 'U33': 'Medieval armored pikeman, steel half helmet, blue gambeson, steel pauldrons and a COMPACT medium steel-tipped pike. The pike is only slightly longer than the soldier and its complete point stays at least 24 pixels inside the six-column cell in every pose; never use a wall-length spear. Two-handed horizontal pike thrust behind an imaginary friendly shield line. Keep every figure and pike isolated from neighboring cells.',
 'U34': 'Preserve the reference medieval heavy cavalry: compact cream-white horse with blue heraldic caparison and brass trim, silver armored knight, blue plume, wooden lance and split blue banner. Complete horse and rider in every cell. Distinct horse trot and strong forward lance lunge.',
 'U41': 'Preserve the reference industrial frontline rifle infantry: broad soldier in riveted silver steel and brass armor, blue fabric and helmet crest, tall steel shield with brass edging, short wood-stock rifle fired alongside the shield. No olive modern uniform. Shield braces as the rifle fires forward; planted boots and restrained recoil.',
 'U42': 'Preserve the reference industrial musketeer: brown feathered brimmed hat, red-and-blue short coat, cream sleeves, leather belts and boots, long wood-stock musket with a silver barrel. No modern army helmet or olive uniform. Shoulder aim, forward musket shot with visible kickback, then reload recovery. Muzzle stays to the right.',
 'U43': 'Preserve the reference industrial anti-armor heavy gunner: riveted silver-and-brass helmet and shoulder armor, short goggles, royal-blue cloth, long heavy wood-and-steel machine gun with its compact bipod. No rocket launcher, rockets or modern green uniform. Plant or brace the bipod, aim the heavy gun, fire forward with a firm shoulder jolt on attack frame 3, recover. During the walk carry the gun and folded bipod as one attached weapon.',
 'U44': 'Preserve the reference industrial heavy tracked cannon: low steel and warm brass chassis, exposed brass recoil mechanism, two continuous dark treads, single broad brass cannon barrel pointing right, royal-blue identification banner. No olive modern tank skin. Treads roll, cannon recoils backward into its mount then returns. No humanoid limbs or added wheels.',
 'U51': 'Preserve the reference orbital frontline guard: cream ceramic exosuit with ornate brass edges, royal-blue panels and crest, small cyan crystal antenna, blue rounded shield with a time-ring emblem, and a SHORT cyan energy blade. Shield braces while the single short blade makes a compact forward slash. Keep blade and shield at least 24 pixels inside the cell and never let an attack pose touch its neighbor. Keep the warm brass-and-cream strategy-game design.',
 'U52': 'Preserve the reference orbital support gunner: pale-haired hooded figure in cream ceramic plates, long cream coat, royal-blue cape and brass edging, long twin-pronged cyan plasma rifle. Keep the reference cape and silhouette. Aim, recoil, then return to firing stance.',
 'U53': 'Preserve the reference orbital anti-armor lancer: cream ceramic helmet and armor, brass trim, royal-blue cape and plates, a SHORT compact cyan energy lance with a small ornamental shaft. Render this unit at about 70 percent of the available cell height, leaving a broad 40-pixel magenta safety border around the entire 1024 canvas. The lance blade extends no more than 55 pixels beyond the body in the attack, never lies horizontally across a cell boundary, and stays at least 28 pixels inside its own cell in every frame. During death poses hold the short lance close to the torso or point it diagonally down; never overlap a neighbor or touch the outer canvas edge. Forward two-handed close thrust with planted legs. No gun.',
 'U54': 'Preserve the reference orbital heavy two-legged walker: compact cream ceramic and brass mech, cyan central time-ring core, broad brass-edged shoulders, stout mechanical legs and one cyan arc-cannon arm aimed right, royal-blue banner. Weighty stepping gait and cannon charging then recoil. Machine, not a human.',
 'H01': 'Hero standard-bearer Li Chuan: preserve the reference brown swept-back hair, face, brass-edged plate armor, leather belts and boots, royal-blue cape, short broad sword and tall blue battle flag attached to the back. Decisive heroic sword slash; flag follows body motion. No added fur costume.',
 'H02': 'Hero eagle-eye ranger Lan Ling: preserve the reference face and wavy brown hair, brown feathered brimmed ranger hat, cream and brown ranger jacket, royal-blue scarf and cape, leather boots, long recurved bow. Keep the hat throughout every pose. Bowstring clearly drawn to cheek and released, feet stable.',
 'H03': 'Hero ironwall guardian Duo Shan: preserve the broad older bearded man, thick silver and brass plate armor, blue cape, huge rectangular brass-edged shield and a COMPACT short-bladed halberd. The halberd head and shaft stay at least 24 pixels inside the cell and never cross into the neighboring frame; attack is a weighty close forward chop with the weapon kept near his body. Shield braces. No replacement war hammer.',
 'H04': 'Hero engineer Qi Heng: preserve the reference face, brown hairstyle and brass goggles, tan and red leather engineer clothes, blue hair ribbon and scarf, belt tools and compact brass repeating gun. Aims forward, gun recoil, checks mechanism.',
 'H05': 'Hero chronologist Su Qing: preserve the exact face and hairstyle of the reference, long cream academic coat with brass ornamental panels, royal-blue collar and cape, ring-shaped cyan time crystal held in one hand. Channels a restrained cyan orb through the ring toward the right, then recovers. Full purposeful arm gesture. No staff or added weapon.',
 'H06': 'Hero supply marshal Mai Sui: preserve the reference braided brown hair and blue ribbon, cream shirt, dark navy and brown travel clothes, leather supply satchel and rolled supplies, compact wood-and-brass crossbow. Aim, shoot, reload; satchel follows torso naturally.',
 'U15': 'Stone-age fire drummer: preserve the supplied reference face, feather crest, red-ochre short cloak, bone ornaments, blue faction sash and one broad hide drum strapped to the waist. BOTH hands hold short bone drumsticks. No shield, club, sword or gun. Attack frames raise the right stick, raise both sticks, STRIKE THE DRUM on frame 3, let the drum skin rebound, then return to ready. Walk in place with the drum secured to the waist. Keep flame motifs as painted fabric, not actual floating flames. Compact and readable at 100px tall.',
 'U25': 'Bronze-age sun standard guardian: preserve reference bronze round sun-emblem shield, tall blue-and-gold sun flag attached behind the left shoulder, bronze helmet, cream linen and royal-blue trim. One very SHORT bronze sword in the right hand. Compact planted sword slash with shield held near chest. The attached flag moves subtly with the torso, remains compact and fully within each cell. No extra characters or second flag.',
 'U35': 'Medieval falcon scout: preserve reference light steel helmet, blue-grey short hooded cape, leather gear, SMALL brown falcon perched on the left shoulder, and compact wooden CROSSBOW held in both hands. No pike, longbow or long rifle. Falcon remains perched throughout idle/walk/attack/hurt and falls with the character in death. Attack frame 3 is a precise forward crossbow release, then hand operates a short cocking lever. All gear compact inside cell.',
 'U45': 'Industrial field medic: preserve reference friendly youthful face, brown cap and brass goggles, cream rolled sleeves, navy-blue apron coat, white cloth armband with a simple green plus, short brass-and-wood pistol in right hand, and compact medical satchel at left hip. The other hand supports the pistol in attack; frame 3 fires forward, then recoil and recover. No modern military helmet or long musket. Satchel, green medical emblem and brass syringe case remain readable and consistent.',
 'U55': 'Orbital chronotech engineer: preserve reference cream ceramic and warm brass suit, royal-blue short cape, cyan round phase coil on backpack, transparent cyan goggles, and ONE compact brass tool arm emitting energy aimed right. Human with two normal legs and two arms, not a giant mech. Attack anticipates, charges the tool arm, extends hand forward in frame 3, recovers. No floating particles or energy beams in the sheet; engine renders them separately. Small backpack coil and tool stay attached and inside every cell.',
}
parser = argparse.ArgumentParser()
parser.add_argument('--only', default='U11')
parser.add_argument('--force', action='store_true')
parser.add_argument('--prompts-only', action='store_true', help='Write the specified actor prompts without requesting images')
args = parser.parse_args()
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'prompts').mkdir(exist_ok=True)
(OUT / 'raw').mkdir(exist_ok=True)

def prompt(actor):
 return f'''Production-ready 2D game animation sprite sheet, exactly SIX columns and FIVE rows, 30 complete full-body frames. Entire image is 1024 by 1024 pixels. Each equal cell is 170.67 px wide and 204.8 px high. No gaps between cells and absolutely no grid lines, lettering, labels or numbers. Plain perfectly solid #FF00FF magenta background, no cast shadows, no floor, no props outside the character. All sprites face RIGHT in true side view with a very slight three-quarter torso, suitable for a single-lane side-scrolling game.
Subject: {descriptions[actor]}
Style: warm hand-painted cartoon strategy game, bold clean dark brown outlines, 3-head-tall heroic proportions, readable chunky silhouettes, cream highlights, small expressive faces, warm natural materials, royal-blue faction accents and brass trim. Keep the supplied reference's identity, costume and exact weapon type except the explicitly redesigned U14 boar rider. Industrial and orbital eras continue the same cream, brass and blue visual language, rather than generic modern soldiers or glossy science-fiction armor. Avoid realistic rendering, pixel art, glossy 3D toys and texture noise. Keep character design, face, clothing, weapon size and body proportions absolutely identical throughout all 30 frames. One animation master sheet, not different character variations.
ROW 1: six gentle idle breathing frames, hands keep the weapon, relaxed but alert. Minimal rhythmic movement.
ROW 2: six successive WALK CYCLE frames, including right-foot contact, down pose, passing pose, left-foot contact, down pose, passing pose. For horses or machines, animate hooves or treads appropriately. Body travels in place; character does not drift across cells.
ROW 3: six ATTACK poses in precise left-to-right order: anticipation, deep windup, forward launch/contact pose, immediate recoil/follow-through, recovery, ready pose. The weapon must change angle and position meaningfully, not rotate the entire cutout. Frame 3 is the strike or projectile release. Bow string is taut before release, gun barrel retracts at recoil, melee hips and shoulders turn. Weapon always attached to the correct hand.
ROW 4: six HIT REACTION poses: slight impact anticipation, backward torso jolt, deepest recoil, braced recovery, stand up, ready. Feet remain anchored, impact does not launch the character far away.
ROW 5: six DEATH poses: initial stagger, knees buckle, body tips backward, falling, touches ground, lies on ground. Last frame is a clear fallen body or disabled vehicle, no blood or gore.
Layout: EACH cell contains the ENTIRE figure and weapon fully within the cell with at least 8 pixels margin on all sides. The same character scale across all cells, no zoom or camera change. In each cell the character's root stays at horizontal center x=85 and the lowest grounded foot is at local y=180. Death poses lie at the same y=180 ground baseline. Large mounted units fit by being wider and shorter while retaining the same scale across their own frames. No character overlaps a neighboring cell. No extra characters, motion trail duplicates, smoke or muzzle flashes: these effects are drawn separately in the engine. Deliver exactly 30 frames, six columns, five rows.'''

def generate(actor):
 source = OUT / 'raw' / (actor + '.png')
 prompt_file = OUT / 'prompts' / (actor + '.txt')
 if source.exists() and args.force:
  archive=OUT/'rejected'/hashlib.sha256(source.read_bytes()).hexdigest()[:12];archive.mkdir(parents=True,exist_ok=True)
  for old in [source,source.with_suffix('.metadata.json'),prompt_file]:
   if old.exists():shutil.copy2(old,archive/old.name)
 prompt_file.write_text(prompt(actor), encoding='utf-8')
 if source.exists() and not args.force:
  with Image.open(source) as im: im.verify()
  return {'id': actor, 'status': 'existing'}
 reference_actor='U11' if actor=='U14' else actor
 reference = (ROOT / 'output/imagegen/epoch-rush/v0.4-specials' / (actor + '.png')) if actor in {'U15','U25','U35','U45','U55'} else ROOT / 'public/assets/characters' / ('heroes' if actor.startswith('H') else 'units') / (reference_actor + '.png')
 command = [sys.executable, '-X', 'utf8', str(CLI), 'edit', '--image', str(reference), '--prompt-file', str(prompt_file), '--model', 'gpt-image-2.5', '--size', '1024x1024', '--quality', 'high', '--background', 'opaque', '--out', str(source)]
 if args.force: command.append('--force')
 for attempt in range(3):
  print('Generating full-pose sheet ' + actor, flush=True)
  result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding='utf-8')
  if result.returncode == 0:
   with Image.open(source) as im: size = list(im.size); im.verify()
   row = {'id': actor, 'status': 'generated', 'model': 'gpt-image-2.5', 'route': 'Sub2 CLI edit', 'referenceSha256': hashlib.sha256(reference.read_bytes()).hexdigest(), 'size': size, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'promptSha256': hashlib.sha256(prompt_file.read_bytes()).hexdigest()}
   source.with_suffix('.metadata.json').write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')
   print('Generated ' + actor, flush=True)
   return row
  error = result.stderr.strip() or result.stdout.strip()
  if any(code in error for code in ['HTTP 429','HTTP 502','HTTP 503','HTTP 504']) and attempt < 2:
   time.sleep(2 * (attempt + 1)); continue
  print('Failed ' + actor + ': ' + error[:450], flush=True)
  return {'id': actor, 'status': 'failed', 'error': error[:450]}
 return {'id': actor, 'status': 'failed'}

actors = list(descriptions) if args.only == 'all' else args.only.split(',')
if any(actor not in descriptions for actor in actors): raise SystemExit('Unknown actor ID')
if args.prompts_only:
 for actor in actors: (OUT / 'prompts' / (actor + '.txt')).write_text(prompt(actor), encoding='utf-8')
 print(json.dumps({'mode': 'prompts_only', 'actors': len(actors), 'generatedImages': 0}))
 raise SystemExit(0)
results = []
with ThreadPoolExecutor(max_workers=2) as pool:
 for future in as_completed([pool.submit(generate, actor) for actor in actors]): results.append(future.result())
(OUT / ('generation-' + args.only.replace(',', '-') + '.json')).write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
raise SystemExit(1 if any(row['status'] == 'failed' for row in results) else 0)
