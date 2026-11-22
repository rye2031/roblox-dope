#!/usr/bin/env python3
"""Download the tools listed in tools.lock.json and verify each one.

Run from anywhere:  python3 -I scripts/fetch_tools.py

A download is refused unless it is at least `minAgeDays` old, comes from
github.com over HTTPS, and matches the size and SHA-256 in the lock file.
Nothing is extracted or made executable before it passes those checks.
Uses the Python standard library only.
"""
import datetime
import hashlib
import json
import os
import shutil
import stat
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOWED_HOSTS = {"github.com"}


def fail(msg):
    sys.exit(f"fetch_tools: {msg}")


def inside_tools(rel):
    path = os.path.realpath(os.path.join(ROOT, rel))
    tools = os.path.realpath(os.path.join(ROOT, "tools"))
    if not path.startswith(tools + os.sep):
        fail(f"{rel} is outside tools/")
    return path


def download(tool, dest):
    url = urllib.parse.urlparse(tool["url"])
    if url.scheme != "https" or url.hostname not in ALLOWED_HOSTS:
        fail(f"{tool['name']}: url must be https on {sorted(ALLOWED_HOSTS)}")
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(tool["url"], timeout=60) as resp, open(dest, "wb") as out:
        while chunk := resp.read(1 << 16):
            size += len(chunk)
            if size > tool["size"]:
                fail(f"{tool['name']}: larger than the locked size")
            digest.update(chunk)
            out.write(chunk)
    if size != tool["size"] or digest.hexdigest() != tool["sha256"]:
        fail(f"{tool['name']}: size or SHA-256 does not match tools.lock.json")


def main():
    with open(os.path.join(ROOT, "tools.lock.json")) as f:
        lock = json.load(f)
    min_age = datetime.timedelta(days=lock["policy"]["minAgeDays"])
    today = datetime.date.today()

    for tool in lock["tools"]:
        label = f"{tool['name']} {tool['version']}"
        published = datetime.date.fromisoformat(tool["published"])
        if today - published < min_age:
            fail(f"{label}: published {published}, newer than {min_age.days} days")

        with tempfile.TemporaryDirectory() as tmp:
            archive = os.path.join(tmp, "download")
            download(tool, archive)

            if "extractTo" in tool:
                target = inside_tools(tool["extractTo"])
                shutil.rmtree(target, ignore_errors=True)
                os.makedirs(target)
                with zipfile.ZipFile(archive) as z:
                    z.extractall(target)
                exe = os.path.join(target, tool["executable"])
                os.chmod(exe, os.stat(exe).st_mode | stat.S_IXUSR)
            else:
                target = inside_tools(tool["saveTo"])
                os.makedirs(os.path.dirname(target), exist_ok=True)
                shutil.move(archive, target)
        print(f"ok  {label}  sha256 verified")


if __name__ == "__main__":
    main()
