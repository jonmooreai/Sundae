#!/usr/bin/env python3
"""Make a new iOS app from the template in assets/template.

    python3 scripts/new_app.py --name "Tally" --repo jonmooreai/tally --dest ~/tally \
        --pitch "Count anything, together." --d1-id 1234abcd-... [options]

Copies the template, fills every placeholder, renames the __APP_TYPE__ folders, writes an
app icon in the accent colour, and checks nothing was left unfilled. Standard library only, so it
runs anywhere Python 3.9+ does. Refuses to write into a folder that has anything but .git in it.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import struct
import sys
import zlib

SKILL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(SKILL, "assets", "template")
PLACEHOLDER = re.compile(r"__[A-Z][A-Z0-9_]*__")
BINARY = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".heic"}
SWIFT_KEYWORDS = {
    "App", "View", "Scene", "Color", "Text", "Image", "Button", "List", "Form", "Task", "Data",
    "Date", "URL", "User", "Note", "Theme", "Keychain", "Model", "Test", "Tests", "Shared",
}


def fail(message):
    print(f"new_app: {message}", file=sys.stderr)
    sys.exit(1)


def type_name(name):
    """'Tally Ho!' -> 'TallyHo'. A Swift type and module name: letters and digits, a letter first."""
    words = re.findall(r"[A-Za-z0-9]+", name)
    joined = "".join(w[:1].upper() + w[1:] for w in words)
    if not joined or not joined[0].isalpha():
        fail(f"can't make a Swift type name from {name!r}; pass --type")
    return joined


def slug(name):
    """'Tally Ho!' -> 'tally-ho'. For the Worker, the database, the SKU."""
    value = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    if not value:
        fail(f"can't make a slug from {name!r}; pass --slug")
    return value


def hex_colour(value):
    match = re.fullmatch(r"#?([0-9A-Fa-f]{6})", value)
    if not match:
        fail(f"--accent wants a colour like #52705C, not {value!r}")
    raw = match.group(1)
    return tuple(int(raw[i:i + 2], 16) for i in (0, 2, 4))


def mix(colour, other, amount):
    return tuple(round(c + (o - c) * amount) for c, o in zip(colour, other))


def write_png(path, width, height, pixel):
    """An RGB PNG (no alpha: App Store icons must not have one), one row at a time."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixel(x, y))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def write_icon(path, accent, size=1024):
    """A starting icon: the accent colour, a soft lighter disc and a small white one, centred.
    Plain on purpose; swap in a real one (references/ios-app.md, "App icon") before release."""
    top = mix(accent, (255, 255, 255), 0.12)
    bottom = mix(accent, (0, 0, 0), 0.10)
    disc = mix(accent, (255, 255, 255), 0.28)
    centre = size / 2
    outer, inner = size * 0.30, size * 0.12

    def blend(base, colour, coverage):
        return tuple(round(b + (c - b) * coverage) for b, c in zip(base, colour))

    def pixel(x, y):
        base = mix(top, bottom, y / (size - 1))
        distance = ((x + 0.5 - centre) ** 2 + (y + 0.5 - centre) ** 2) ** 0.5
        base = blend(base, disc, max(0.0, min(1.0, outer - distance + 0.5)))
        base = blend(base, (255, 255, 255), max(0.0, min(1.0, inner - distance + 0.5)))
        return bytes(base)

    write_png(path, size, size, pixel)


