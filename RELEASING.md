# Releasing T3d Boy

Versions follow [semantic versioning](https://semver.org): `MAJOR.MINOR.PATCH`.
The [`VERSION`](VERSION) file is the single source of truth — `build.sh` stamps it
into the app bundle and names the DMG `T3dBoy-<version>.dmg`.

## Cut a release

1. **Bump the version**

   ```sh
   echo "2.0.0" > VERSION
   ```

2. **Update the changelog** — add a `## [2.0.0]` section to `CHANGELOG.md`.

3. **Build the DMG**

   ```sh
   ./build.sh          # produces build/T3dBoy-2.0.0.dmg
   ```

4. **Commit, tag, and push**

   ```sh
   git add VERSION CHANGELOG.md
   git commit -m "Release 2.0.0"
   git tag v2.0.0
   git push github main --tags
   ```

5. **Create the GitHub Release** and attach the DMG.

   ```sh
   gh release create v2.0.0 "build/T3dBoy-2.0.0.dmg" --repo t3dboy/t3d-boy \
     --title "T3d Boy 2.0.0" \
     --notes "$(sed -n '/## \[2.0.0\]/,/## \[/p' CHANGELOG.md | sed '$d')"
   ```

   Or in the web UI: **Releases → Draft a new release**, pick tag `v2.0.0`,
   paste the changelog notes, and upload the DMG as a release asset.

## Notes

- The DMG is **ad-hoc signed**, not notarized. Users open it via right-click →
  Open the first time (documented in the README). If you later want frictionless
  distribution to strangers, that requires an Apple Developer ID ($99/yr) and a
  notarization step added to `build.sh`.
- Never commit ROMs — `.gitignore` blocks `*.gb`, `*.gbc`, `*.zip`, and `ROMs/`.
