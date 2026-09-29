# Yan Yu Jiang Hu x86 Android 7 Cloud Phone

[简体中文](README.md) | **English** | [Implementation overview](OVERVIEW.en.md)

An Android 7 cloud phone for the x86 environment used by **Yan Yu Jiang Hu**. Both `image` and `dev` run **two containers: Android and web**, using the same Compose generator. Defaults: 4 vCPU, 6 GiB RAM, 720×1280, Asia/Shanghai timezone and a random administrator password generated and printed at first start.

Search keywords: Yan Yu Jiang Hu, x86 Android 7 cloud phone, Android 7.1.1, API 25, x86_64, Docker, KVM, Houdini, Magisk, browser control.

The game APK is not included. The guest is x86_64; ARM APKs still use Houdini translation and can perform differently from native x86 APKs.

## Quick start

Requires Linux x86_64, Docker Engine, the Docker Compose plugin and `/dev/kvm`. Suggested minimum: 4 logical CPUs, 12 GiB RAM and 30 GiB disk space. Virtual-machine hosts require nested virtualization.

On a new machine, check requirements and install dependencies as needed:

```bash
chmod +x check-host.sh install-deps.sh android7.sh
sudo ./check-host.sh
# If dependencies are missing, install and check again
./install-deps.sh --dry-run
sudo ./install-deps.sh
sudo ./check-host.sh
```

An initial failure for missing Docker is expected before installation. Enable hardware/nested virtualization in BIOS or through your provider when required. After checking, continue with image startup below.

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

Open `http://localhost:8000` locally or `http://<server-ip>:8000` remotely, sign in as `admin` with the initial password printed by the script, then click the device's `connect` link. By default the port is bound to all IPv4 interfaces; remote access also requires network reachability and firewall permission. The script creates no tunnels. The script initializes the password before publishing the web port.

```bash
./android7.sh image status
./android7.sh image log
./install-apk.sh -c yanyu-android7 /path/to/game.apk
```

## Pull remote images only

The standalone `android7-image.sh` **only downloads the Android and web images**. It does not build, push, create/start containers, or generate volumes/configuration. It needs Docker and registry connectivity, but does not depend on `android7.sh`, Compose or KVM.

```bash
chmod +x android7-image.sh
./android7-image.sh
# Use sudo ./android7-image.sh if Docker access requires elevated permissions
```

Defaults are the `1.1-android` and `1.1-web` tags above. Every invocation runs `docker pull` against the registry, including for locally cached tags; Docker reuses unchanged layers. The platform is `linux/amd64`, without required image digests. To download another pair:

```bash
./android7-image.sh myrepo/phone:1.2-android myrepo/phone:1.2-web
```

Either pull failing returns a nonzero exit code; already downloaded images are retained. Running containers are not updated. For private registries, run `docker login` under the same user first. The original `android7.sh image pull` also starts the phone; **use `android7-image.sh` when you only want to download images**.

## Host checks and dependency installation

Both standalone scripts provide `--help` and use the complete toolset: Docker, Compose, Buildx, Python 3, curl, 7z and SHA256 tools. There is no image/dev mode selection. Both ports 8000 and 8001 are checked by default. Neither script starts a cloud phone nor changes its data.

| Script | Purpose |
| --- | --- |
| `check-host.sh` | Check Linux/x86_64, CPU, memory, project/Docker disk space, Docker/Compose, KVM and the web port |
| `install-deps.sh` | Install missing dependencies on Ubuntu 22.04/24.04/26.04 or Debian 12/13 (x86_64, systemd) |

```bash
# Install and check the complete toolset; no deployment/build mode selection
sudo ./install-deps.sh
sudo ./check-host.sh

# Check another existing data directory and port without changing deployment settings
sudo ./check-host.sh --disk-path /mnt/cloudphone --port 8000
```

The checker makes no network requests, downloads or containers. It creates and immediately closes an empty KVM VM with no vCPU or RAM. Python 3 is required for this probe; missing tools or insufficient permissions fail verification rather than treating the mere presence of `/dev/kvm` as success. Remote Docker, Docker Desktop and rootless Docker are unsupported. Unprivileged checks only try non-interactive sudo without prompting; use sudo as above for a complete check.

