"""Compile a Godot Android v2 plugin using the configured native JDK and Android SDK."""
import io
import os
import pathlib
import subprocess
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "services/android-secure-store"
WORK = ROOT / "output/online-android-plugin"


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    api = WORK / "godot-4.7.2.stable.aar"
    if not api.exists():
        print("Downloading native Godot Android API", flush=True)
        urllib.request.urlretrieve("https://repo.maven.apache.org/maven2/org/godotengine/godot/4.7.2.stable/godot-4.7.2.stable.aar", api)
    with zipfile.ZipFile(api) as archive:
        classes = WORK / "godot-api.jar"
        classes.write_bytes(archive.read("classes.jar"))
    jdk = pathlib.Path(os.environ["JAVA_HOME"])
    sdk = pathlib.Path(os.environ.get("ANDROID_HOME", pathlib.Path.home() / "AppData/Local/Android/Sdk"))
    android_api = sdk / "platforms/android-36/android.jar"
    compiled = WORK / "classes"
    compiled.mkdir(exist_ok=True)
    sources = list((SOURCE / "src").rglob("*.java"))
    subprocess.run([str(jdk / "bin/javac.exe"), "-encoding", "UTF-8", "-source", "8", "-target", "8", "-classpath", str(classes) + os.pathsep + str(android_api), "-d", str(compiled), *map(str, sources)], check=True)
    jar = io.BytesIO()
    with zipfile.ZipFile(jar, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in compiled.rglob("*.class"):
            archive.write(path, path.relative_to(compiled).as_posix())
    plugin_dir = ROOT / "godot/android/plugins"
    plugin_dir.mkdir(parents=True, exist_ok=True)
    output = plugin_dir / "EpochSecureStore.aar"
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("classes.jar", jar.getvalue())
        archive.write(SOURCE / "AndroidManifest.xml", "AndroidManifest.xml")
    (plugin_dir / "EpochSecureStore.gdap").write_text('[config]\nname="EpochSecureStore"\nbinary_type="local"\nbinary="EpochSecureStore.aar"\n\n[dependencies]\nlocal=[]\nremote=[]\ncustom_maven_repos=[]\n', encoding="utf-8")
    print("Android Keystore plugin built:", output, flush=True)


if __name__ == "__main__":
    main()
