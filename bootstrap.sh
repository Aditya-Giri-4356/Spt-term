#!/bin/bash
set -euo pipefail
git rev-parse --is-inside-work-tree >/dev/null
mkdir -p SptTerm/Services/Live SptTermTweak

git mv SptTerm.xcodeproj/project.xcproj SptTerm.xcodeproj/project.pbxproj 2>/dev/null || true

cat > SptTerm/Services/Live/STSpotifyConfig.swift <<'SWIFT'
import Foundation

/// Compile-time Spotify configuration. Register an app at
/// developer.spotify.com with `redirectURI` as a redirect, then paste the
/// client ID in.
enum STSpotifyConfig {
    static let clientID = "YOUR_CLIENT_ID"
    static let redirectURI = "sptterm://auth"

    static let apiBase = URL(string: "https://api.spotify.com/v1")!
    static let accountsBase = URL(string: "https://accounts.spotify.com")!

    static let scopes = [
        "user-library-read",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-read-private",
    ]

    static var scopeString: String { scopes.joined(separator: " ") }
    static var isConfigured: Bool { clientID != "YOUR_CLIENT_ID" }
}
SWIFT

cat > SptTerm/Services/Live/STPKCE.swift <<'SWIFT'
import Foundation
import CryptoKit
import Security

/// RFC 7636 verifier/challenge pair for the authorization-code flow.
struct STPKCE {
    let verifier: String
    let challenge: String

    init() {
        verifier = Self.randomVerifier()
        challenge = Self.challenge(for: verifier)
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
SWIFT

cat > SptTerm/Services/Live/STKeychain.swift <<'SWIFT'
import Foundation
import Security

/// Generic-password wrapper. One service string for the whole app.
enum STKeychain {
    private static let service = "ai.venice.sptterm"

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        SecItemDelete(baseQuery(key) as CFDictionary)
        var query = baseQuery(key)
        query[kSecValueData as String] = data
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        SecItemDelete(baseQuery(key) as CFDictionary) == errSecSuccess
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
    }
}
SWIFT

cat > SptTermTweak/SptTermTweak.plist <<'PLIST'
{ Filter = { Bundles = ( "com.spotify.client" ); }; }
PLIST

cat > SptTermTweak/Tweak.swift <<'SWIFT'
import Orion
import UIKit

struct SptTermTweak: Tweak {
    init() {
        DispatchQueue.main.async {
            STWindowHost.shared.install()
        }
    }
}
SWIFT

cat > control <<'CTRL'
Package: ai.venice.spttermtweak
Name: SptTermTweak
Version: 1.0.0
Architecture: iphoneos-arm
Description: Terminal UI layer for Spotify
Maintainer: you
Author: you
Section: Tweaks
Depends: mobilesubstrate, firmware (>= 16.0)
CTRL

cat > Makefile <<'MAKE'
TARGET := iphone:clang:latest:16.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Spotify

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SptTermTweak
SptTermTweak_FILES = $(shell find SptTermTweak -name '*.swift') $(shell find SptTerm -name '*.swift' ! -name 'SptTermApp.swift')
SptTermTweak_SWIFTFLAGS = -warnings-as-errors

include $(THEOS_MAKE_PATH)/tweak.mk
MAKE

cat > build_and_inject.sh <<'SH'
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
SH
chmod +x build_and_inject.sh

echo "OK — run 'git status' to review"