`FAIL` means a required check failed or could not be completed. `WARN` means a resource recommendation is unmet or a port is occupied (possibly by the existing phone). Exit codes: `0` required checks passed, `1` failures, `2` invalid arguments. **Warnings can still produce exit code 0; read the report.** For one phone, allow 4 logical CPUs, 12 GiB total RAM and 8 GiB available RAM before startup; disk checks use a 30 GiB free-space recommendation; allow 60 GiB when also downloading sources and building images. Check capacity separately if containerd stores images on another filesystem. This does not verify game performance, download connectivity, HTTPS or remote streaming.

The installer supports a no-change `--dry-run`. It uses Docker's signed official APT repository, verifies the signing-key fingerprint when creating that repository, and relies on APT for package signature-chain/hash verification. Existing official repository configuration is reused without overwriting administrator settings. Host package versions are outside the cloud-phone image source lock.

Installation follows Docker's official instructions for [Ubuntu](https://docs.docker.com/engine/install/ubuntu/) and [Debian](https://docs.docker.com/engine/install/debian/).

A complete existing Docker installation is retained. If components are missing and distribution Docker/containerd packages conflict with Docker CE, installation stops without removing them. Only missing packages are requested, although APT may update dependencies to satisfy them. The script enables Docker at boot and starts it. If `/dev/kvm` is absent, it tries loading the Intel/AMD KVM module; it cannot configure BIOS or provider-side nested virtualization. It does not add users to the Docker group, configure firewalls or create tunnels. Rerun the checker after installation, then start the phone.

## Modes

| Aspect | `image` | `dev` |
| --- | --- | --- |
| Services | Separate Android and web containers | Same |
| Container names | `yanyu-android7` + `yanyu-ws-scrcpy-web` | `yanyu-android7-dev` + `yanyu-ws-scrcpy-web-dev` |
| Network | Web shares Android's network namespace; host port 8000 is published | Same topology; host port 8001 |
| Access | Default `0.0.0.0`; safe mode `127.0.0.1` | Same |
| Settings, health checks, startup order | Shared generator | Same |
| Images | Pull/reuse two prebuilt images | Build from pinned sources |
| System files | Embedded in Android image | Read-only `patched/` mounts |
| Android state | `yanyu-android7-data` volume | `docker-state-dev/` |
| Web state | `yanyu-ws-scrcpy-data` volume | `ws-scrcpy-data-dev/` |

Image mode uses `yanyu-android7` and `yanyu-ws-scrcpy-web`; dev appends `-dev` to each name. State remains separate. Image uses port 8000 and dev uses 8001, so both can run together with sufficient resources. The examples switch to a single running mode using `down`, which removes containers while preserving data. Ownership checks remain in place, and switching does not migrate data.

```bash
# image → dev
./android7.sh image down
./android7.sh dev start

# dev → image
./android7.sh dev down
./android7.sh image start

# Image mode: the container name is optional
./install-apk.sh /path/to/game.apk

# Dev mode: specify the container with the -dev suffix
./install-apk.sh -c yanyu-android7-dev /path/to/game.apk
```

Legacy dev containers, including versions that used names without a suffix, remain manageable through the saved configuration. Run `dev down`, then `dev start` to adopt the `-dev` names while retaining existing directory data.

## Data locations and migration

Image mode uses the independent Docker volumes `yanyu-android7-data` and `yanyu-ws-scrcpy-data`. Dev uses project directories `docker-state-dev/` and `ws-scrcpy-data-dev/`; runtime state is not shared.

```bash
# Old dev directories docker-state/ and ws-scrcpy-data/ → new -dev directories
./android7.sh dev migrate
./android7.sh dev start

# image → dev (destination dev directories must be empty)
./android7.sh data migrate image dev
./android7.sh dev start

# dev → image (destination image volumes must be empty or absent)
./android7.sh data migrate dev image
./android7.sh image start
```

