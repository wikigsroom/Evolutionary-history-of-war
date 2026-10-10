"""Install isolated native Windows toolchains; never invokes containers or WSL."""
import hashlib
import json
import pathlib
import io
import tarfile
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
TARGET = ROOT / ".local-tools" / "online"


def download(url, name, expected=None):
    path = TARGET / name
    if not path.exists():
        print("Downloading", name, flush=True)
        urllib.request.urlretrieve(url, path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if expected and digest != expected:
        raise RuntimeError("Download checksum mismatch: " + name)
    print(name, "sha256", digest, flush=True)
    return path


def main():
    TARGET.mkdir(parents=True, exist_ok=True)
    if not (TARGET / "go/bin/go.exe").exists():
        with urllib.request.urlopen("https://golang.google.cn/dl/?mode=json&include=all", timeout=20) as response:
            release = next(r for r in json.load(response) if r["version"] == "go1.27.2")
        package = next(f for f in release["files"] if f["os"] == "windows" and f["arch"] == "amd64" and f["kind"] == "archive")
        archive = download("https://dl.google.com/go/" + package["filename"], package["filename"], package["sha256"])
        with zipfile.ZipFile(archive) as z:
            z.extractall(TARGET)
    if not (TARGET / "pgsql/bin/postgres.exe").exists():
        # This Maven bundle contains native Windows PostgreSQL binaries for local
        # development. Production uses an independently maintained PostgreSQL service.
        name = "embedded-postgres-binaries-windows-amd64-18.6.0.jar"
        url = "https://repo.maven.apache.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-windows-amd64/18.6.0/" + name
        archive = download(url, name, "b7ef2d03588e0439f0d0a2250f43905f7464f1e96ace47703ceaf79094198150")
        with zipfile.ZipFile(archive) as z:
            with tarfile.open(fileobj=io.BytesIO(z.read("postgres-windows-x86_64.txz")), mode="r:xz") as native:
                native.extractall(TARGET / "pgsql", filter="data")
    print("Native Go and PostgreSQL ready:", TARGET, flush=True)


if __name__ == "__main__":
    main()
