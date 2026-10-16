# Publishing Meridian

## Repository and website

Repository: https://github.com/etongle/Meridian

The buildless site lives in `docs/`. In **Settings → Pages → Build and deployment**, select **GitHub Actions** once. The Website workflow publishes to https://etongle.github.io/Meridian/ on changes to `docs/`.

## Signing key: one-time owner setup

Sparkle is bundled and wired into the app. Release builds derive their public key from a stable private seed stored in the repository secret **SPARKLE_PRIVATE_KEY**. Development builds with no public key leave the updater inactive.

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

Automatic checks default to every 6 hours. Automatic downloads are optional and disabled by default. Sparkle verifies the signed archive before extraction. The first signed public release is required for end-to-end update testing; no live update is claimed before that release exists.

## Developer ID and notarization

Local builds and the initial workflow use ad-hoc code signing. Sparkle Ed25519 signing authenticates updates; it does not replace Apple Developer ID signing and notarization for a smooth first installation from the internet.

To create a Developer ID build, install the certificate in the build keychain and set `MERIDIAN_SIGN_IDENTITY` to that identity before invoking `build.sh`. Submit the finished app archive through `xcrun notarytool`, staple the app, and create the final archive **before** running `generate_appcast`. Re-sign the archive/feed whenever the archived app changes.

## Official references

- https://sparkle-project.org/documentation/
- https://sparkle-project.org/documentation/programmatic-setup/
- https://sparkle-project.org/documentation/customization/
- https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages
