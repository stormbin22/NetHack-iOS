"""Launch the UIKit app in an iPhone simulator and capture its first game map."""
from pathlib import Path
import concurrent.futures
import json
import os
import platform
import re
import shutil
import subprocess
import time

root=Path(__file__).resolve().parents[2]
os.chdir(root)
out=root/"build/ios"
def run(*args):
    return subprocess.check_output([str(a) for a in args],text=True).strip()
sdk=run("xcrun","--sdk","iphonesimulator","--show-sdk-path")
target=["-target",f"{platform.machine()}-apple-ios16.0-simulator","-isysroot",sdk]
flags=["-std=c99","-O1","-fsigned-char","-DANDROID","-DSND_LIB_ANDROIDSOUND","-Iinclude","-Isys/ios",f"-I{out}/lua-5.4.8/src"]
source_list=re.search(r"HACKCSRC \?= (.*?)(?:\n\n)",(root/"sys/android/Makefile.src").read_text(),re.S)[1]
sources=["src/"+s for s in source_list.replace("\\\n"," ").split()]
sources += ["src/cfgfiles.c","src/date.c","src/tile.c","sys/ios/platform.c","sys/share/posixregex.c","sys/share/ioctl.c","sys/share/unixtty.c","sys/android/androidmain.c","sys/android/androidunix.c","sys/android/winandroid.c"]
sources += [str(p) for p in (out/"lua-5.4.8/src").glob("*.c") if p.name not in ("lua.c","luac.c")]
objects=out/"sim-objects"
objects.mkdir(exist_ok=True)
def compile(source):
    obj=objects/(Path(source).stem+".o")
    run("xcrun","clang",*target,*flags,"-c",source,"-o",obj)
    return obj
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    compiled=list(pool.map(compile,sources))
for name in ("Bridge.m","GameApp.m"):
    obj=objects/(name+".o")
    run("xcrun","clang",*target,"-fobjc-arc","-fmodules","-Isys/ios","-c","sys/ios/"+name,"-o",obj)
    compiled.append(obj)
app=out/"Simulator/NetHack.app"
shutil.copytree(out/"Payload/NetHack.app",app,dirs_exist_ok=True)
run("xcrun","clang",*target,*compiled,"-framework","UIKit","-framework","Foundation","-o",app/"NetHack")
run("codesign","--force","--sign","-",app)
available=json.loads(run("xcrun","simctl","list","devices","available","--json"))["devices"]
phones=[d for devices in available.values() for d in devices if "iPhone" in d["name"]]
device=next((d for d in phones if d["name"]=="iPhone 14 Pro"),phones[0])
udid=device["udid"]
print("UI test device:",device["name"],flush=True)
if device["state"]!="Booted":run("xcrun","simctl","boot",udid)
run("xcrun","simctl","bootstatus",udid,"-b")
run("xcrun","simctl","install",udid,app)
run("xcrun","simctl","launch",udid,"org.nethack.personal.ios","--ui-smoke")
container=Path(run("xcrun","simctl","get_app_container",udid,"org.nethack.personal.ios","data"))
for marker,filename in (("UI_READY","ios-game-screen.png"),("UI_KEYBOARD","ios-keyboard-screen.png"),("UI_SETTINGS","ios-settings-screen.png")):
    ready=container/"Documents"/marker
    for _ in range(45):
        if ready.exists():break
        time.sleep(1)
    time.sleep(1)
    run("xcrun","simctl","io",udid,"screenshot",out/filename)
    if not ready.exists():raise RuntimeError(f"UIKit check did not finish: {marker}")
    print(f"PASS: {marker}",flush=True)
print("PASS: Gurr command input, map, HP status, keyboard and settings",flush=True)