def colourset(light, dark):
    def entry(rgb, appearance=None):
        item = {
            "color": {
                "color-space": "srgb",
                "components": {
                    "alpha": "1.000",
                    "red": f"0x{rgb[0]:02X}",
                    "green": f"0x{rgb[1]:02X}",
                    "blue": f"0x{rgb[2]:02X}",
                },
            },
            "idiom": "universal",
        }
        if appearance:
            item["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        return item

    return json.dumps({"colors": [entry(light), entry(dark, "dark")], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--name", required=True, help="Display name under the icon, e.g. 'Tally'")
    parser.add_argument("--dest", required=True, help="Folder to create (or an empty clone)")
    parser.add_argument("--repo", required=True, help="GitHub owner/repo, e.g. jonmooreai/tally")
    parser.add_argument("--pitch", required=True, help="One sentence: what the app is for")
    parser.add_argument("--type", help="Swift type and module name (default: from --name)")
    parser.add_argument("--slug", help="Lowercase name for the Worker and database (default: from --name)")
    parser.add_argument("--bundle-prefix", default="com.jonmooreai")
    parser.add_argument("--bundle-id", help="Default: <bundle-prefix>.<slug without hyphens>")
    parser.add_argument("--d1-id", default="", help="The D1 database's id; without it, wrangler.jsonc is left to fill in")
    parser.add_argument("--workers-subdomain", default="sundae-fam", help="The Cloudflare account's workers.dev subdomain")
    parser.add_argument("--live", action="store_true", help="Point the app at the server now (default: demo data until it is deployed)")
    parser.add_argument("--match-git-url", default="https://github.com/jonmooreai/sundae-private.git",
                        help="The shared private certificates repository")
    parser.add_argument("--git-name", default="jonmooreai")
    parser.add_argument("--git-email", default="118233078+jonmooreai@users.noreply.github.com")
    parser.add_argument("--accent", default="#52705C", help="Accent colour, also the icon's")
    args = parser.parse_args()

    app_type = args.type or type_name(args.name)
    if not re.fullmatch(r"[A-Z][A-Za-z0-9]*", app_type):
        fail(f"--type must be UpperCamelCase letters and digits, not {app_type!r}")
    if app_type in SWIFT_KEYWORDS:
        fail(f"{app_type!r} clashes with a type the template already uses; pass --type, e.g. {app_type}App")
    app_slug = args.slug or slug(args.name)
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,40}", app_slug):
        fail(f"--slug must be lowercase letters, digits and hyphens, starting with a letter, not {app_slug!r}")
    bundle_id = args.bundle_id or f"{args.bundle_prefix}.{app_slug.replace('-', '')}"
    if not re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+", bundle_id):
        fail(f"{bundle_id!r} is not a bundle id")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repo):
        fail("--repo is owner/repo")
    # The name lands in Swift, JavaScript, YAML and HTML as it is, so it keeps to characters
    # that mean nothing special in any of them.
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 .-]{0,29}", args.name):
        fail("--name is up to 30 letters, digits, spaces, dots or hyphens")
    if len(args.name) > 12:
        print(f"new_app: note: {args.name!r} may be cut short under the icon; a Home Screen name fits about 12 characters")
    if "\u2014" in args.pitch or PLACEHOLDER.search(args.pitch):
        fail("--pitch can't contain em-dashes or __PLACEHOLDERS__")
    if args.d1_id and not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", args.d1_id):
        fail("--d1-id is the database's UUID")

    dest = os.path.abspath(os.path.expanduser(args.dest))
    if os.path.exists(dest):
        extra = [entry for entry in os.listdir(dest) if entry != ".git"]
        if extra:
            fail(f"{dest} already has {', '.join(sorted(extra)[:5])}; choose an empty folder")
    os.makedirs(dest, exist_ok=True)

    today = datetime.date.today()
    api_url = f"https://{app_slug}-api.{args.workers_subdomain}.workers.dev"
    values = {
        "__APP_NAME__": args.name,
        "__APP_TYPE__": app_type,
        "__APP_SLUG__": app_slug,
        "__APP_PITCH__": args.pitch,
        "__BUNDLE_PREFIX__": args.bundle_prefix,
        "__BUNDLE_ID__": bundle_id,
        "__GITHUB_REPO__": args.repo,
        "__API_BASE_URL__": api_url,
        "__APP_API_BASE_URL__": api_url if args.live else "",
        "__D1_DATABASE_ID__": args.d1_id or "FILL-IN-THE-D1-DATABASE-ID",
        "__MATCH_GIT_URL__": args.match_git_url,
        "__GIT_NAME__": args.git_name,
        "__GIT_EMAIL__": args.git_email,
        "__TODAY__": today.isoformat(),
        # A week back, so it is never ahead of the runtime Workers Builds deploys with.
        "__COMPAT_DATE__": (today - datetime.timedelta(days=7)).isoformat(),
    }

    def fill(text):
        for key, value in values.items():
            text = text.replace(key, value)
        return text

    written = []
    for root, dirs, files in os.walk(TEMPLATE):
        dirs.sort()
        rel_root = os.path.relpath(root, TEMPLATE)
        out_root = os.path.join(dest, fill(rel_root)) if rel_root != "." else dest
        os.makedirs(out_root, exist_ok=True)
        for name in sorted(files):
            if name == ".DS_Store":
                continue
            src = os.path.join(root, name)
            out = os.path.join(out_root, fill(name))
            if os.path.splitext(name)[1].lower() in BINARY:
                shutil.copyfile(src, out)
            else:
                with open(src, encoding="utf-8") as handle:
                    text = fill(handle.read())
                with open(out, "w", encoding="utf-8") as handle:
                    handle.write(text)
            shutil.copymode(src, out)
            written.append(out)

    accent = hex_colour(args.accent)
    assets = os.path.join(dest, app_type, "Resources", "Assets.xcassets")
    with open(os.path.join(assets, "AccentColor.colorset", "Contents.json"), "w") as handle:
        handle.write(colourset(accent, mix(accent, (255, 255, 255), 0.15)))
    icon = os.path.join(assets, "AppIcon.appiconset", "AppIcon.png")
    write_icon(icon, accent)
    written.append(icon)

    for path in ("scripts/pick_simulators.py", "scripts/collect_screenshots.py"):
        full = os.path.join(dest, path)
        if os.path.exists(full):
            os.chmod(full, 0o755)

    leftovers, dashes = [], []
    for path in written:
        if path.endswith(".png"):
            continue
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        rel = os.path.relpath(path, dest)
        leftovers += [f"{rel}: {token}" for token in sorted(set(PLACEHOLDER.findall(text)))]
        if "\u2014" in text:
            dashes.append(rel)
        if PLACEHOLDER.search(rel):
            leftovers.append(f"{rel}: in the path")
    if leftovers:
        fail("placeholders left unfilled:\n  " + "\n  ".join(leftovers))
    if dashes:
        fail("em-dashes found in: " + ", ".join(dashes))

    print(f"Made {args.name} in {dest}")
    print(f"  Swift type and module  {app_type}")
    print(f"  Bundle id              {bundle_id}")
    print(f"  Worker                 {app_slug}-api, at {api_url}")
    print(f"  D1 database            {app_slug}" + ("" if args.d1_id else "  (id still to fill in, in wrangler.jsonc)"))
    print(f"  App points at          {'the server' if args.live else 'demo data (set APIBaseURL in project.yml once the server answers)'}")
    print()
    print("Next:")
    print(f"  cd {dest}/server/api && node --test --no-warnings")
    print(f"  git add -A && git commit -m 'Start {args.name}' && git push -u origin HEAD:claude/start")
    print("  Then docs/SETUP.md for the owner's one-time steps.")


if __name__ == "__main__":
    main()
