# Signing and notarization

`scripts/release.sh` signs with a local `Dockerd Local Signing` certificate if you have one (see below), otherwise ad-hoc (`codesign --sign -`). Either is enough to run on the machine that built it. To distribute Dockerd you need a Developer ID certificate and notarization.

## Why the Accessibility grant resets on rebuilds

macOS records the Accessibility (TCC) grant against the app's code signature. An ad-hoc signature changes with every build, so after a rebuild macOS treats Dockerd as a new app. The old entry in **System Settings → Privacy & Security → Accessibility** stays but no longer applies.

After an ad-hoc rebuild:

1. Quit Dockerd.
2. In the Accessibility list, remove the existing Dockerd entry with the − button.
3. Launch the new build and grant access again.

To keep the grant across rebuilds, create a local signing certificate once with `scripts/make-signing-cert.sh`. The script creates a self-signed code-signing identity named `Dockerd Local Signing` in your login keychain; only `codesign` may use its key.

Or do it by hand:

1. Open Keychain Access → Certificate Assistant → **Create a Certificate…**
2. Name: `Dockerd Local Signing`. Identity Type: **Self Signed Root**. Certificate Type: **Code Signing**.
3. Click Create, then rebuild with `scripts/release.sh`.

When `SIGN_IDENTITY` is not set, `release.sh` looks for a certificate with that name and signs with it, falling back to ad-hoc only when there isn't one. The build output says which one it used. Grant Accessibility once to a build signed this way, and later builds keep the grant.

Variables:
- `LOCAL_SIGN_NAME` uses a different certificate name.
- `SIGN_IDENTITY=-` forces ad-hoc signing.

A self-signed certificate is only for your own machine; it can't be notarized.

## Developer ID build

Requirements: an Apple Developer account and a "Developer ID Application" certificate in your login keychain.

```sh
security find-identity -v -p codesigning
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/release.sh
```

For a `Developer ID Application` identity, the script signs with the hardened runtime (`--options runtime`) and a secure timestamp (`--timestamp`). Both are required for notarization. Dockerd needs no entitlements: Accessibility is a TCC permission, not an entitlement, and the app uses no network, sandbox exceptions or JIT.

## Notarize

Store credentials once, using an app-specific password from appleid.apple.com:

```sh
xcrun notarytool store-credentials dockerd-notary \
  --apple-id you@example.com --team-id TEAMID --password app-specific-password
```

Submit, wait, then staple:

```sh
ditto -c -k --keepParent dist/Dockerd.app dist/Dockerd.zip
xcrun notarytool submit dist/Dockerd.zip --keychain-profile dockerd-notary --wait
xcrun stapler staple dist/Dockerd.app
spctl --assess --type execute --verbose dist/Dockerd.app
```

If the submission is rejected, read the log:

```sh
xcrun notarytool log <submission-id> --keychain-profile dockerd-notary
```

After stapling, zip the app again (or wrap it in a DMG) for distribution.

`notarytool` and `stapler` ship with Xcode. With Command Line Tools only, check that `xcrun notarytool --help` works before you rely on it.
