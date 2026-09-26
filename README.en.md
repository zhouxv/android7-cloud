# Yan Yu Jiang Hu x86 Android 7 Cloud Phone

[简体中文](README.md) | **English** | [Implementation overview](OVERVIEW.en.md)

An Android 7 cloud phone for the x86 environment used by **Yan Yu Jiang Hu**. Both `image` and `dev` run **two containers: Android and web**, using the same Compose generator. Defaults: 4 vCPU, 6 GiB RAM, 720×1280, Asia/Shanghai timezone and administrator password setup on first visit.

Search keywords: Yan Yu Jiang Hu, x86 Android 7 cloud phone, Android 7.1.1, API 25, x86_64, Docker, KVM, Houdini, Magisk, browser control.

The game APK is not included. The guest is x86_64; ARM APKs still use Houdini translation and can perform differently from native x86 APKs.

## Quick start

Requires Linux x86_64, Docker Engine, the Docker Compose plugin and `/dev/kvm`. Suggested minimum: 4 logical CPUs, 12 GiB RAM and 30 GiB disk space. Virtual-machine hosts require nested virtualization.

Both images use the same repository, with separate tags:

| Component | Image | Container | Volume |
| --- | --- | --- | --- |
| Android | `blueobsidian/android7-magisk-yanyujianghu:1.1-android` | `yanyu-android7` | `yanyu-android7-data` |
| Web | `blueobsidian/android7-magisk-yanyujianghu:1.1-web` | `yanyu-ws-scrcpy-web` | `yanyu-ws-scrcpy-data` |

**Build or publish these new tags first. The old combined `1.0` image cannot be used for this two-container deployment.**

```bash
chmod +x android7.sh
./android7.sh image pull
```

Defaults select the two release tags. Reuse existing local images or pull only missing ones, validate both components, then create the two containers. Web starts after Android passes its health check. Deployment requires Compose but no SDK, system-file cache or source-build tools.

Open `http://localhost:8000`, set the `admin` password, then click the device's `connect` link. For remote access, use your existing port forwarding; the script creates no tunnels. Complete password initialization before allowing other people access.

```bash
./android7.sh image status
./android7.sh image log
./install-apk.sh -c yanyu-android7 /path/to/game.apk
```

## Modes

| Aspect | `image` | `dev` |
| --- | --- | --- |
| Services | Separate Android and web containers | Same |
| Network | Web shares Android's network namespace; only local port 8000 is published | Same |
| Settings, health checks, startup order | Shared generator | Same |
| Images | Pull/reuse two prebuilt images | Build from pinned sources |
| System files | Embedded in Android image | Read-only `patched/` mounts |
| Android state | `yanyu-android7-data` volume | `docker-state/` |
| Web state | `yanyu-ws-scrcpy-data` volume | `ws-scrcpy-data/` |

Modes have separate containers/data but both use port 8000 by default. Stop the other deployment before switching. Switching modes does not automatically migrate data.

## Commands

```bash
./android7.sh help
./android7.sh help image
./android7.sh help dev
```

| Command | Behavior |
| --- | --- |
| `image pull` / `image start` | Pull missing images and start two containers |
| `image build` | Build both images, check login and automatically push to Docker Hub; do not start containers |
| `image stop` | Stop both containers; retain data |
| `image restart` | Restart both containers |
| `image down` | Remove both containers/network; retain both volumes |
| `image purge` | After YES, remove both containers and delete both volumes; do not restart |
| `image log` / `image status` | Logs / status of both services |
| `dev start` | Prepare sources, build and start two development containers |
| `dev stop` / `dev restart` / `dev down` | Manage development containers; retain data |
| `dev reset` | After YES, reset Android and restart; retain web accounts |
| `dev purge` | After YES, remove development containers and clear Android/web data; do not restart |
| `dev log` / `dev status` | Development logs / detailed Android diagnostics |

Custom deployments require both image references:

```bash
./android7.sh image start myrepo/phone:android myrepo/phone:web
```