Choose only the migration direction you need. Migration stops involved containers and copies complete Android and web state, preserving apps, accounts, passwords, permissions and sparse disks. **Source data is retained; nonempty destinations are rejected.** Migration does not build, publish or start containers; run the destination's `start` afterwards. Other running containers referencing the data block copying.

If legacy dev data exists but the new directory is empty, startup asks you to run `dev migrate` instead of silently creating an empty phone. Old directories remain as backups; `.android7-legacy-dev-migrated` records that they should no longer be checked automatically. Later `dev purge` clears only the new directories.

Interrupted copies leave `.android7-migration-TARGET.pending`, blocking destination startup. Source data remains unchanged. Inspect the target, discard the partial copy using the target mode's `purge`, then retry migration. The copy includes the same Android identity and web login state; afterwards each deployment saves independently without automatic synchronization.

## Initial web password and password changes

First startup generates a **32-character random password** containing uppercase/lowercase letters, digits and symbols, then prints it with the username `admin`. Each web data store gets a unique password; there is no shared default and no plaintext password in images, Compose or `.env`. Initialization runs in a temporary container with no published ports and also works with existing two-container releases.

**Existing passwords are preserved.** Normal restarts, Android `reset` and data migration retain web accounts. The initial password is printed once. Its temporary handoff file, `/data/.android7-initial-password` in web storage, uses mode `0600` and is removed after display. If you miss the output or forget the password, run on the host:

```bash
# Change/reset the image deployment's admin password
./android7.sh image password

# Change/reset the dev deployment's admin password
./android7.sh dev password
```

The deployment must be running. Enter the new password twice (8–128 characters); input is hidden and passed through stdin, not command arguments or environment variables. The old password is not required: this command relies on host Docker administration privileges. Changing it revokes the administrator's existing sessions without changing Android app data. The two deployments keep separate web accounts.

## Web access and safe mode

The default allows access through the server IP, with the generated password still required for sign-in. Safe mode changes only the bind address; it does not disable authentication or automatically enable HTTPS.

| Mode | Default remote URL | Safe-mode local URL |
| --- | --- | --- |
| image | `http://<server-ip>:8000` | `http://127.0.0.1:8000` |
| dev | `http://<server-ip>:8001` | `http://127.0.0.1:8001` |

```bash
# Localhost access only
./android7.sh image start --safe
./android7.sh dev start --safe

# Restore access through the server IP
./android7.sh image start --public
./android7.sh dev start --public
```

Each mode saves its choice in `.android7-image.env` or `.android7.env`. Later starts without an option retain it; without a saved choice the default is `public`. Use `start` to apply changed bindings: `restart` does not update ports. Recreating affected containers briefly interrupts connections but preserves Android and web login data. `image pull` also accepts these options.

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
| `image password` / `dev password` | Change/reset the corresponding web admin password with hidden input |
| `image stop` | Stop both containers; retain data |
| `image restart` | Restart both containers |
| `image down` | Remove both containers/network; retain both volumes |
| `image reset` | After YES, reset Android and restart both containers; retain web accounts/passwords |
| `image purge` | After YES, remove both containers and delete both volumes; do not restart |
| `image log` / `image status` | Logs / status of both services |
| `dev start` | Prepare sources, build and start two development containers |
| `dev stop` / `dev restart` / `dev down` | Manage development containers; retain data |
| `dev reset` | After YES, reset Android and restart; retain web accounts |
| `dev purge` | After YES, remove development containers and clear Android/web data; do not restart |
| `dev migrate` | Copy legacy dev state into empty -dev directories, retaining the source |
| `data migrate SOURCE TARGET` | Copy state between image / dev; the destination must be empty |
| `dev log` / `dev status` | Development logs / detailed Android diagnostics |

Custom deployments require both image references:

```bash
./android7.sh image start myrepo/phone:android myrepo/phone:web
```

Deployment uses image tags only, without pinning release-image SHA256 digests. Selected tags are saved in `.android7-image.env`; subsequent argument-free starts reuse them. To update, pull the new pair and explicitly pass both references to `image start`. Compose recreates affected containers while retaining volumes.

`image reset` deletes only `avd/` and `android.ready` inside the Android volume, clearing games, app data and Android accounts/settings while retaining web accounts/passwords and the selected images. After confirmation it stops both services, clears that state and starts them again, without building or publishing images.

