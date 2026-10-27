#!/usr/bin/env python3
"""Genera las páginas de instalación para GitHub Pages (lo usa scripts/publish-pages.sh).

  pages.py build DIR       escribe manifest.plist, index.html y build.json de un build en DIR
                           (DIR ya contiene el .ipa y los iconos; los datos llegan por entorno)
  pages.py site SITE KEEP  borra los builds de ramas más allá de los KEEP más recientes y
                           escribe la portada (index.html) y .nojekyll
  pages.py titles SITE     adds commit_title to the build.json files published before that
                           field existed, reading the commit title from GitHub
"""

import html
import json
import os
import plistlib
import shutil
import subprocess
import sys
import urllib.parse
from datetime import datetime, timezone

STYLE = """
:root { color-scheme: light dark; --bg:#f2f2f7; --card:#fff; --text:#1c1c1e; --muted:#6e6e73; --accent:#c8671d; --line:#d1d1d6; }
@media (prefers-color-scheme: dark) { :root { --bg:#000; --card:#1c1c1e; --text:#f2f2f7; --muted:#98989f; --line:#38383a; } }
* { box-sizing: border-box; }
body { margin:0; padding:24px 16px 48px; background:var(--bg); color:var(--text);
       font:16px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { max-width:640px; margin:0 auto; }
h1 { font-size:28px; margin:0 0 4px; } h2 { font-size:20px; margin:32px 0 12px; }
.muted { color:var(--muted); font-size:14px; }
.card { background:var(--card); border-radius:16px; padding:20px; margin:16px 0; }
.hero { display:flex; gap:16px; align-items:center; }
.hero img { width:72px; height:72px; border-radius:16px; }
.button { display:block; text-align:center; background:var(--accent); color:#fff; text-decoration:none;
          font-weight:600; padding:14px 18px; border-radius:12px; margin-top:16px; }
.button.small { display:inline-block; padding:8px 14px; margin:0; font-size:14px; }
ul.builds { list-style:none; margin:0; padding:0; }
ul.builds li { display:flex; justify-content:space-between; align-items:center; gap:12px;
               padding:12px 0; border-top:1px solid var(--line); }
ul.builds li:first-child { border-top:0; }
ul.builds a.name { color:var(--text); font-weight:600; text-decoration:none; }
ul.builds li > div { min-width:0; }
.commit { font-size:15px; margin-top:2px; overflow-wrap:anywhere; }
.badge { font-size:12px; font-weight:600; padding:2px 8px; border-radius:999px; margin-left:6px;
         background:var(--line); color:var(--text); }
.badge.stable { background:#2e8b57; color:#fff; }
dl { display:grid; grid-template-columns:max-content 1fr; gap:4px 12px; margin:0; font-size:14px; }
dt { color:var(--muted); } dd { margin:0; overflow-wrap:anywhere; }
"""


def page(title, body):
    return f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>{STYLE}</style>
</head>
<body><main>
{body}
</main></body>
</html>
"""


def install_url(manifest_url):
    return "itms-services://?action=download-manifest&url=" + urllib.parse.quote(manifest_url, safe="")


def cmd_build(folder):
    e = os.environ
    base = e["BASE_URL"].rstrip("/") + "/"
    tag = e["TAG"]
    folder_url = base + urllib.parse.quote(tag) + "/"
    ipa = e["IPA_NAME"]
    info = {
        "tag": tag,
        "channel": e["CHANNEL"],  # "stable" (main) o "branch"
        "branch": e["BRANCH"],
        "commit": e["COMMIT"],
        "commit_title": e.get("COMMIT_TITLE", ""),
        "title": e["TITLE"],
        "bundle_id": e["BUNDLE_ID"],
        "version": e["VERSION"],
        "build": e["BUILD_NUMBER"],
        "devices": int(e.get("DEVICES") or 0),
        "ipa": ipa,
        "run_url": e.get("RUN_URL", ""),
        "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "page_url": folder_url,
        "manifest_url": folder_url + "manifest.plist",
    }
    info["install_url"] = install_url(info["manifest_url"])

    manifest = {
        "items": [{
            "assets": [
                {"kind": "software-package", "url": folder_url + urllib.parse.quote(ipa)},
                {"kind": "display-image", "url": folder_url + "icon-57.png"},
                {"kind": "full-size-image", "url": folder_url + "icon-512.png"},
            ],
            "metadata": {
                "bundle-identifier": info["bundle_id"],
                "bundle-version": info["version"],
                "kind": "software",
                "title": info["title"],
            },
        }]
    }
    with open(os.path.join(folder, "manifest.plist"), "wb") as handle:
        plistlib.dump(manifest, handle)
    with open(os.path.join(folder, "build.json"), "w") as handle:
        json.dump(info, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    esc = html.escape
    kind = "Versión estable" if info["channel"] == "stable" else f"Pre-release de la rama {info['branch']}"
    run = f'<dt>Ejecución</dt><dd><a href="{esc(info["run_url"])}">ver en GitHub Actions</a></dd>' if info["run_url"] else ""
    commit = esc(info["commit"][:7])
    if info["commit_title"]:
        commit += f" · {esc(info['commit_title'])}"
    body = f"""
