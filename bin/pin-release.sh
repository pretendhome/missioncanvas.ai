#!/usr/bin/env bash
# Pin the site's download buttons to a desktop release — safely, or not at all.
#
# Why this exists
# ---------------
# Until 2026-09-19 the buttons were hand-edited in two files, and before that by
# a sed in auto-release.yml that assumed tags looked like desktop-vX.Y.Z. The
# north-star tags do not (desktop-v0.3.5-north-star.20260919), so that sed would
# have produced desktop-v0.3.6-...-north-star.20260919 — a doubled suffix
# pointing at nothing. auto-release.yml has not succeeded since 2026-09-05, so
# every pin since 0.3.0 has in fact been done by hand.
#
# This script replaces the WHOLE tag between /releases/download/ and the asset
# name, so tag shape never matters. It verifies every installer really downloads
# BEFORE it commits, and it touches nothing if any check fails, so a failed run
# leaves the previous working build pinned rather than a dead button.
#
# It deliberately never uses .../releases/latest/download/<asset>. In this repo
# that URL 302s and then 404s: four release trains share it, `latest` currently
# resolves to a Tropical IT release, and the desktop releases are prereleases so
# they can never be `latest`. A HEAD check sees the 302 and reports success.
#
# Usage
#   bin/pin-release.sh                 # pin the newest desktop-v* release
#   bin/pin-release.sh <tag>           # pin a specific tag (rollback)
#   bin/pin-release.sh --dry-run       # show the diff, change nothing
#   bin/pin-release.sh <tag> --dry-run
set -euo pipefail

REPO="pretendhome/missioncanvas.ai"
ASSETS=(MissionCanvas.dmg MissionCanvas-Setup.exe MissionCanvas.AppImage)
FILES=(index.html apps/index.html)

cd "$(dirname "$0")/.."

TAG=""; DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) TAG="$arg" ;;
  esac
done

command -v gh >/dev/null || { echo "FAIL: gh is not installed" >&2; exit 1; }

if [ -z "$TAG" ]; then
  echo "Finding the newest desktop-v* release in $REPO ..."
  TAG=$(gh api "repos/$REPO/releases?per_page=100" \
        --jq '[.[] | select(.tag_name | startswith("desktop-v"))]
              | sort_by(.published_at) | reverse | .[0].tag_name')
  [ -n "$TAG" ] && [ "$TAG" != "null" ] || { echo "FAIL: no desktop-v* release found" >&2; exit 1; }
fi
echo "Tag: $TAG"

# ---- verify every installer actually downloads, before touching a file ------
echo "Verifying installers resolve and download ..."
for a in "${ASSETS[@]}"; do
  url="https://github.com/$REPO/releases/download/$TAG/$a"
  # -L follows the redirect to the CDN; a tag/asset that does not exist 404s here.
  # Note the trailing newline in -w: without it `read` hits EOF and, under
  # `set -e`, kills the script after printing nothing. That bug was here once.
  out=$(curl -sL -o /dev/null -w '%{http_code} %{size_download}\n' -r 0-65535 "$url" 2>/dev/null || echo "000 0")
  code=${out%% *}; size=${out##* }
  if [ "$code" != "200" ] && [ "$code" != "206" ]; then
    echo "FAIL: $a -> HTTP $code. Nothing was changed." >&2; exit 1
  fi
  if [ "${size:-0}" -lt 1024 ]; then
    echo "FAIL: $a returned only ${size} bytes. Nothing was changed." >&2; exit 1
  fi
  printf '  OK  %-26s HTTP %s, %s bytes read\n' "$a" "$code" "$size"
done

# ---- rewrite the whole tag, leaving other products' links alone -------------
# Snapshot first. --dry-run restores from THIS, never from git: a `git checkout`
# here would also throw away unrelated edits sitting in the working tree. That
# happened once, to a full page redesign, about a minute after this was written.
SNAP=$(mktemp -d)
trap 'rm -rf "$SNAP"' EXIT
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  mkdir -p "$SNAP/$(dirname "$f")"; cp "$f" "$SNAP/$f"
done

python3 - "$TAG" "${FILES[@]}" <<'PY'
import re, sys, pathlib
tag, files = sys.argv[1], sys.argv[2:]
# Only our three installers in our release repo. TropicalIT and LinguaViva
# links live in apps/index.html too and must not be touched.
pat = re.compile(
    r'(https://github\.com/pretendhome/missioncanvas\.ai/releases/download/)'
    r'([^/"\']+)'
    r'(/MissionCanvas(?:\.dmg|-Setup\.exe|\.AppImage))')
total = 0
for f in files:
    p = pathlib.Path(f)
    if not p.exists():
        print(f"  skip {f} (not present)"); continue
    src = p.read_text(encoding="utf-8")
    new, n = pat.subn(lambda m: m.group(1) + tag + m.group(3), src)
    if n and new != src:
        p.write_text(new, encoding="utf-8")
    print(f"  {f}: {n} href(s)")
    total += n
if total == 0:
    sys.exit("FAIL: no pinned hrefs matched — the markup changed. Nothing written.")
PY

if git diff --quiet; then
  echo "Already pinned to $TAG. Nothing to do."; exit 0
fi

echo; echo "--- diff ---"; git --no-pager diff --stat; echo

if [ "$DRY" = "1" ]; then
  echo "Dry run: restoring the files as they were."
  for f in "${FILES[@]}"; do [ -f "$SNAP/$f" ] && cp "$SNAP/$f" "$f"; done
  exit 0
fi

git add "${FILES[@]}"
git commit -q -m "site: pin the download buttons to $TAG"
git push -q origin HEAD:main
echo "Pushed. Waiting for GitHub Pages to serve $TAG ..."

for i in $(seq 1 24); do
  body=$(curl -sf -H 'Cache-Control: no-cache' https://missioncanvas.ai/ || true)
  if grep -q "$TAG" <<< "$body"; then
    echo "OK: missioncanvas.ai is serving $TAG (after ~$((i*10))s)"
    echo
    echo "Now confirm the build still does what the page says:  bin/verify-claims.sh"
    exit 0
  fi
  seen=$(grep -o 'desktop-v[0-9A-Za-z.\-]*' <<< "$body" | sort -u | tr '\n' ' ' || true)
  echo "  [$i/24] not yet — site shows: ${seen:-<none>}"
  sleep 10
done
echo "FAIL: the site never served $TAG. The commit is pushed; check Pages." >&2
exit 1
