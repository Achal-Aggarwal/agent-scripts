# Releasing Agent Scripts

Agent Scripts ships a source catalog on GitHub, not an npm package. The private
root package manifest is development tooling. The current released version is
`0.12.0`; release tags deliberately have **no `v` prefix**.

`.github/workflows/release.yml` calls the shared source archetype at `@v1`.
It validates `VERSION`, exactly one dated changelog section, protected-main
ancestry, and successful push CI on the exact source commit. It validates the
skill catalog, downloads commit-bound source archives, and independently verifies
the notes, inventory and checksums on two clean runners before publication.

Before a future release, update `VERSION`, finalize the matching dated section in
`CHANGELOG.md`, and land those changes on protected main. Wait for its push CI.
First rehearse without creating a tag or publishing:

```sh
gh workflow run release.yml --ref main -f version=0.12.0 -F dry_run=true
```

Use the version being prepared for a future release. A main-branch dry run always
checks that exact main commit, even when the version already has a release tag.
It does not change that tag or release.

Publication requires an existing **SSH-signed annotated** `X.Y.Z` tag on the tested
commit. Use the fleet release signing key whose public half is committed in
`.github/release-allowed-signers`, then push that exact tag. Tag pushes publish;
a dispatch with `dry_run=false` can resume only the same signed tag. Never move
an existing version tag or replace published bytes. There is no local publication
fallback. Releases include commit-bound tar/zip archives, `RELEASE-NOTES.md`,
`ASSET-INVENTORY.json`, and `SHA256SUMS`, titled `Agent Scripts X.Y.Z`.

The shared source archetype must include the `tag-prefix` and `release-name`
inputs before this caller is enabled; the caller remains pinned to `@v1`.
No npm, Apple signing, Homebrew, Sparkle, or deployment credentials are needed.
The broader cross-project guardrails remain in [docs/RELEASING.md](docs/RELEASING.md).