<p class="muted"><a href="../">← Todos los builds</a></p>
<div class="card">
  <div class="hero">
    <img src="icon-512.png" alt="">
    <div><h1>{esc(info['title'])}</h1><div class="muted">{esc(tag)} · {esc(kind)}</div></div>
  </div>
  <a class="button" href="{esc(info['install_url'])}">Instalar en este iPhone</a>
  <p class="muted">Abre esta página en Safari en el iPhone. Sólo se instala en los dispositivos registrados
  en la cuenta de Apple Developer ({info['devices']} en este build).</p>
</div>
<div class="card">
  <dl>
    <dt>Versión</dt><dd>{esc(info['version'])} ({esc(info['build'])})</dd>
    <dt>Bundle ID</dt><dd>{esc(info['bundle_id'])}</dd>
    <dt>Rama</dt><dd>{esc(info['branch'])}</dd>
    <dt>Commit</dt><dd>{commit}</dd>
    <dt>Fecha</dt><dd>{esc(info['created_at'])}</dd>
    {run}
    <dt>Archivo</dt><dd><a href="{esc(urllib.parse.quote(ipa))}">{esc(ipa)}</a></dd>
  </dl>
</div>
"""
    with open(os.path.join(folder, "index.html"), "w") as handle:
        handle.write(page(f"{info['title']} {tag}", body))


def version_key(tag):
    try:
        return tuple(int(part) for part in tag.split("."))
    except ValueError:
        return (-1,)


def cmd_titles(site):
    # Builds published before commit_title was stored only have the commit hash, so ask GitHub for its title.
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not repo or not shutil.which("gh"):
        return
    for name in os.listdir(site):
        path = os.path.join(site, name, "build.json")
        if not os.path.isfile(path):
            continue
        with open(path) as handle:
            info = json.load(handle)
        if info.get("commit_title"):
            continue
        result = subprocess.run(
            ["gh", "api", f"repos/{repo}/commits/{info['commit']}", "--jq", ".commit.message"],
            capture_output=True, text=True, check=False,
        )
        lines = result.stdout.splitlines()
        if result.returncode != 0 or not lines:
            print(f"warning: no commit title for {name}: {result.stderr.strip()}", file=sys.stderr)
            continue
        info["commit_title"] = lines[0]
        with open(path, "w") as handle:
            json.dump(info, handle, indent=2, ensure_ascii=False)
            handle.write("\n")


def cmd_site(site, keep):
    builds = []
    for name in os.listdir(site):
        path = os.path.join(site, name, "build.json")
        if os.path.isfile(path):
            with open(path) as handle:
                builds.append(json.load(handle))

    branch_builds = sorted((b for b in builds if b["channel"] != "stable"),
                           key=lambda b: b["created_at"], reverse=True)
    for old in branch_builds[keep:]:
        shutil.rmtree(os.path.join(site, old["tag"]))
    removed = {b["tag"] for b in branch_builds[keep:]}
    builds = sorted((b for b in builds if b["tag"] not in removed), key=lambda b: b["created_at"], reverse=True)
    stable = sorted((b for b in builds if b["channel"] == "stable"),
                    key=lambda b: (version_key(b["tag"]), b["created_at"]), reverse=True)

    esc = html.escape
    title = (stable or builds)[0]["title"] if builds else "Builds"
    if stable:
        latest = stable[0]
        hero = f"""
<div class="card">
  <div class="hero">
    <img src="{esc(latest['tag'])}/icon-512.png" alt="">
    <div><h1>{esc(latest['title'])}</h1><div class="muted">Última versión estable: {esc(latest['tag'])}</div></div>
  </div>
  <a class="button" href="{esc(latest['install_url'])}">Instalar la última versión estable</a>
  <p class="muted">Abre esta página en Safari en un iPhone registrado en la cuenta de Apple Developer.</p>
</div>"""
    else:
        hero = f"""
<div class="card"><h1>{esc(title)}</h1>
  <p class="muted">Todavía no hay una versión estable (se publica una con cada push a main).</p></div>"""

    rows = []
    for b in builds:
        badge = '<span class="badge stable">estable</span>' if b["channel"] == "stable" else \
            f'<span class="badge">{esc(b["branch"])}</span>'
        commit_line = f'<div class="commit">{esc(b["commit_title"])}</div>' if b.get("commit_title") else ""
        rows.append(f"""  <li>
    <div><a class="name" href="{esc(b['tag'])}/">{esc(b['tag'])}</a>{badge}
      {commit_line}
      <div class="muted">{esc(b['version'])} ({esc(b['build'])}) · {esc(b['commit'][:7])} · {esc(b['created_at'][:16].replace('T', ' '))} UTC</div></div>
    <a class="button small" href="{esc(b['install_url'])}">Instalar</a>
  </li>""")
    listing = "\n".join(rows) or '  <li class="muted">No hay builds publicados.</li>'
    body = f"""{hero}
<h2>Todos los builds</h2>
<div class="card"><ul class="builds">
{listing}
</ul></div>
<p class="muted">Se guardan todas las versiones de main y los últimos {keep} builds de otras ramas.</p>
"""
    with open(os.path.join(site, "index.html"), "w") as handle:
        handle.write(page(title, body))
    open(os.path.join(site, ".nojekyll"), "w").close()


def main(argv):
    if len(argv) == 3 and argv[1] == "build":
        cmd_build(argv[2])
    elif len(argv) == 3 and argv[1] == "titles":
        cmd_titles(argv[2])
    elif len(argv) == 4 and argv[1] == "site":
        cmd_site(argv[2], int(argv[3]))
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
