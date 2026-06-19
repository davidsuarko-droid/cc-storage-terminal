#!/usr/bin/env python3
"""Extract flat item-icon PNGs from Minecraft mod jars for cc-storage-terminal.

Reads assets/<ns>/models/item/<name>.json; for item/generated|handheld models
(those with textures.layer0) pulls assets/<ns>/textures/<layer0>.png into
icons/<ns>__<name>.png. 3D/block models (no layer0) are skipped. Writes
icons/manifest.txt listing available item ids.

Usage:
  python3 scripts/build-icons.py <jars_dir> [--out icons]
The jars_dir is the modpack 'mods/' folder (pull via SFTP into a local cache
first; creds in memory reference-minecraft-server-sftp).
"""
import argparse
import json
import os
import sys
import zipfile

ITEM_PARENTS = ("item/generated", "item/handheld")


def texture_to_path(tex):
    # "create:item/cogwheel" -> ("create", "item/cogwheel")
    if ":" in tex:
        ns, rest = tex.split(":", 1)
    else:
        ns, rest = "minecraft", tex
    return ns, rest


def layer0_of(model):
    parent = model.get("parent", "") or ""
    if not any(p in parent for p in ITEM_PARENTS):
        return None
    return (model.get("textures") or {}).get("layer0")


def process_jar(path, out_dir, manifest):
    try:
        zf = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        print(f"skip (bad zip): {path}")
        return 0
    written = 0
    names = zf.namelist()
    nameset = set(names)
    for entry in names:
        # assets/<ns>/models/item/<name>.json
        parts = entry.split("/")
        if len(parts) < 5 or parts[0] != "assets" or parts[2] != "models" or parts[3] != "item":
            continue
        if not entry.endswith(".json"):
            continue
        ns = parts[1]
        item = "/".join(parts[4:])[:-5]  # strip .json, keep nested name
        try:
            model = json.loads(zf.read(entry))
        except (json.JSONDecodeError, KeyError):
            continue
        layer0 = layer0_of(model)
        if not layer0:
            continue
        tns, trest = texture_to_path(layer0)
        tex_entry = f"assets/{tns}/textures/{trest}.png"
        if tex_entry not in nameset:
            continue
        out_name = f"{ns}__{item.replace('/', '_')}.png"
        with open(os.path.join(out_dir, out_name), "wb") as fh:
            fh.write(zf.read(tex_entry))
        manifest.add(f"{ns}:{item}")
        written += 1
    zf.close()
    return written


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jars_dir")
    ap.add_argument("--out", default="icons")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    manifest = set()
    total = 0
    jars = [f for f in os.listdir(args.jars_dir) if f.endswith(".jar")]
    if not jars:
        print(f"no jars in {args.jars_dir}", file=sys.stderr)
        sys.exit(1)
    for j in sorted(jars):
        n = process_jar(os.path.join(args.jars_dir, j), args.out, manifest)
        if n:
            print(f"{j}: {n} icons")
        total += n
    with open(os.path.join(args.out, "manifest.txt"), "w") as fh:
        for item_id in sorted(manifest):
            fh.write(item_id + "\n")
    print(f"done: {total} icons, {len(manifest)} ids -> {args.out}/manifest.txt")


if __name__ == "__main__":
    main()
