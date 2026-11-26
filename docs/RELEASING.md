# Releasing

Releases are cut from `main` by pushing a `vMAJOR.MINOR.PATCH` tag or by running the workflow manually. The
[Release workflow](../.github/workflows/release.yml) then builds, packages, signs the update and publishes a
GitHub Release. Installed copies pick it up through [Sparkle](https://sparkle-project.org).

## Cutting a release

1. Open a pull request that moves the **Unreleased** entries in `CHANGELOG.md` under a new
   `## [X.Y.Z] - YYYY-MM-DD` heading (and adds the matching compare link at the bottom). Merge it.
2. Tag the merge commit and push the tag:
   ```sh
   git switch main && git pull
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```
   Alternatively, run the **Release** workflow from the Actions tab (*Run workflow* on `main`, enter `X.Y.Z`);
   it creates the `vX.Y.Z` tag on the commit it built.
3. The workflow:
   - checks that the tag is on `main` and that `CHANGELOG.md` has a section for the version;
   - runs the tests and builds the universal app with `CFBundleShortVersionString = X.Y.Z` and
     `CFBundleVersion` = the number of commits on `main` (always increasing, which Sparkle relies on);
   - creates `Dotwell.dmg` (for people, built with `dmgbuild`; unversioned so
     `releases/latest/download/Dotwell.dmg` always points at the newest one) and `Dotwell-X.Y.Z.zip` (for Sparkle);
   - signs the zip with the EdDSA key, verifies the signature against `SUPublicEDKey` in `Resources/Info.plist`,
     and writes `appcast.xml` with the changelog section as release notes;
   - publishes the release with all three files attached.

The appcast is served from `https://github.com/Saissaken/dotwell/releases/latest/download/appcast.xml`,
so the newest release always carries the current feed and there is nothing else to host.

## Nightly builds

Every push to `main` that touches the app runs the [Nightly workflow](../.github/workflows/nightly.yml). It
tests and builds `main` and publishes it to a single rolling prerelease tagged `nightly`:

- the version is the last release plus build metadata, e.g. `0.7.0+nightly.312`, and `CFBundleVersion` is the
  commit count, the same scheme as releases. A release of commit X has the same build number as the nightly of
  X, so nightly users are never offered a "downgrade" and always move forward;
- `Dotwell-nightly-<build>.zip` is signed with the same EdDSA key (the previous zip is kept for downloads in
  flight, older ones are deleted), and there is no disk image: nightlies are reached by updating an install;
- `appcast.xml` on that prerelease (`releases/download/nightly/appcast.xml`) lists the nightly with
  `<sparkle:channel>nightly</sparkle:channel>`, followed by the items of the latest release's appcast;
- the release notes list the commits since the last release.

Publishing a release also starts the Nightly workflow, so the nightly feed picks up the new release right away
(release commits only change `CHANGELOG.md`, which would not trigger it).

Installed copies only read the nightly feed after the person turns on **Settings → Updates → Get nightly
builds**: the updater delegate then returns the nightly feed URL and allows the `nightly` channel. Turning it off
goes back to `SUFeedURL`; Sparkle never downgrades, so the nightly stays until a newer release is out.

Official releases are unaffected. GitHub's *latest release* never resolves to a prerelease, so
`releases/latest/download/…` (the stable appcast, the DMG link on the site and in the README) keeps pointing at
the last official release.

## How updates reach users

`SUEnableAutomaticChecks` and `SUAutomaticallyUpdate` are on: Sparkle checks once a day, downloads new versions
in the background and installs them when the app quits (for example at logout or restart). People can also
right-click the menu bar icon and choose **Check for Updates…**. Sparkle only installs an archive whose EdDSA
signature matches the public key of the copy that is already installed.

## Signing keys

- `SUPublicEDKey` in `Resources/Info.plist` is the public half and is safe to publish.
- The private half lives only in the `SPARKLE_PRIVATE_KEY` repository secret (base64 of the 32-byte Ed25519 seed,
  the format of Sparkle's `generate_keys -x`). Keep an offline backup: if it is lost, existing installs can no
  longer be updated automatically.
- To rotate the key, generate a new pair with Sparkle's `generate_keys`, ship one release signed with the old key
  that contains the new public key, then switch the secret.

## Code signing and notarization

Builds are ad-hoc signed today, so Gatekeeper asks people to allow the app once (see the README). Sparkle works
with ad-hoc builds because updates are trusted through EdDSA, not through the code signature.

`scripts/bundle.sh` already supports a real identity: with `SIGN_IDENTITY="Developer ID Application: …"` it signs
Sparkle's helpers and the app with the hardened runtime and secure timestamps. Adding notarization later means
importing the certificate into a temporary keychain in the workflow, passing `SIGN_IDENTITY`, and running
`xcrun notarytool submit --wait` plus `xcrun stapler staple` on the `.app` and `.dmg` before packaging the zip.
Sparkle allows switching from ad-hoc to Developer ID signing because the EdDSA key stays the same.
