# Bitwarden SDK for Swift

GPL-only Swift bindings and native libraries for the provider-neutral alias v1 SDK.
Generated Swift APIs, FFI headers, and both native slices are built from the exact
SDK source commit recorded in `VERSION` and `ALIAS_SDK_PROVENANCE.json`.

The package supports arm64 iOS devices and arm64 iOS simulators. It exposes an
injected `AliasProviderAdapter`, alias lifecycle operations, journal and
reconciliation APIs, and the encrypted login `aliasReference` field. Adapter
credentials and provider transport stay outside the common SDK boundary.

Bindings also include current vault encryption metadata, repositories,
registration `openOrgInvite`, and restricted-view partial semantics. Generated
files under `Sources/BitwardenSdk` must be regenerated with the matching native
library, never edited independently.

Run `scripts/verify-provider-neutral-alias.sh` to verify source provenance,
archive checksum, immutable binary URL, GPL boundary, slices, and alias ABI.
The archive script preserves externally defined static-link symbols while
normalizing archive ordering, timestamps, and permissions.

This is a local native build distribution. Provenance records only checks
actually performed; it does not claim a GitHub Actions build or attestation.
Use the verifier without arguments for this distribution. Passing an extracted
release candidate directory is unsupported for `build.kind: local-native`.

The optional candidate-directory mode compares a separately preverified candidate
against provenance containing all seven `verifiedEvidence` SHA-256 hashes:
Swift archive, checksum index, handoff manifest, CycloneDX SBOM, Sigstore bundle,
Swift API report, and dependency audit report. It retains the package, ABI,
checksum, audit, source, and reproducible archive checks. It checks the pinned
Sigstore bundle bytes, but does not itself verify signatures or establish the
attestation's trust. Do not add candidate evidence claims to local-native
provenance merely to enable this mode.
