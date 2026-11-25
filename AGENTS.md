# tombino104-store: notes for AI assistants and maintainers

This repo is a community app store for umbrelOS (`umbrel-app-store.yml`, id `tombino104`).
Umbrel reads it straight from GitHub: every folder `tombino104-<name>/` is one app.
Everything below was learned the hard way; follow it so a new app works first try.

## Layout of an app folder

| File | Purpose |
| --- | --- |
| `umbrel-app.yml` | Manifest: id (`tombino104-<name>`), name, version, port, category, description, `icon`, `gallery`. |
| `docker-compose.yml` | The services. Must contain no `app_proxy` image: Umbrel injects it. |
| `icon.svg` | 256x256 rounded-square icon, referenced by raw.githubusercontent URL in the manifest. |
| `gallery/` | Optional screenshots, referenced by raw URL. |

Rules that bite:

- `tagline` and other one-line YAML values containing `: ` **must be quoted**, or the manifest is invalid (this already happened once).
- Pick a unique host `port` (taken: 8000 vibravid, 8473 personal-os, 8474 homelab-savings, 8475 mini-qr, 8476 open-seo, 8477 hycanvas, 8478 chatwoot, 8479 colanode, 8480 taxhacker, 8481 upersite-crm, 3480 taskhit; next free: 8482).
- `app_proxy.environment`: `APP_HOST: <app-id>_<service>_1` (the container Umbrel creates) and `APP_PORT` (the port inside it).
  Add `PROXY_AUTH_ADD: "false"` when the app has its own accounts; leave the default when it has none (Umbrel's login then protects it).
- Never publish ports with `ports:`; everything goes through `app_proxy`.
- Persist data under `${APP_DATA_DIR}/data/...` (bind mounts), never named volumes.
- Secrets: use `${APP_SEED}` (stable per-app 64-hex secret) for JWT/secret keys and database passwords.
  `${DEVICE_DOMAIN_NAME}` is `umbrel.local` and is what to use when an app needs its own public URL.
- Images must exist for `linux/amd64` and `linux/arm64` (Raspberry Pi). Check with `docker buildx imagetools inspect <image>:<tag>`.
- Pin images as `repo:tag@sha256:digest`. Sidecars (postgres, redis) are pinned once and left alone.
- Optional user config (API keys): `env_file` with `required: false` pointing at `${APP_DATA_DIR}/data/<name>.env`, and document it in the description.
- Apps with a database or several processes need `depends_on` with a healthcheck so migrations do not race.

## Auto-updates

`.github/workflows/update-apps.yml` runs daily (05:17 UTC) and on demand (`gh workflow run update-apps.yml`).
It runs `.github/update-apps.sh`, which reads `.github/tracked-apps.txt` (`app|image|source`):

- `latest` (or a fixed tag): pin the digest of that tag; version = today's date (`2026.11.18`). Use it when the project only publishes `latest`.
- `gh:owner/repo`: image tag = newest GitHub release tag (the repo must be public: the Action cannot read private releases); version = that release without the `v`.
- `gh-nov:owner/repo`: same, for images tagged without the leading `v`.
- `tag-nov:owner/repo`: newest `vX.Y.Z` git tag, for projects without GitHub releases (`tombino104-taskhit`). If the image of a fresh tag is still building, that line fails and is retried the next day.
  TaskHit's folder was copied from `umbrel-store/` in its repo; manifest or compose changes made there must be copied here by hand. It needs `data/app/.gitkeep` and HTTPS (umbrelOS 2.x).

When the pinned digest changes, the script rewrites the `image:` line and bumps `version` in `umbrel-app.yml`;
Umbrel only offers an update when `version` changes. The workflow commits and pushes to `main`.
A line whose image or release cannot be found is reported as an error and skipped; the others still run.
Locally: `bash .github/update-apps.sh` (needs `docker buildx` and an authenticated `gh`; no Docker daemon needed).

Apps maintained by hand (their own releases, with release notes): `tombino104-homelab-savings` (see the homelab-savings repo: tag `vX.Y.Z`, CI publishes the image, then bump version + digest here) and `tombino104-personal-os`.

## Adding a new app: checklist

1. Read the project's own self-hosting docs and compose file. List every service and env var.
2. Check the images exist for both architectures and note digests (`docker buildx imagetools inspect`). Prefer a version tag over `latest`.
3. Create `tombino104-<name>/` with the files above. Collapse the project's compose into Umbrel's rules (no `ports`, bind mounts under `${APP_DATA_DIR}/data`, secrets from `${APP_SEED}`).
4. Validate: `APP_SEED=x APP_DATA_DIR=/tmp/x DEVICE_DOMAIN_NAME=umbrel.local docker compose -f app/docker-compose.yml -f stub.yml config -q`,
   where `stub.yml` gives `app_proxy` a dummy `image: alpine`. Also parse `umbrel-app.yml` with a YAML parser.
5. Add a line to `.github/tracked-apps.txt`, run `bash .github/update-apps.sh`, commit, push.
6. Test on a real Umbrel if you can (add `https://github.com/tombino104/tombino104-store` under App Store > Community stores).

## Apps that were looked at and not added

- **AppFlowy** (as of 2026-11): its self-host stack (AppFlowy-Cloud) has 11 services and needs a fixed public URL. Its compose uses `minio/minio` from Docker Hub, which no longer exists there, so the upstream compose does not even start. Needs a different S3 store (RustFS works in open-seo's stack, untested here) and a real Umbrel to test on. The GitHub release tags of AppFlowy-Cloud are stale (2025); its images are published under `latest`.

## Known limits

- None of these Docker stacks could be run where they were written (no Docker daemon on the authoring machine), only validated statically. Test them on a real Umbrel and fix what breaks.
- OpenSEO uses the project's older single-container image (builds itself at container start, slow first boot); its newer "standalone" image needs six services.
- Chatwoot and HyCanvas build their public links from `umbrel.local`.
