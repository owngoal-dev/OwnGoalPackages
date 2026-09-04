# OwnGoal Packages

Flat APT repository for OwnGoal Studio iOS packages.

## Repository URL

Use the GitHub Pages repository URL:

```text
https://apt.owngoal.dev/
```

The equivalent APT source entry for the unsigned repository is:

```text
deb [trusted=yes] https://apt.owngoal.dev/ ./
```

## Package sources

The published pool merges two sources:

- `manifest.json` declares GitHub repositories whose releases are downloaded at
  build time into the ignored `downloads/` directory.
- `debs/` holds `.deb` files that are committed directly.

Both sources are indexed together, so every package is served from `debs/` in the
published repository. Two packages may not share a file name.

### Track a GitHub release

Add an entry to `manifest.json`:

```json
{
  "packages": [
    {
      "repository": "https://github.com/owngoal-dev/CocoaInspector",
      "architectures": ["iphoneos-arm64e", "iphoneos-arm64"]
    }
  ]
}
```

`repository` accepts a browser URL, a clone URL, or a bare `owner/name` slug.
`architectures` is a required, non-empty array. Each value selects the release
asset whose file name ends in `<architecture>.deb`. A repository is declared
once, and every listed jailbreak layout reaches the pool under its own file
name.

`./scripts/fetch-packages.sh` resolves the newest release that is not a draft,
not a prerelease, and not tagged as a preview build (`alpha`, `beta`, `rc`,
`pre`, `preview`, `dev`, `nightly`, `snapshot`). Every API call and download is
retried with exponential backoff. A downloaded file is rejected unless it carries
the Debian archive magic and, when the release also publishes a `SHA256SUMS`
asset that lists it, matches the recorded digest. A rejected file is discarded
and downloaded again. The build fails when a declared repository has no matching
stable asset, so a package is never silently dropped from the index.

Set `PACKAGE_FETCH_TOKEN` to reach releases in a private source repository. The
workflow falls back to the default `GITHUB_TOKEN`, which only raises the public
API rate limit.

### Commit a package directly

1. Copy the `.deb` file into `debs/`.
2. Commit and push it to `main`.

### Build

The `Build and Deploy APT Repository` workflow downloads the manifest packages,
reads the control metadata of the whole pool, builds the complete repository in
`_site/`, and deploys that artifact to GitHub Pages. It runs on every push that
touches the repository inputs, once a day at 04:00 UTC to pick up new upstream
releases, and on demand.

`Packages`, `Packages.xz`, and `Release` are generated during the build and are
intentionally excluded from Git. The workflow verifies their public SHA-256
hashes after each deployment.

For local generation, install `apt-utils`, `xz-utils`, `curl`, and `jq` on Debian
or Ubuntu, then run `./scripts/update-repository.sh`. The complete site is written
to the ignored `_site/` directory. Set `SKIP_PACKAGE_FETCH=1` to build from the
already downloaded packages without contacting GitHub.

Signed releases can be created with
`./scripts/sign-repository.sh <GPG_KEY_ID>` after a local build.

Rebuilding `_site/` removes existing signatures because every metadata change
requires a fresh signature.

## Sileo metadata

Sileo reads repository information from files at the repository root:

- `CydiaIcon.png` is the repository icon.
- `_site/Release` provides the repository name, description, and supported
  architectures.
- `_site/Packages` provides each package name, category, icon, and depiction.

Every package control file must include `Section`. Sileo uses that value to build
software categories. See [`debs/README.md`](debs/README.md) for the supported
package fields.
