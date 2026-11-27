#!/usr/bin/env python3
"""Download the flags and coats of arms KeyFlag bundles from Wikimedia Commons.

Scripts/wikimedia-flags.json and Scripts/wikimedia-arms.json map a flag code to a Commons
file name. Each file is fetched as Commons' own PNG render (SVG originals included) at
150 px high into Resources/Flags/<CODE>.png and Resources/CoatsOfArms/<CODE>.png, and
Resources/Wikimedia-Credits.md lists the source, author and license of every image.

Where Commons has no plain shield for a coat of arms, the arms entry can instead be
{"file": ..., "crop": [left, top, right, bottom], "shape": ...}: the box (fractions of the
image) is cut out of a larger render and clipped to the shield's outline by
Scripts/crop-arms.swift, leaving out the supporters, mantle and motto.

    /usr/bin/python3 Scripts/fetch-wikimedia-art.py            # everything
    /usr/bin/python3 Scripts/fetch-wikimedia-art.py GB-WLS CZ  # only these codes
"""
import html, json, math, os, re, subprocess, sys, tempfile, time, urllib.parse, urllib.request
from urllib.error import HTTPError

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SETS = [("flags", "Flags", "Flags"), ("arms", "CoatsOfArms", "Coats of arms")]
HEIGHT = 150
UA = {"User-Agent": "KeyFlag-build-script/1.0 (+https://github.com/kurtcz/KeyFlag)"}

def get(url):
    for attempt in range(6):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA)).read()
        except HTTPError as error:
            if error.code != 429:
                raise
            time.sleep(10 * (attempt + 1))  # Commons rate limit
    raise SystemExit("Rate limited: " + url)

def text(value):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", value or ""))).strip()

def api(title, **size):
    query = urllib.parse.urlencode(dict(action="query", titles="File:" + title, redirects=1, prop="imageinfo",
                                        iiprop="url|size|extmetadata", format="json", formatversion="2", **size))
    return json.loads(get("https://commons.wikimedia.org/w/api.php?" + query))["query"]["pages"][0]

def fetch(entry, path):
    title = entry if isinstance(entry, str) else entry["file"]
    crop = None if isinstance(entry, str) else entry["crop"]
    page = api(title, iiurlheight=HEIGHT)
    info = page["imageinfo"][0]
    meta = info.get("extmetadata", {})
    if crop:
        # Render the whole image large enough that the crop is twice the final height, then cut it out.
        left, top, right, bottom = crop
        width = math.ceil(2 * HEIGHT / (bottom - top) * info["width"] / info["height"])
        data = get(api(title, iiurlwidth=width)["imageinfo"][0]["thumburl"])
    else:
        data = get(info["thumburl"])
    if not data.startswith(b"\x89PNG"):
        raise SystemExit(f"{title}: not a PNG render")
    if crop:
        with tempfile.NamedTemporaryFile(suffix=".png") as render:
            render.write(data)
            render.flush()
            subprocess.run(["swift", os.path.join(ROOT, "Scripts", "crop-arms.swift"), render.name, path,
                            *map(str, crop), entry.get("shape", "rect"), str(HEIGHT)], check=True)
    else:
        with open(path, "wb") as file:
            file.write(data)
    return dict(file=page["title"][5:], url=info["descriptionurl"], cropped=bool(crop),
                author=text(meta.get("Artist", {}).get("value")) or "unknown",
                license=text(meta.get("LicenseShortName", {}).get("value")) or "see source")

def main():
    only = {code.upper() for code in sys.argv[1:]}
    credits_path = os.path.join(ROOT, "Resources", "Wikimedia-Credits.json")
    credits = json.load(open(credits_path)) if os.path.exists(credits_path) else {}
    for key, folder, _ in SETS:
        mapping = json.load(open(os.path.join(ROOT, "Scripts", f"wikimedia-{key}.json")))
        os.makedirs(os.path.join(ROOT, "Resources", folder), exist_ok=True)
        credits.setdefault(key, {})
        for code, entry in sorted(mapping.items()):
            if only and code not in only:
                continue
            credits[key][code] = fetch(entry, os.path.join(ROOT, "Resources", folder, code + ".png"))
            print(folder, code, credits[key][code]["license"])
            time.sleep(1)
    with open(credits_path, "w") as file:
        json.dump(credits, file, indent=1, ensure_ascii=False, sort_keys=True)
    write_markdown(credits)

def write_markdown(credits):
    lines = ["# Wikimedia Commons credits", "",
             "KeyFlag's bundled flags (`Resources/Flags`) and coats of arms (`Resources/CoatsOfArms`) are PNG "
             "renders of these Wikimedia Commons files, scaled down. Each keeps its own license, shown below; "
             "they are not covered by KeyFlag's MIT license. Arms marked \u2702 show only the shield, "
             "cut out of the full achievement. Regenerate with `Scripts/fetch-wikimedia-art.py`.", ""]
    for key, _, heading in SETS:
        lines += [f"## {heading}", "", "| Code | File | Author | License |", "|---|---|---|---|"]
        for code, c in sorted(credits.get(key, {}).items()):
            author = c["author"].replace("|", "/")
            if len(author) > 160:
                author = author[:157] + "…"
            mark = " \u2702" if c.get("cropped") else ""
            lines.append(f"| {code} | [{c['file']}]({c['url']}){mark} | {author} | {c['license']} |")
        lines.append("")
    with open(os.path.join(ROOT, "Resources", "Wikimedia-Credits.md"), "w") as file:
        file.write("\n".join(lines))

if __name__ == "__main__":
    main()
