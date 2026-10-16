# Publishing Meridian

## Repository and website

Repository: https://github.com/etongle/Meridian

The buildless site lives in `docs/`. GitHub Pages can publish **main / (root)**; the root index forwards visitors to the bilingual site in `docs/`. Alternatively, select **GitHub Actions** in Settings → Pages, and the Website workflow publishes `docs/` directly at https://etongle.github.io/Meridian/. The workflow detects branch publishing and leaves deployment to GitHub in that mode.

## Signing key: one-time owner setup

Sparkle is bundled and wired into the app. Release builds derive their public key from a stable private seed stored in the repository secret **SPARKLE_PRIVATE_KEY**. The trusted public key is committed in Config/release.json. Never rotate it casually; users trust this key for future updates.

1. Run `zsh scripts/fetch-sparkle.sh`.
2. Generate an application-specific key using `.build/Sparkle/bin/generate_keys --account etongle.Meridian`. Sparkle stores the private key in your macOS login Keychain.
3. Export a temporary private key file using `.build/Sparkle/bin/generate_keys --account etongle.Meridian -x /private/tmp/meridian-signing-key`.
4. From an owner-authorized GitHub CLI account, set the secret without displaying its value:

```sh
gh secret set SPARKLE_PRIVATE_KEY --repo etongle/Meridian < /private/tmp/meridian-signing-key
rm /private/tmp/meridian-signing-key
```

Keep the Keychain key backed up. Reusing the same seed for future releases preserves the trusted update chain. Never commit a private key or paste it into an issue, README or workflow input.

The release workflow requires the current Sparkle 32-byte seed format. It derives the public Ed25519 key with CryptoKit and never prints private key material.

## Release flow

1. Update `version` and increment the numeric `build` in `Config/release.json`. Keep `bundleIdentifier` unchanged for updates and preference compatibility.
2. Update `CHANGELOG.md`; run `zsh test.sh` and `zsh build.sh`.
3. Commit, tag the same version (for example `v1.1.0`), and push the tag.
4. The Release workflow builds both architectures, packages the app, signs its update archive using Sparkle, creates `appcast.xml`, and uploads the archive and feed to the same GitHub Release.

The appcast URL is `https://github.com/etongle/Meridian/releases/latest/download/appcast.xml`. Archive URLs point to the exact version’s release. The website changes its download links when a real archive exists.

Automatic checks default to every 6 hours. Automatic downloads are optional and disabled by default. Sparkle verifies the signed archive before extraction. Every archive is verified against the appcast, including a rejection check on modified archive bytes. A real version-to-version installation can be checked after a later build is released.

## Developer ID and notarization

Local builds and the initial workflow use ad-hoc code signing. Sparkle Ed25519 signing authenticates updates; it does not replace Apple Developer ID signing and notarization for a smooth first installation from the internet.

To create a Developer ID build, install the certificate in the build keychain and set `MERIDIAN_SIGN_IDENTITY` to that identity before invoking `build.sh`. Submit the finished app archive through `xcrun notarytool`, staple the app, and create the final archive **before** running `generate_appcast`. Re-sign the archive/feed whenever the archived app changes.

## Official references

- https://sparkle-project.org/documentation/
- https://sparkle-project.org/documentation/programmatic-setup/
- https://sparkle-project.org/documentation/customization/
- https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages

## Local Keychain signing and first publication

The same release can be signed locally without uploading the private key to GitHub:

```sh
MERIDIAN_ARCHS="arm64 x86_64" zsh build.sh
zsh scripts/package-release.sh
```

The packaging script uses the dedicated login Keychain account `etongle.Meridian`. Set `MERIDIAN_SPARKLE_ACCOUNT` to override the account. The public key must match Config/release.json.

For first publication, create a `release-artifacts/vVERSION` branch from the committed source. Copy both the DMG installer and ZIP update archive, and all other files listed by `dist/updates/SHA256SUMS`, plus `SHA256SUMS`, into `ReleaseArtifacts/`. Add `ReleaseArtifacts/release.json` with `tag` and the full `sourceCommit`. Push that branch. The Publish signed artifacts workflow verifies the source, bundle metadata, universal architectures, code signature, bundled license and Ed25519 archive signature before creating a release whose tag points to that source commit. Only signed public artifacts are uploaded; the private signing key remains in Keychain.

## GitHub Packages

Both publishing workflows mirror the release files to `ghcr.io/etongle/meridian` using the Packages workflow. Tags include the version with and without `v`, plus `latest`. The OCI artifact contains the native macOS DMG and ZIP, update feed, checksums and license; it is not a runnable container. Source and license metadata link it to this repository.

GitHub creates a new personal-account package as private. The owner must set its package visibility to Public once in Package settings for anonymous downloads. This is separate from the repository's visibility. After that, future versions retain the setting.

## DMG installers

`zsh scripts/build-dmg.sh` wraps the existing signed `dist/Meridian.app` in a compressed read-only DMG with an Applications shortcut and license notices. `package-release.sh` builds it after the ZIP-only Sparkle feed so automatic updates keep using ZIP. The website prefers the DMG asset for first installation.
