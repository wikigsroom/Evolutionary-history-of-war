"""Fetch verified CC0 source audio on native Windows; keep provenance and originals."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse, unquote
import hashlib
import json
import requests
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "output/audio-sources"
SOURCES = [
    ("kenney-impact", "Impact Sounds", "Kenney", "https://kenney.nl/assets/impact-sounds", "zip"),
    ("kenney-interface", "Interface Sounds", "Kenney", "https://kenney.nl/assets/interface-sounds", "zip"),
    ("kenney-rpg", "RPG Audio", "Kenney", "https://kenney.nl/assets/rpg-audio", "zip"),
    ("kenney-scifi", "Sci-Fi Sounds", "Kenney", "https://kenney.nl/assets/sci-fi-sounds", "zip"),
    ("kenney-jingles", "Music Jingles", "Kenney", "https://kenney.nl/assets/music-jingles", "zip"),
    ("krakatoa", "Krakatoa", "Kistol", "https://opengameart.org/content/krakatoa", "ogg"),
    ("hope", "Hope (Orchestral battle music)", "MintoDog", "https://opengameart.org/content/hopeorchestral-battle-music", "flac"),
    ("massive-battle", "Massive Battle", "Eldritch Grim", "https://opengameart.org/content/massive-battle", "wav"),
    ("epic-march", "Epic March Loop", "Eldritch Grim", "https://opengameart.org/content/epic-war-loop", "wav"),
    ("8bit-battle", "8-Bit Battle Loop", "Theodore Kerr (Wolfgang_)", "https://opengameart.org/content/8-bit-battle-loop", "ogg"),
    ("awake", "Awake! (Megawall-10)", "cynicmusic", "https://opengameart.org/content/awake-megawall-10", "mp3"),
    ("relax", "relax_background1", "joaquinton", "https://opengameart.org/content/relaxbackground1-0", "ogg"),
]

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a" and "href" in attrs:
            self.hrefs.append(attrs["href"])

def fetch(source):
    key, title, author, page, extension = source
    directory = DEST / key
    directory.mkdir(parents=True, exist_ok=True)
    response = requests.get(page, timeout=45)
    response.raise_for_status()
    # Verify an actual CC0 license link, not a collection title containing CC0.
    parser = Links()
    parser.feed(response.text)
    license_urls = [urljoin(page, href) for href in parser.hrefs if "creativecommons.org/publicdomain/zero/1.0" in href]
    if not license_urls:
        raise ValueError(f"CC0 license link missing: {page}")
    (directory / "source-page.html").write_text(response.text, encoding="utf-8")
    urls = [urljoin(page, href) for href in parser.hrefs if urlparse(href).path.lower().endswith("." + extension)]
    if not urls:
        raise ValueError(f"Download missing: {page}")
    download = urls[0]
    path = directory / unquote(Path(urlparse(download).path).name)
    if not path.exists():
        binary = requests.get(download, timeout=90)
        binary.raise_for_status()
        path.write_bytes(binary.content)
    if extension == "zip":
        with zipfile.ZipFile(path) as archive:
            for member in archive.infolist():
                target = (directory / "extracted" / member.filename).resolve()
                if not target.is_relative_to((directory / "extracted").resolve()):
                    raise ValueError("Unsafe archive path")
            archive.extractall(directory / "extracted")
    result = {"id": key, "title": title, "author": author, "page": page, "license": "CC0-1.0",
              "license_url": license_urls[0], "download": download, "file": path.relative_to(ROOT).as_posix(),
              "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size}
    print(f"Downloaded {key}: {path.stat().st_size:,} bytes", flush=True)
    return result

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        sources = list(pool.map(fetch, SOURCES))
    license_response = requests.get("https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt", timeout=45)
    license_response.raise_for_status()
    (DEST / "CC0-1.0.txt").write_bytes(license_response.content)
    manifest = {"retrieved_at": datetime.now(timezone.utc).isoformat(), "sources": sources}
    (DEST / "sources.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {len(sources)} verified CC0 sources and license evidence.")

if __name__ == "__main__":
    main()