Deployment uses image tags only, without pinning release-image SHA256 digests. Selected tags are saved in `.android7-image.env`; subsequent argument-free starts reuse them. To update, pull the new pair and explicitly pass both references to `image start`. Compose recreates affected containers while retaining volumes.

`purge` permanently deletes games, app files, accounts, settings, logs and web passwords for the selected mode. Images, source and build/download caches remain. Any answer other than YES, or end-of-input, cancels. References from other containers block data removal. The next start creates a fresh phone and requires a new administrator password.

Original flat commands such as `./android7.sh start` and `./android7.sh purge` remain aliases for **dev** commands.

## Build and publish both images

Building additionally requires curl, 7z and sha256sum. Host tools are checked, not automatically installed. Source URLs, base-image digests and artifact hashes are pinned; Ubuntu packages use a dated snapshot.

```bash
# Build and push defaults: 1.1-android and 1.1-web
./android7.sh image build

# Or provide two new tags
./android7.sh image build \
  blueobsidian/android7-magisk-yanyujianghu:1.2-android \
  blueobsidian/android7-magisk-yanyujianghu:1.2-web
```

After building the default tags, run `./android7.sh image start`. For custom tags or a saved configuration selecting another version, use the printed `Deploy:` command with both explicit tags. Rebuilding may change output digests; tag-based startup does not depend on those digests.

The build reuses the same Android/web base images as `dev`. The Android release embeds verified clean system files; the web base is tagged directly as the web release. Services are never combined, and current phone accounts/data are not copied.

After building, `image build` automatically runs `docker login`. Docker validates and reuses saved credentials; if no valid login exists, follow its terminal instructions to complete browser verification. It then pushes Android and web in order, reporting publication success only after both succeed. Custom build targets must be Docker Hub `USER/REPOSITORY:TAG` names you can push to.

Cancelled login or a failed push exits with an error and retains local images. An earlier successful push remains published. To retry publication separately, run:

```bash
docker login -u blueobsidian
docker push blueobsidian/android7-magisk-yanyujianghu:1.1-android
docker push blueobsidian/android7-magisk-yanyujianghu:1.1-web
```

Deploy using the two published tags; no image digests are required. `dev start` still builds/runs locally without publishing.

## Manual Docker deployment

Pull the published pair and create two volumes:

```bash
ANDROID_IMAGE=blueobsidian/android7-magisk-yanyujianghu:1.1-android
WEB_IMAGE=blueobsidian/android7-magisk-yanyujianghu:1.1-web
docker info
test -e /dev/kvm
docker pull "$ANDROID_IMAGE"
docker pull "$WEB_IMAGE"
docker volume create yanyu-android7-data
docker volume create yanyu-ws-scrcpy-data
```

Start Android and wait for readiness:

```bash
docker run -d --name yanyu-android7 \
  --device /dev/kvm --shm-size 2g --stop-timeout 45 \
  --restart unless-stopped -p 127.0.0.1:8000:8000 \
  -v yanyu-android7-data:/data "$ANDROID_IMAGE"

for attempt in $(seq 1 90); do
  health=$(docker inspect -f '{{.State.Health.Status}}' yanyu-android7)
  [ "$health" = healthy ] && break
  sleep 5
done
test "$health" = healthy
```

Only after that check succeeds, start web:

```bash
docker run -d --name yanyu-ws-scrcpy-web \
  --network container:yanyu-android7 --stop-timeout 30 \
  --restart unless-stopped -e WS_SCRCPY_ALLOW_REMOTE_ADMIN=0 \
  -v yanyu-ws-scrcpy-data:/data "$WEB_IMAGE"
```

Manual containers are not Compose-managed and must not be mixed with same-named script containers. To switch to the script, stop/remove the manual containers, retain both volumes and run `image start`. When manually recreating Android, recreate web too so it joins the new network namespace.

```bash
# Manual cleanup retaining both data volumes
docker stop yanyu-ws-scrcpy-web yanyu-android7
docker rm yanyu-ws-scrcpy-web yanyu-android7
```

## Migrate from the old combined 1.0 image

The old `/data/web` state must become the new web container's `/data`. Prepare both new images, stop the old container for consistent data, retain Android's volume and copy web state to its own volume. Reinitialize web dependencies because their paths differ; retain the database and accounts.

