#!/bin/bash
# Usage: ./build_and_inject.sh EeveeSpotify-*.ipa
set -euo pipefail

IPA="${1:?usage: $0 <injected.ipa>}"
OUT="SptTerm-Eevee.ipa"

rm -rf work
unzip -q -o "$IPA" -d work

make clean package FINALPACKAGE=1
DYLIB=$(find .theos/obj -name 'SptTermTweak.dylib' -print -quit)
[ -n "$DYLIB" ] || { echo "dylib not found"; exit 1; }

cp "$DYLIB" work/Payload/Spotify.app/

# Already-injected IPA: append a second load command, keep existing ones.
insert_dylib --inplace --strip-codesig --all-yes \
  @executable_path/SptTermTweak.dylib work/Payload/Spotify.app/Spotify

# Skip the ldid lines if signing with Sideloadly or Azule; keep for TrollStore.
codesign -d --entitlements :- work/Payload/Spotify.app > ents.plist 2>/dev/null || true
if [ -s ents.plist ]; then
  ldid -Sents.plist work/Payload/Spotify.app/Spotify
  ldid -Sents.plist work/Payload/Spotify.app/SptTermTweak.dylib
else
  ldid -S work/Payload/Spotify.app/Spotify
  ldid -S work/Payload/Spotify.app/SptTermTweak.dylib
fi

otool -L work/Payload/Spotify.app/Spotify | grep -q SptTermTweak \
  || { echo "load command missing"; exit 1; }

rm -f "$OUT"
(cd work && zip -qr "../$OUT" Payload)
echo "wrote $OUT"
