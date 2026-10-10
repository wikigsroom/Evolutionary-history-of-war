"""Install a pinned native Gradle export template for the Android Keystore plugin."""
import os
import pathlib
import re
import zipfile

ROOT=pathlib.Path(__file__).resolve().parents[2]
PROJECT=ROOT/"godot"


def main():
    templates=pathlib.Path(os.environ["APPDATA"])/"Godot/export_templates/4.7.2.stable"
    source=templates/"android_source.zip"
    if not source.exists():raise SystemExit("Install official Godot 4.7.2 export templates first.")
    target=PROJECT/"android/build"
    if not (target/"build.gradle").exists():
        target.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(source) as archive:
            for entry in archive.infolist():
                if not (target/entry.filename).resolve().is_relative_to(target.resolve()):raise RuntimeError("Unsafe template path")
            archive.extractall(target)
    (target/".gdignore").touch()
    manifest=target/"src/main/AndroidManifest.xml"
    text=manifest.read_text(encoding="utf-8")
    # The engine AAR supplies legacy storage/phone permissions; explicitly remove
    # inherited permissions which are unrelated to our anonymous online feature.
    for permission in ["READ_PHONE_STATE","READ_EXTERNAL_STORAGE","WRITE_EXTERNAL_STORAGE"]:
        marker=f'android.permission.{permission}'
        if marker not in text:
            text=text.replace("<application",f'<uses-permission android:name="{marker}" tools:node="remove" />\n    <application',1)
    manifest.write_text(text,encoding="utf-8")
    (PROJECT/"android/.build_version").write_text("4.7.2.stable",encoding="utf-8")
    sdk=pathlib.Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or pathlib.Path.home()/"AppData/Local/Android/Sdk")
    if not (sdk/"build-tools/35.0.0/aapt.exe").exists():raise SystemExit("Install Android Build Tools 35.0.0 before native export.")
    config=target/"config.gradle"
    config.write_text(re.sub(r"(buildTools\s*:\s*)'[^']+'",r"\1'35.0.0'",config.read_text(encoding="utf-8")),encoding="utf-8")
    wrapper=target/"gradle/wrapper/gradle-wrapper.properties"
    text=wrapper.read_text(encoding="utf-8")
    text=re.sub(r"^distributionUrl=.*$",r"distributionUrl=https\://services.gradle.org/distributions/gradle-8.14.3-all.zip",text,flags=re.M)
    wrapper.write_text(text,encoding="utf-8")
    props=target/"gradle.properties"
    text=props.read_text(encoding="utf-8")
    for key,value in {"org.gradle.daemon":"false","org.gradle.console":"plain","android.overridePathCheck":"true","android.enableResourceOptimizations":"false"}.items():
        text=re.sub(r"^"+re.escape(key)+r"=.*\n?","",text,flags=re.M)
        text+=f"\n{key}={value}\n"
    props.write_text(text,encoding="utf-8")
    print("Native Android template ready: Godot 4.7.2 / Gradle 8.14.3 / SDK 36 / Build Tools 35.0.0")


if __name__=="__main__":main()