These commands assume default names and that **`yanyu-ws-scrcpy-data` does not exist yet**. If it exists, inspect it first; do not overwrite it.

```bash
# Record the old image and mounts for rollback
docker inspect yanyu-android7 --format '{{.Image}} {{json .Mounts}}'
# Both new images must be ready
docker image inspect blueobsidian/android7-magisk-yanyujianghu:1.1-android >/dev/null
docker image inspect blueobsidian/android7-magisk-yanyujianghu:1.1-web >/dev/null
# This should report no such volume; if it exists, stop and inspect it
docker volume inspect yanyu-ws-scrcpy-data
```

After confirming those conditions:

```bash
docker stop yanyu-android7
docker rename yanyu-android7 yanyu-android7-legacy
docker volume create yanyu-ws-scrcpy-data
docker run --rm --network none --user 0:0 --entrypoint /bin/sh \
  -v yanyu-android7-data:/old:ro -v yanyu-ws-scrcpy-data:/new \
  blueobsidian/android7-magisk-yanyujianghu:1.1-web \
  -ec 'test -f /old/web/wsscrcpy.db; test -z "$(ls -A /new)"; cp -a /old/web/. /new/; rm -rf /new/dependencies; chown -R 1000:1000 /new'
./android7.sh image start
```

Verify the game and web login before removing the stopped `yanyu-android7-legacy` container. The original Android volume retains its old `web/` subtree as an account backup from migration; the new web service uses its independent volume.

If migration fails, run `image down` to remove new services, rename the legacy container back and start it. Never run old/new Android containers on the same volume simultaneously. While the legacy container exists, `image purge` refuses volume deletion because that container still references Android's volume.

## Defaults and troubleshooting

- Android 7.1.1 / API 25 / x86_64; 4 vCPU, 6144 MiB RAM, 8 GiB data partition.
- 720×1280, 320 dpi, KVM CPU acceleration, SwiftShader software rendering; GLDMA disabled to avoid an old-kernel crash with 6 GiB RAM.
- Houdini ARM32/ARM64, Magisk 27 and AOSP su; the guest watchdog restores adbd after root apps stop it.
- Authentication enabled by default, with an 8–128 character first administrator password, native hashing, sessions and CSRF checks. Unexpected disconnects retry; manually closed streams stay closed.
- Both containers use `Asia/Shanghai`; guest timezone is not explicitly changed. `docker exec yanyu-android7 date '+%Z %z'` should show `+0800`.

```bash
# Diagnostics and manual APK installation
docker exec yanyu-android7 /opt/android/status.sh
docker cp /path/to/game.apk yanyu-android7:/tmp/game.apk
docker exec yanyu-android7 adb -s emulator-5556 install -r /tmp/game.apk
docker exec yanyu-android7 rm /tmp/game.apk
```

For unavailable web access, inspect both services' health/logs. Stop conflicting deployments if port 8000 is occupied. Unexpected password setup usually warrants checking the web volume. Two containers alone do not guarantee faster gameplay; APK architecture, rendering, encoding and frame rate still matter.

## Project files

Only `android7.sh`, `install-apk.sh`, Chinese/English README and OVERVIEW files, and `.gitignore` are versioned. Scripts/help are English; documentation is separated by language.

`docker/`, `patched/`, `downloads/`, Compose/environment files, manifests and runtime data are generated and ignored. Edit the main generator rather than generated Compose/Dockerfiles, which are overwritten. Separate `image/` and `tests/` directories are unnecessary.

## Upstream projects

- [Android 7 Houdini/Magisk system](https://github.com/xBZZZZ/android_7.1.1_x86_64_libhoudini_magisk): commit `159eb29934e09fd15e7490326c53eb47732b0f57`.
- [ws-scrcpy-web](https://github.com/bilbospocketses/ws-scrcpy-web): beta.129 with a pinned digest.
- [Android Emulator](https://developer.android.com/studio/run/emulator-commandline): build 15917651.

Follow upstream and game usage/redistribution terms. This is not an official game distribution.
