"""Create authentic 0.6.2 save fixtures in an isolated native Godot project."""
from pathlib import Path
import zipfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/qa/ten-eras/legacy-fixture-project'
with zipfile.ZipFile(ROOT/'output/qa/ten-eras/baseline-0.6.2-sources.zip') as archive:
    for name in archive.namelist():
        if not name.startswith(('godot/scripts/','godot/scenes/','godot/assets/data/','godot/assets/shaders/')):continue
        path=OUT/Path(name).relative_to('godot');path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(archive.read(name))
(OUT/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Legacy Snapshot Fixtures"\nconfig/features=PackedStringArray("4.7", "GL Compatibility")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
(OUT/'make_fixtures.gd').write_text('''extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
    for age in range(1,6):
        var model=GameModel.new()
        model.reset_battle({"startingEraId":"A"+str(age),"aiEnabled":false,"loadout":model.db.default_loadout("H02")})
        model.hero(0)["hp"]=model.hero(0)["maxHp"]*0.6
        model.hero(0)["x"]=600.0;model.hero(0)["previousX"]=600.0
        model.sides[0]["command"]=100;model.sides[0]["gold"]=1000
        model.spawn(0,"U%d1"%age,"A"+str(age),"unit",450.0)
        var target=model.spawn(1,"U%d1"%age,"A"+str(age),"unit",820.0)
        target["speed"]=0
        model.abilities.cast(0,"HS02",820.0,int(target["id"]))
        model.act({"type":"train","unitId":"U%d2"%age,"side":0})
        model.step_ticks(2)
        var file=FileAccess.open("res://../legacy-age-%d.json"%age,FileAccess.WRITE)
        file.store_string(JSON.stringify(model.snapshot(),"\\t"));file.close();model.free()
    print("FIVE AUTHENTIC LEGACY SAVES WRITTEN")
    quit()
''',encoding='utf-8')
print(OUT)
