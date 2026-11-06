# 0012. `S3Store` na minio-go

- **Status:** Przyjęty
- **Data:** 2026-11-06
- **Dotyczy:** silo-server

## Kontekst

Bloby (surowe wiadomości, załączniki, uploady draftów, miniatury) są adresowane treścią i niemutowalne ([plan 3.16](../../ARCHITECTURE_AND_PLAN.md#316-blobstore)). `FSStore` wymaga wolumenu lokalnego; instancje na hostingu z magazynem obiektowym (MinIO obok compose, AWS S3, Backblaze B2, Wasabi) chcą trzymać bloby poza dyskiem serwera. Klucz bloba to `sha256` treści, więc musi być znany przed zapisem obiektu.

## Decyzja

`SILO_BLOB_BACKEND=s3` wybiera `S3Store` oparty na `github.com/minio/minio-go/v7`.

- Klucze `<SILO_BLOB_S3_PREFIX>/ab/cd/<sha256>` – ten sam układ co `FSStore`, dedup przez content-addressing.
- `Put` najpierw **spoolowanie do pliku tymczasowego** z liczeniem `sha256`, potem `PutObject` ze znanym rozmiarem; serwer potrzebuje miejsca tymczasowego na największy blob.
- **Brak automatycznego tworzenia bucketu:** `serve` sprawdza istnienie bucketu przy starcie i kończy się błędem konfiguracji; uprawnienia i polityki bucketu należą do administratora.
- Konfiguracja `SILO_BLOB_S3_*` (endpoint, bucket, klucze, region, prefiks, TLS, path-style dla MinIO).
- Testy integracyjne na obrazie MinIO przez testcontainers; domyślny obraz `ghcr.io/coollabsio/minio:RELEASE.2025-10-15T17-29-55Z` (nadpisanie `SILO_TEST_MINIO_IMAGE`), bo `minio/minio` z Docker Hub i `quay.io/minio/minio` były niedostępne z maszyny deweloperskiej (odmowa pobrania).

## Konsekwencje

- Bloby można trzymać poza hostem; backup `full` obejmuje wtedy tylko bazę – bucket archiwizuje się narzędziami dostawcy (wersjonowanie, replikacja).
- Zmiana backendu nie przenosi blobów: mirror to cache (`rebuild-cache` pobierze ponownie), bloby `local` (uploady, drafty, wiadomości zaplanowane) trzeba skopiować ręcznie (`docs/admin`).
- Zależność od minio-go (podbite zależności pośrednie); obraz testowy MinIO z mirrora ghcr to ryzyko łańcucha dostaw w CI – do zastąpienia mirrorem organizacji.

## Alternatywy

- **aws-sdk-go-v2:** pełne S3 AWS, ale duży zestaw modułów i wolniejsza kompilacja; zgodność z MinIO i innymi dostawcami S3 przez opcje endpointu/path-style podobna. Odrzucone ze względu na rozmiar.
- **Własny klient S3 (podpis SigV4 na `net/http`):** mało kodu na `Put`/`Get`/`Delete`, ale podpisy, multipart i błędy dostawców to źródło trudnych błędów. Odrzucone.
- **Zapis strumieniowy bez spoolowania (multipart pod kluczem tymczasowym + server-side copy):** oszczędza dysk, ale podwaja operacje i zostawia porzucone obiekty przy awarii. Odrzucone na 1.0.
