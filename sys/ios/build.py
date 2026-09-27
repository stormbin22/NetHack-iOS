"""Build host generators, then cross-compile the unchanged Android C port.

The small in-process JNI adapter connects that port to UIKit, not to a JVM.
"""
from pathlib import Path
import concurrent.futures
import glob
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
OUT = ROOT / "build/ios"
OUT.mkdir(parents=True, exist_ok=True)
HOST = OUT / "host"
HOST.mkdir(exist_ok=True)

def run(*args, cwd=ROOT):
    command = [str(a) for a in args]
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        print("FAILED:", " ".join(command), flush=True)
        print(result.stdout, flush=True)
        raise SystemExit(result.returncode)
    if result.stdout.strip():
        print(result.stdout, flush=True)
    return result.stdout.strip()

lua = OUT / "lua-5.4.8/src"
if not lua.exists():
    archive = OUT / "lua-5.4.8.tar.gz"
    urllib.request.urlretrieve("https://www.lua.org/ftp/lua-5.4.8.tar.gz", archive)
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            if not (OUT / member.name).resolve().is_relative_to(OUT.resolve()):
                raise RuntimeError("Invalid Lua archive path")
        tar.extractall(OUT, filter="data")
header = '#include "lua.h"\n#include "lualib.h"\n#include "lauxlib.h"\n'
(ROOT / "include/nhlua.h").write_text(header)
common = ["-std=c99", "-O1", "-fsigned-char", "-DANDROID", "-DSND_LIB_ANDROIDSOUND", "-Iinclude", "-Isys/ios", f"-I{lua}"]

def host_objects(names):
    objects=[]
    for source in names:
        obj=HOST/(Path(source).stem+".o")
        run("xcrun", "clang", *common, "-c", source, "-o", obj)
        objects.append(obj)
    return objects

print("Building host data generators", flush=True)
base=host_objects(["src/alloc.c", "src/hacklib.c", "util/panic.c", "src/monst.c", "src/objects.c"])
makeobjs=host_objects(["src/date.c", "util/makedefs.c"])
run("xcrun", "clang", *base, *makeobjs, "-o", ROOT/"util/makedefs")
for flag in ("-p", "-o", "-d", "-r", "-h", "-1", "-2", "-3", "-v"):
    run("./makedefs", flag, cwd=ROOT/"util")
tileobjs=host_objects(["src/drawing.c", "win/share/tilemap.c"])
run("xcrun", "clang", *base, *tileobjs, "-o", ROOT/"util/tilemap")
run("./tilemap", cwd=ROOT/"util")

sources=re.search(r"HACKCSRC \?= (.*?)(?:\n\n)", (ROOT/"sys/android/Makefile.src").read_text(), re.S)[1]
sources=["src/"+s for s in sources.replace("\\\n", " ").split()]
sources += ["src/date.c", "src/tile.c", "sys/share/posixregex.c", "sys/share/ioctl.c", "sys/share/unixtty.c", "sys/android/androidmain.c", "sys/android/androidunix.c", "sys/android/winandroid.c"]
sources += [str(p) for p in lua.glob("*.c") if p.name not in ("lua.c", "luac.c")]
# iOS has no command shell. Lua os.execute must report that it is unavailable.
loslib=lua/"loslib.c"
luaos=loslib.read_text()
luaos=luaos.replace("system(cmd)", "((cmd) == NULL ? 0 : -1)")
loslib.write_text(luaos)

sdk=run("xcrun", "--sdk", "iphoneos", "--show-sdk-path")
target=["-target", "arm64-apple-ios16.0", "-isysroot", sdk]
objects=OUT/"objects"
objects.mkdir(exist_ok=True)
def compile_c(source):
    obj=objects/(Path(source).stem+".o")
    run("xcrun", "clang", *target, *common, "-c", source, "-o", obj)
    return obj
print("Compiling NetHack and Lua for iPhone", flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    compiled=list(pool.map(compile_c, sources))
for source in ("Bridge.m", "GameApp.m"):
    obj=objects/(source+".o")
    run("xcrun", "clang", *target, "-fobjc-arc", "-fmodules", "-Isys/ios", "-c", "sys/ios/"+source, "-o", obj)
    compiled.append(obj)

app=OUT/"Payload/NetHack.app"
app.mkdir(parents=True,exist_ok=True)
run("xcrun", "clang", *target, *compiled, "-framework", "UIKit", "-framework", "Foundation", "-o", app/"NetHack")
info=plistlib.loads((ROOT/"sys/ios/Info.plist").read_bytes())
info.update(CFBundleDisplayName="NetHack", CFBundleShortVersionString="0.2.0", CFBundleVersion=os.environ.get("GITHUB_RUN_NUMBER", "2"), UIFileSharingEnabled=True, LSSupportsOpeningDocumentsInPlace=True)
(app/"Info.plist").write_bytes(plistlib.dumps(info))
data=app/"GameData"
data.mkdir(exist_ok=True)
for file in (ROOT/"dat").iterdir():
    if file.is_file() and file.name not in ("Makefile",): shutil.copy2(file,data/file.name)
shutil.copy2(ROOT/"sys/android/defaults.nh",data/"defaults.nh")
for file in (ROOT/"sys/android/app/res/drawable-nodpi").glob("*.png"): shutil.copy2(file,app/file.name)
ipa=OUT/"NetHack-ios-unsigned.ipa"
with zipfile.ZipFile(ipa,"w",zipfile.ZIP_DEFLATED) as archive:
    for file in app.rglob("*"):
        if file.is_file(): archive.write(file,file.relative_to(OUT))
print(f"Created {ipa}", flush=True)