`purge` permanently deletes games, app files, accounts, settings, logs and web passwords for the selected mode. Images, source and build/download caches remain. Any answer other than YES, or end-of-input, cancels. References from other containers block data removal. The next start creates a fresh phone and prints a new random password.

Original flat commands such as `./android7.sh start` and `./android7.sh purge` remain aliases for **dev** commands.

## Build and publish both images

Building additionally requires curl, 7z and sha256sum. The main script checks host tools without installing them; on a new host, run `sudo ./install-deps.sh` first. Source URLs, base-image digests and artifact hashes are pinned; Ubuntu packages inside images use a dated snapshot.

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

The `WEB_BIND_IP=0.0.0.0` setting below allows access through the server IP; use `WEB_BIND_IP=127.0.0.1` for safe mode.

Start Android and wait for readiness:

```bash
WEB_BIND_IP=0.0.0.0
docker run -d --name yanyu-android7 \
  --device /dev/kvm --shm-size 2g --stop-timeout 45 \
  --restart unless-stopped -p "${WEB_BIND_IP}:8000:8000" \
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

Newly built web images also generate an initial password during manual Docker deployment. After the web service is ready, display it once with the command below. Manual deployments of older images still use first-visit password setup; script deployments handle initialization automatically:

```bash
docker exec --user 1000:1000 yanyu-ws-scrcpy-web \
  node /app/dist/android7-password.cjs show
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
- New or factory-reset Android data defaults to **Simplified Chinese (China)** (`zh-Hans-CN`). The first boot initializes the language and restarts Android framework services once. Existing data and subsequent manual language choices are preserved. Both modes share this logic; published images must be rebuilt and deployed to include the new default.
- 720×1280, 320 dpi, KVM CPU acceleration, SwiftShader software rendering; GLDMA disabled to avoid an old-kernel crash with 6 GiB RAM.
- Houdini ARM32/ARM64, Magisk 27 and AOSP su; the guest watchdog restores adbd after root apps stop it.
- Authentication enabled by default, with a generated 32-character random initial password and support for 8–128 character replacements, native hashing, sessions and CSRF checks. Unexpected disconnects retry; manually closed streams stay closed.
- Both containers use `Asia/Shanghai`; guest timezone is not explicitly changed. `docker exec yanyu-android7 date '+%Z %z'` should show `+0800`.

```bash
# Diagnostics and manual APK installation
docker exec yanyu-android7 /opt/android/status.sh
docker cp /path/to/game.apk yanyu-android7:/tmp/game.apk
docker exec yanyu-android7 adb -s emulator-5556 install -r /tmp/game.apk
docker exec yanyu-android7 rm /tmp/game.apk
```

For unavailable web access, inspect both services' health/logs. Check for other programs occupying image port 8000 or dev port 8001; also check bind mode and firewall rules for remote access. If an existing password stops working or a new initial password appears, check the web volume. Two containers alone do not guarantee faster gameplay; APK architecture, rendering, encoding and frame rate still matter.

## Project files

Only `android7.sh`, `android7-image.sh`, `install-apk.sh`, `check-host.sh`, `install-deps.sh`, Chinese/English README and OVERVIEW files, and `.gitignore` are versioned. Scripts/help are English; documentation is separated by language.

`docker/`, `patched/`, `downloads/`, Compose/environment files, manifests and runtime data are generated and ignored. Edit the main generator rather than generated Compose/Dockerfiles, which are overwritten. Separate `image/` and `tests/` directories are unnecessary.

## Upstream projects

- [Android 7 Houdini/Magisk system](https://github.com/xBZZZZ/android_7.1.1_x86_64_libhoudini_magisk): commit `159eb29934e09fd15e7490326c53eb47732b0f57`.
- [ws-scrcpy-web](https://github.com/bilbospocketses/ws-scrcpy-web): beta.129 with a pinned digest.
- [Android Emulator](https://developer.android.com/studio/run/emulator-commandline): build 15917651.

Follow upstream and game usage/redistribution terms. This is not an official game distribution.
