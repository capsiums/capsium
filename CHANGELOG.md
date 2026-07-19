# Changelog

## 0.2.0

### Changed

- Migrated all package configuration models from shale to lutaml-model.
- All configuration files now follow the canonical schemas
  (ARCHITECTURE.md sections 2-6):
  - `metadata.json`: `dependencies` is an object of `guid -> semver range`;
    `name`/`version`/`description`/`guid`/`uuid` are the required fields.
  - `manifest.json`: a `resources` object keyed by package-relative path
    (`type`, `visibility`, optional `version`).
  - `routes.json`: optional top-level `index` plus a `routes` array with
    discriminated kinds (`resource` / `dataset` / handler).
  - `storage.json`: `storage.dataSets` object; dataset `source` and
    `schemaFile` are package-relative paths.
- Legacy (pre-0.2) configuration files are accepted on read and normalized
  to the canonical forms; writers emit only the canonical forms.
- Manifest and routes auto-generation is deterministic (sorted); HTML files
  get dual routes, the index HTML gets `/`, datasets get
  `/api/v1/data/<id>`.
- The reactor serves dataset routes as JSON, sets `Cache-Control: public,
  max-age=31536000` on static resources (configurable), responds 501 to
  handler routes, and rejects packages that fail integrity verification.
- The CLI exits nonzero on errors.

### Added

- `security.json` with SHA-256 checksums over every package file, generated
  at pack time; verified automatically on load (`Package#verify_integrity`,
  `Capsium::Package::Security::IntegrityError` on mismatch).
- `capsium package validate <path|cap>`: per-check validation report
  (metadata formats, on-disk existence of manifest resources, route targets
  and dataset sources, dataset JSON-schema validation, checksums, external
  http(s) references in content), exit status 1 on any failure.
- `capsium package unpack <cap> [-o dir]`.
- `Capsium::Package::Validator` and `Capsium::Package::Security`.

### Removed

- `Capsium::Protector` (bit-rotted, insecure; encryption/signing is
  deferred to a later phase).
- shale dependency (replaced by lutaml-model); base64 dependency.
- Unused constants `Package::PACKAGING_FILE`, `Package::SIGNATURE_FILE`,
  `Package::ENCRYPTED_PACKAGING_FILE`, `Routes::DEFAULT_INDEX_TARGET`.
