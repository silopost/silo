# 0012. `S3Store` on minio-go

- **Status:** Accepted
- **Date:** 2026-11-06
- **Applies to:** silo-server

## Context

Blobs (raw messages, attachments, draft uploads, thumbnails) are content-addressed and immutable. `FSStore` requires a local volume; instances on hosting with object storage (MinIO next to compose, AWS S3, Backblaze B2, Wasabi) want to keep blobs off the server's disk. The blob key is the `sha256` of the content, so it must be known before the object is written.

## Decision

`SILO_BLOB_BACKEND=s3` selects `S3Store`, based on `github.com/minio/minio-go/v7`.

- Keys `<SILO_BLOB_S3_PREFIX>/ab/cd/<sha256>` – the same layout as `FSStore`, deduplication through content addressing.
- `Put` first **spools to a temporary file** while computing the `sha256`, then calls `PutObject` with a known size; the server needs temporary space for the largest blob.
- **No automatic bucket creation:** `serve` checks that the bucket exists at start-up and exits with a configuration error; bucket permissions and policies belong to the administrator.
- Configuration through `SILO_BLOB_S3_*` (endpoint, bucket, keys, region, prefix, TLS, path-style for MinIO).
- Integration tests on a MinIO image through testcontainers; the default image is `ghcr.io/coollabsio/minio:RELEASE.2025-10-15T17-29-55Z` (override with `SILO_TEST_MINIO_IMAGE`), because `minio/minio` from Docker Hub and `quay.io/minio/minio` were unavailable from the development machine (pulls refused).

## Consequences

- Blobs can be kept off the host; the `full` backup then covers only the database – the bucket is archived with the provider's tools (versioning, replication).
- Changing the backend does not move blobs: the mirror is a cache (`rebuild-cache` fetches it again), while `local` blobs (uploads, drafts, scheduled messages) have to be copied by hand (`docs/admin`).
- A dependency on minio-go (bumped indirect dependencies); a MinIO test image from a ghcr mirror is a supply-chain risk in CI – to be replaced with an organization mirror.

## Alternatives

- **aws-sdk-go-v2:** full AWS S3, but a large set of modules and slower compilation; compatibility with MinIO and other S3 providers through endpoint/path-style options is similar. Rejected because of its size.
- **Our own S3 client (SigV4 signing on `net/http`):** little code for `Put`/`Get`/`Delete`, but signatures, multipart and provider errors are a source of hard bugs. Rejected.
- **Streaming writes without spooling (multipart under a temporary key + server-side copy):** saves disk, but doubles the operations and leaves abandoned objects on failure. Rejected for 1.0.
