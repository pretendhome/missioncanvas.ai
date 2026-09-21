#!/usr/bin/env bash
# Does the app we are shipping still do what the front page says it does?
#
# Why this exists
# ---------------
# The page makes specific, checkable promises about the download: that the empty
# screen offers a sample-notes button, that the app is called Palette, that you
# can click a claim back to its source, and that it reads nothing until you
# grant a folder. Every one of those is a sentence a stranger will judge us by.
#
# Pinning a new tag can invalidate any of them silently. Nothing in the release
# pipeline knows the marketing page exists, so a rename or a removed button
# would leave the site asserting something the binary no longer does, and no
# test anywhere would go red. This closes that gap: it reads the SHIPPED
# payload, not the source tree, because the tree is not what people download.
#
# It also re-derives the download's sha256 and compares it to the digest the
# releases API publishes, so a corrupted or substituted asset fails here rather
# than on a stranger's machine.
#
# Usage
#   bin/verify-claims.sh            # check whatever tag the site currently pins
#   bin/verify-claims.sh <tag>      # check a specific tag before pinning it
#
# Exit 0 = every claim the page makes is present in the build it links to.
# Exit 1 = it is not. Do not pin, or change the page.
set -euo pipefail

REPO="pretendhome/missioncanvas.ai"
cd "$(dirname "$0")/.."

TAG="${1:-}"
if [ -z "$TAG" ]; then
  TAG=$(grep -o 'releases/download/[^/]*/MissionCanvas\.dmg' index.html \
        | head -1 | sed 's#releases/download/##; s#/MissionCanvas\.dmg##')
  [ -n "$TAG" ] || { echo "FAIL: could not read the pinned tag from index.html" >&2; exit 1; }
  echo "Checking the tag the site currently pins: $TAG"
else
  echo "Checking tag: $TAG"
fi

command -v gh >/dev/null || { echo "FAIL: gh is not installed" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# B1-110: from desktop-v0.3.8 the Linux installer is a .deb; releases up to 0.3.7 carry the AppImage.
# Ask the release which one it has — never guess from the tag's number.
NAMES=$(gh api "repos/$REPO/releases?per_page=100" --jq ".[] | select(.tag_name==\"$TAG\") | .assets[].name" 2>/dev/null)
if grep -q -x "MissionCanvas.deb" <<< "$NAMES"; then ASSET=MissionCanvas.deb
elif grep -q -x "MissionCanvas.AppImage" <<< "$NAMES"; then ASSET=MissionCanvas.AppImage
else echo "FAIL: $TAG carries neither MissionCanvas.deb nor MissionCanvas.AppImage — CANNOT TELL, not a pass." >&2; exit 1; fi
URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"

echo "Downloading $ASSET as an anonymous user would (80-120 MB) ..."
curl -sL -o "$WORK/$ASSET" "$URL" || { echo "FAIL: download failed" >&2; exit 1; }
[ -s "$WORK/$ASSET" ] || { echo "FAIL: downloaded file is empty" >&2; exit 1; }

WANT=$(gh api "repos/$REPO/releases?per_page=100" \
       --jq ".[] | select(.tag_name==\"$TAG\") | .assets[] | select(.name==\"$ASSET\") | .digest" \
       2>/dev/null | sed 's/^sha256://')
GOT=$(sha256sum "$WORK/$ASSET" | cut -d' ' -f1)
if [ -z "$WANT" ]; then
  echo "FAIL: the releases API published no digest for $ASSET on $TAG — CANNOT TELL, not a pass." >&2
  exit 1
fi
if [ "$WANT" != "$GOT" ]; then
  echo "FAIL: digest mismatch." >&2
  echo "  published $WANT" >&2
  echo "  received  $GOT" >&2
  exit 1
fi
echo "  digest matches what the release publishes: ${GOT:0:16}..."

echo "Extracting the shipped payload ..."
if [ "$ASSET" = "MissionCanvas.deb" ]; then
  command -v dpkg-deb >/dev/null || { echo "FAIL: dpkg-deb is not installed — cannot open the .deb" >&2; exit 1; }
  dpkg-deb -x "$WORK/$ASSET" "$WORK/deb-root" || { echo "FAIL: the .deb does not unpack" >&2; exit 1; }
  PYZ=$(find "$WORK/deb-root/opt" -path '*/resources/north-star/mcr.pyz' -print -quit)
  # the page promises an install with nothing typed: the packaged post-install must carry what makes that true
  dpkg-deb -e "$WORK/$ASSET" "$WORK/deb-control"
  grep -q "userns," "$WORK/deb-control/postinst" && grep -q "chmod 4755" "$WORK/deb-control/postinst" \
    || { echo "FAIL: the .deb's post-install does not set up the sandbox (B1-110) — it would abort on Ubuntu 24.04." >&2; exit 1; }
  echo "  the .deb's post-install sets up the sandbox (AppArmor profile + setuid helper)"
else
  chmod +x "$WORK/$ASSET"
  ( cd "$WORK" && ./"$ASSET" --appimage-extract >/dev/null 2>&1 ) || true
  PYZ="$WORK/squashfs-root/resources/north-star/mcr.pyz"
fi
[ -f "$PYZ" ] || { echo "FAIL: mcr.pyz not found in the package — the layout changed." >&2; exit 1; }

# Each entry is: <what the page promises> :: <string that must exist in the payload>
# Keep this list in step with index.html. If you remove a promise from the page,
# remove it here; if you add one, add it here, or this gate is decorative.
python3 - "$PYZ" <<'PY'
import sys, zipfile
CLAIMS = [
    ('the empty screen offers "Try it with sample notes"', "Try it with sample notes"),
    ('the app is called Palette',                          "Palette"),
    ('you can click a claim back to its source',           "data-claim"),
    ('it reads nothing until you grant a folder',          "Grant"),
]
z = zipfile.ZipFile(sys.argv[1])
blob = b"".join(z.read(n) for n in z.namelist() if n.endswith(".py"))
text = blob.decode("utf-8", "replace")
bad = []
for promise, needle in CLAIMS:
    n = text.count(needle)
    print(f"  {'OK    ' if n else 'BROKEN'}  {promise}  (x{n})")
    if not n:
        bad.append(promise)
if bad:
    print("\nFAIL: the page promises this and the build does not deliver it:")
    for b in bad:
        print(f"  - {b}")
    sys.exit(1)
PY

echo
echo "OK: every claim on missioncanvas.ai is present in the build it links to ($TAG)."
