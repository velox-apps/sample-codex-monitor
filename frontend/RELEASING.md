# Releasing CodexMonitor (macOS)

This is a copy/paste friendly script-style guide. It assumes you have a
Developer ID Application certificate installed and a `notarytool` keychain
profile named `codexmonitor-notary`.

```bash
set -euo pipefail

# --- Set versions ---
# Update these two values each release.
RELEASE_VERSION="0.4.3"
PREV_VERSION="0.4.2"

# --- Update version fields (manual check afterwards) ---
perl -pi -e "s/\"version\": \"[^\"]+\"/\"version\": \"${RELEASE_VERSION}\"/" package.json
perl -pi -e "s/\"version\": \"[^\"]+\"/\"version\": \"${RELEASE_VERSION}\"/" src-tauri/tauri.conf.json
npm install

# --- Commit + push version bump ---
git add package.json package-lock.json src-tauri/tauri.conf.json
git commit -m "chore: bump version to ${RELEASE_VERSION}"
git push origin main

# --- Build (signed for updater) ---
export TAURI_SIGNING_PRIVATE_KEY=~/.tauri/codexmonitor.key
export TAURI_SIGNING_PRIVATE_KEY_PASSWORD="release"
npm run tauri -- build --bundles app

# --- Bundle OpenSSL + re-sign app ---
CODESIGN_IDENTITY="Developer ID Application: Thomas Ricouard (Z6P74P6T99)" \
  scripts/macos-fix-openssl.sh

# --- Zip, notarize, staple ---
ditto -c -k --keepParent \
  src-tauri/target/release/bundle/macos/CodexMonitor.app \
  CodexMonitor.zip

xcrun notarytool submit CodexMonitor.zip \
  --keychain-profile codexmonitor-notary \
  --wait

xcrun stapler staple \
  src-tauri/target/release/bundle/macos/CodexMonitor.app

# --- Package ZIP + DMG from stapled app ---
mkdir -p release-artifacts release-artifacts/dmg-root
rm -rf release-artifacts/dmg-root/CodexMonitor.app
ditto src-tauri/target/release/bundle/macos/CodexMonitor.app \
  release-artifacts/dmg-root/CodexMonitor.app

ditto -c -k --keepParent \
  src-tauri/target/release/bundle/macos/CodexMonitor.app \
  release-artifacts/CodexMonitor.zip

hdiutil create -volname "CodexMonitor" \
  -srcfolder release-artifacts/dmg-root \
  -ov -format UDZO \
  release-artifacts/CodexMonitor_${RELEASE_VERSION}_aarch64.dmg

# --- Rebuild updater tarball without AppleDouble files ---
COPYFILE_DISABLE=1 tar -czf \
  src-tauri/target/release/bundle/macos/CodexMonitor.app.tar.gz \
  -C src-tauri/target/release/bundle/macos CodexMonitor.app

npm run tauri signer sign -- \
  -f ~/.tauri/codexmonitor.key \
  -p "release" \
  src-tauri/target/release/bundle/macos/CodexMonitor.app.tar.gz

# --- Changelog (for release notes) ---
git log --name-only --pretty=format:"%h %s" v${PREV_VERSION}..v${RELEASE_VERSION}

# --- Tag ---
git tag v${RELEASE_VERSION}
git push origin v${RELEASE_VERSION}

# --- Build latest.json for updater ---
PUB_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SIGNATURE=$(cat src-tauri/target/release/bundle/macos/CodexMonitor.app.tar.gz.sig)

cat <<EOF > release-artifacts/latest.json
{
  "version": "${RELEASE_VERSION}",
  "notes": "- Short update notes",
  "pub_date": "${PUB_DATE}",
  "platforms": {
    "darwin-aarch64": {
      "url": "https://github.com/Dimillian/CodexMonitor/releases/download/v${RELEASE_VERSION}/CodexMonitor.app.tar.gz",
      "signature": "${SIGNATURE}"
    }
  }
}
EOF

# --- Create GitHub release with artifacts ---
gh release create v${RELEASE_VERSION} \
  --title "v${RELEASE_VERSION}" \
  --notes "- Short update notes" \
  release-artifacts/CodexMonitor.zip \
  release-artifacts/CodexMonitor_${RELEASE_VERSION}_aarch64.dmg \
  src-tauri/target/release/bundle/macos/CodexMonitor.app.tar.gz \
  src-tauri/target/release/bundle/macos/CodexMonitor.app.tar.gz.sig \
  release-artifacts/latest.json

# --- If you need to update assets later ---
gh release upload v${RELEASE_VERSION} \
  src-tauri/target/release/bundle/macos/CodexMonitor.app.tar.gz \
  src-tauri/target/release/bundle/macos/CodexMonitor.app.tar.gz.sig \
  release-artifacts/latest.json \
  --clobber
```

Notes:
- Never commit `~/.tauri/codexmonitor.key`.
- If notarization fails, run `xcrun notarytool log <ID> --keychain-profile codexmonitor-notary`.
