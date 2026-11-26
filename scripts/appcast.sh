#!/usr/bin/env bash
# Signs the update archive with the Sparkle EdDSA key and writes build/appcast.xml.
# Usage: SPARKLE_PRIVATE_KEY=... scripts/appcast.sh <version> <build> <zip> <download-url> <notes.md>
# SPARKLE_PUBLIC_KEY overrides the key from Info.plist (only for CI dry runs with a throwaway key).
# CHANNEL puts the item on a Sparkle channel (e.g. "nightly"); only apps that allow it see the item.
# INCLUDE_FEED is another appcast whose items are copied after the new one (the nightly feed carries
# the latest stable release too, so nightly users never miss one).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version}" BUILD="${2:?build}" ZIP="${3:?zip}" URL="${4:?download url}" NOTES="${5:?notes file}"
: "${SPARKLE_PRIVATE_KEY:?set SPARKLE_PRIVATE_KEY to the base64 EdDSA private key (see docs/RELEASING.md)}"

SIGN_UPDATE="$(find .build/artifacts -type f -path '*/bin/sign_update' -print -quit)"
[[ -x "$SIGN_UPDATE" ]] || { echo "sign_update not found in .build/artifacts" >&2; exit 1; }
SIGNATURE="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$ZIP")"
LENGTH="$(stat -f %z "$ZIP")"

# Refuse to publish an update that installed copies would reject: the signature must match the
# public key shipped in Info.plist, not just the private key we happen to have.
PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$(plutil -extract SUPublicEDKey raw Resources/Info.plist)}"
swift scripts/verify-signature.swift "$PUBLIC_KEY" "$SIGNATURE" "$ZIP"

MIN_OS="$(plutil -extract LSMinimumSystemVersion raw Resources/Info.plist)"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
# CDATA cannot contain "]]>"; split it if the notes ever do.
BODY="$(sed 's/]]>/]]]]><![CDATA[>/g' "$NOTES")"
CHANNEL_TAG=""
[[ -n "${CHANNEL:-}" ]] && CHANNEL_TAG="<sparkle:channel>$CHANNEL</sparkle:channel>"
EXTRA_ITEMS=""
if [[ -n "${INCLUDE_FEED:-}" ]]; then
    # An empty result (no items) is fine; a feed that doesn't parse is not.
    xmllint --noout "$INCLUDE_FEED"
    EXTRA_ITEMS="$(xmllint --xpath '/rss/channel/item' "$INCLUDE_FEED" 2> /dev/null || true)"
fi

cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Dotwell</title>
    <link>https://github.com/Saissaken/dotwell</link>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      $CHANNEL_TAG
      <description sparkle:format="markdown"><![CDATA[
$BODY
]]></description>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
$EXTRA_ITEMS
  </channel>
</rss>
XML

xmllint --noout build/appcast.xml
echo "Wrote build/appcast.xml for $VERSION ($BUILD)"
