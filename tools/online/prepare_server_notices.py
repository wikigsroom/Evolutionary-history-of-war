"""Retain upstream redistribution notices for the native server dependencies."""
import json
import base64
import pathlib
import re
import subprocess
import urllib.request

ROOT=pathlib.Path(__file__).resolve().parents[2]
DEST=ROOT/"services/online-gateway/licenses"
SOURCES={
    "PostgreSQL-COPYRIGHT.txt":"https://raw.githubusercontent.com/postgres/postgres/REL_18_STABLE/COPYRIGHT",
    "Zonky-Apache-2.0.txt":"https://raw.githubusercontent.com/zonkyio/embedded-postgres-binaries/master/LICENSE",
    "OpenSSL-LICENSE.txt":"https://raw.githubusercontent.com/openssl/openssl/openssl-3.4/LICENSE.txt",
    "ICU-LICENSE.txt":"https://raw.githubusercontent.com/unicode-org/icu/release-77-1/LICENSE",
    "libxml2-LICENSE.txt":"https://raw.githubusercontent.com/GNOME/libxml2/master/Copyright",
    "zstd-LICENSE.txt":"https://raw.githubusercontent.com/facebook/zstd/v1.5.7/LICENSE",
    "lz4-LICENSE.txt":"https://raw.githubusercontent.com/lz4/lz4/v1.10.0/lib/LICENSE",
    "zlib-LICENSE.txt":"https://raw.githubusercontent.com/madler/zlib/v1.3.1/LICENSE",
    "winpthreads-COPYING.txt":"https://raw.githubusercontent.com/mingw-w64/mingw-w64/master/mingw-w64-libraries/winpthreads/COPYING",
    "GNU-LGPL-2.1.txt":"https://raw.githubusercontent.com/autotools-mirror/gettext/master/gettext-runtime/intl/COPYING.LIB",
}


def main():
    (DEST/"postgresql").mkdir(parents=True,exist_ok=True)
    for name,url in SOURCES.items():
        path=DEST/"postgresql"/name
        if not path.exists():
            if url.startswith("https://raw.githubusercontent.com/"):
                owner,repository,ref,filename=url.removeprefix("https://raw.githubusercontent.com/").split("/",3)
                cli=ROOT/".local-tools/github-cli/bin/gh.exe"
                result=subprocess.run([str(cli),"api",f"repos/{owner}/{repository}/contents/{filename}?ref={ref}"],capture_output=True,check=True,timeout=35,text=True)
                content=base64.b64decode(json.loads(result.stdout)["content"])
            else:
                request=urllib.request.Request(url,headers={"User-Agent":"Epoch-Rush-server-notices/0.8.0"})
                with urllib.request.urlopen(request,timeout=25) as response:content=response.read()
            if len(content)<120 or b"<html" in content.lower():raise RuntimeError("Invalid upstream notice: "+name)
            path.write_bytes(content)
    references={"license_sources":SOURCES,"runtime_sources":{
        "PostgreSQL":"https://ftp.postgresql.org/pub/source/v18.6/",
        "OpenSSL":"https://github.com/openssl/openssl",
        "ICU":"https://github.com/unicode-org/icu/tree/release-77-1",
        "libxml2":"https://gitlab.gnome.org/GNOME/libxml2",
        "libiconv":"https://ftp.gnu.org/pub/gnu/libiconv/",
        "libintl/gettext":"https://ftp.gnu.org/pub/gnu/gettext/",
        "winpthreads":"https://github.com/mingw-w64/mingw-w64/tree/master/mingw-w64-libraries/winpthreads",
        "zstd":"https://github.com/facebook/zstd",
        "lz4":"https://github.com/lz4/lz4",
        "zlib":"https://github.com/madler/zlib"},"note":"Native PostgreSQL binary package is unmodified. Source archives and exact build configuration are available from the pinned Zonky upstream package project. Runtime GPL/LGPL libraries retain their upstream licenses; they are dynamically linked."}
    (DEST/"postgresql/SOURCES.json").write_text(json.dumps(references,indent=2)+"\n",encoding="utf-8")
    go=ROOT/".local-tools/online/go/bin/go.exe"
    result=subprocess.run([str(go),"env","GOMODCACHE"],capture_output=True,check=True,text=True,timeout=20)
    cache=pathlib.Path(result.stdout.strip())
    modules=DEST/"go-modules";modules.mkdir(exist_ok=True)
    requirements=re.findall(r'^\s*((?:github\.com|golang\.org)/\S+)\s+(v\S+)',(ROOT/"services/online-gateway/go.mod").read_text(encoding="utf-8"),re.M)
    for module,version in requirements:
        directory=cache/(module+"@"+version)
        licenses=[p for p in directory.iterdir() if p.is_file() and p.name.upper().startswith(("LICENSE","COPYING","NOTICE"))]
        if not licenses:raise RuntimeError("Module redistribution notice missing: "+module)
        for license in licenses:
            target=modules/(module.replace("/","_")+"_"+version+"_"+license.name)
            target.write_bytes(license.read_bytes())
    print("Native server redistribution notices prepared")


if __name__=="__main__":main()
