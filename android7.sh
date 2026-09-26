#!/usr/bin/env bash

# ============================================================
#
# Android 7.1.1 / API 25 / x86_64
# Houdini ARM32 + ARM64
# Magisk 27 root
# Android Emulator + KVM
#
# Quick start: ./android7.sh image pull
# Help:        ./android7.sh help [image|dev]
# Build:       ./android7.sh image build [ANDROID_IMAGE WEB_IMAGE]
# Development: ./android7.sh dev start
#
# First "dev start" or "image build":
#   - verifies Docker + KVM
#   - reuses/downloads pre-patched Houdini/Magisk image
#   - generates Docker runtime files
#   - verifies source-pinned Ubuntu and web image digests
#   - builds Android Emulator image
#   - starts Android only for "dev start"
#
# The script directory is the project root, even when invoked from elsewhere.
# Edit this source, not generated Dockerfiles, Compose or container scripts.
# No "set -e": critical operations explicitly propagate failures.
# ============================================================

set -u


# ============================================================
# Paths
# ============================================================

# Resolve all generated files and persistent data relative to this script,
# even when invoked from another working directory.
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1

PATCHED_DIR="${BASE_DIR}/patched"
SRC_DIR="${BASE_DIR}/src"

DOCKER_DIR="${BASE_DIR}/docker"
STATE_DIR="${BASE_DIR}/docker-state"

COMPOSE_FILE="${BASE_DIR}/compose.android7.yml"
ENV_FILE="${BASE_DIR}/.android7.env"

BASE_IMAGE_FILE="${BASE_DIR}/docker-base-image.txt"
MANIFEST_FILE="${BASE_DIR}/docker-manifest.txt"


# ============================================================
# Runtime names
# ============================================================

SERVICE_NAME="android7"
CONTAINER_NAME="android7-cloudphone"

RUNTIME_IMAGE="android7-cloudphone:api25-houdini-magisk-v1"

AVD_NAME="android7-houdini-root"

EMULATOR_PORT="5556"
ANDROID_SERIAL="emulator-${EMULATOR_PORT}"


# ============================================================
# Existing Houdini/Magisk image
# ============================================================

IMAGE_REPO="https://github.com/xBZZZZ/android_7.1.1_x86_64_libhoudini_magisk.git"

IMAGE_COMMIT="159eb29934e09fd15e7490326c53eb47732b0f57"

IMAGE_REPO_DIR="${SRC_DIR}/android_7.1.1_x86_64_libhoudini_magisk"

IMAGE_ARCHIVE="android_7.1.1_x86_64_libhoudini_magisk.7z"

PATCHED_SYSTEM="${PATCHED_DIR}/system.img"
PATCHED_RAMDISK="${PATCHED_DIR}/ramdisk.img"
PATCHED_MAGISK="${PATCHED_DIR}/Magisk-v27.0.apk"


# ============================================================
# Docker command
# ============================================================

DOCKER_CMD=()

# Published deployment uses the same two-service topology as development.
RELEASE_IMAGE="blueobsidian/android7-magisk-yanyujianghu:1.1-android"
RELEASE_WEB_IMAGE="blueobsidian/android7-magisk-yanyujianghu:1.1-web"
RELEASE_CONTAINER="yanyu-android7"
RELEASE_WEB_CONTAINER="yanyu-ws-scrcpy-web"
RELEASE_VOLUME="yanyu-android7-data"
RELEASE_WEB_VOLUME="yanyu-ws-scrcpy-data"
IMAGE_COMPOSE_FILE="${BASE_DIR}/compose.image.yml"
IMAGE_ENV_FILE="${BASE_DIR}/.android7-image.env"
IMAGE_PROJECT="android7-image"

# Reviewed source lock. Update URLs and expected hashes together, never from a cache.
UBUNTU_IMAGE="ubuntu@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3"
WEB_BASE_IMAGE="bilbospocketses/ws-scrcpy-web:0.1.30-beta.129@sha256:11c60e4ed73e793b2e93d5cdae54c4d7f3b7e3fa7e40aa003fa28120bd5d011b"
UBUNTU_SNAPSHOT="20260922T000000Z"
SYSTEM_IMG_SHA256="30e9d2697348ced76e60715e8f92436f3712b393488f574a9754bba3d2b6eb5b"
RAMDISK_IMG_SHA256="291a33bd1a1afb6f3d03ce227642097fb332a9f844a9c666fb1f7f30d4739e25"
MAGISK_APK_SHA256="f511bd33d3242911d05b0939f910a3133ef2ba0e0ff1e098128f9f3cd0c16610"
ADB_SHA256="a902be8f45c6c62e76c9efaf6947a0fa747c9cabd89a2ac8e0d16ecb30b3ed01"
ARCHIVE_SHA256=(
    af6121aedc1b2682ab198e81c53258e3b090bc7dfaf1e0eb755657e403cdc0fc
    42e9760dd96a4cf74072c3c8a1eec6f6c8b426a42ea3620b9b6a6346d73eafbf
    7053dc5b84d7edb0398124847802eccd56f99110bd1ec71e12435dfa7d94947a
)
SDK_FILES=(
    commandlinetools-linux-15859902_latest.zip
    platform-tools_r37.0.1-linux.zip
    x86_64-25_r01.zip
    emulator-linux_x64-15917651.zip
)
SDK_SHA256=(
    4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
    d230f13842f60f782a8645f9c813f8f845bf36089ea7289f28c48f17979313f1
    746d233fcb2241cc0e599175cb0e909dee6c296c003003af6c8fefa6dea1b185
    95771e0ae431897b2a4bd2d97fa095f29a8b0624a7b216baf529f9306161c266
)
SDK_URLS=(
    "https://dl.google.com/android/repository/${SDK_FILES[0]}"
    "https://dl.google.com/android/repository/${SDK_FILES[1]}"
    "https://dl.google.com/android/repository/sys-img/android/${SDK_FILES[2]}"
    "https://dl.google.com/android/repository/${SDK_FILES[3]}"
)



# ============================================================
# Helpers
# ============================================================

# Print a separator for readable status output.
hr()
{
    printf '%s\n' \
        "============================================================"
}


# Print progress messages, treating arguments as plain text.
info()
{
    printf '\n[INFO] %s\n' "$*"
}


# Print a success message without changing application state.
ok()
{
    printf '[ OK ] %s\n' "$*"
}


# Write a warning to stderr; the caller decides whether to continue.
warn()
{
    printf '[WARN] %s\n' "$*" >&2
}


# Write failure details to stderr; callers must return or exit explicitly.
fail()
{
    printf '[FAIL] %s\n' "$*" >&2
}


# Display a shell-escaped command, execute its original arguments and preserve failures.
run()
{
    printf '\n+ '

    printf '%q ' "$@"

    printf '\n'

    "$@"

    local rc=$?

    if [ "${rc}" -ne 0 ]; then

        fail "command failed: rc=${rc}"

        return "${rc}"

    fi

    return 0
}


# Invoke the selected docker or sudo docker argument array without string evaluation.
docker_cmd()
{
    "${DOCKER_CMD[@]}" "$@"
}


# Run Compose in the project directory with its explicit environment and YAML files.
dc()
{
    (
        cd "${BASE_DIR}" || exit 1

        "${DOCKER_CMD[@]}" compose \
            --env-file "${ENV_FILE}" \
            -f "${COMPOSE_FILE}" \
            "$@"
    )
}


# ============================================================
# Directories
# ============================================================

# Create build, source and Android state directories while retaining existing data.
prepare_dirs()
{
    mkdir -p \
        "${BASE_DIR}" \
        "${PATCHED_DIR}" \
        "${SRC_DIR}" \
        "${DOCKER_DIR}" \
        "${STATE_DIR}"

    return 0
}


# ============================================================
# Docker
# ============================================================

# Check preinstalled Docker/Compose without changing host package repositories.
ensure_docker()
{
    info "Checking Docker"

    if ! command -v docker >/dev/null 2>&1; then

        fail "docker command not found."

        echo
        echo "Install Docker Engine first."

        return 1

    fi

    # Prefer normal non-root Docker access.
    if docker info >/dev/null 2>&1; then

        DOCKER_CMD=(docker)

    else

        warn "Current user cannot access Docker directly."
        warn "Trying sudo docker."

        if sudo docker info >/dev/null 2>&1; then

            DOCKER_CMD=(sudo docker)

        else

            fail "Cannot access Docker daemon."

            return 1

        fi

    fi

    # Image deployment needs Docker Engine only; it does not install Compose.
    if [ "${1:-}" = "--engine-only" ]; then
        return 0
    fi

    if ! docker_cmd compose version >/dev/null 2>&1; then

        fail "Docker Compose is required for building. Install it using your host's package manager first."
        return 1

    fi

    echo
    docker_cmd --version
    docker_cmd compose version

    ok "Docker available"

    return 0
}


# ============================================================
# KVM
# ============================================================

# Check host /dev/kvm and report permissions/GID; Compose explicitly passes the device through.
check_kvm()
{
    info "Checking KVM"

    if [ ! -e /dev/kvm ]; then

        fail "/dev/kvm does not exist."

        return 1

    fi

    echo
    ls -l /dev/kvm

    if [ ! -r /dev/kvm ] ||
       [ ! -w /dev/kvm ]; then

        warn "Current user has no direct rw access to /dev/kvm."
        warn "Docker will receive /dev/kvm explicitly."

    fi

    local gid

    gid="$(
        stat \
            -c '%g' \
            /dev/kvm
    )"

    echo "KVM GID: ${gid}"

    ok "KVM available"

    return 0
}


# ============================================================
# Host tools used only to fetch/extract prebuilt image
# ============================================================

# Check host prerequisites. Host tools are outside the image source lock.
# Installing them explicitly avoids silently downloading from arbitrary host repositories.
ensure_host_tools()
{
    local cmd missing=0
    for cmd in curl 7z sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            fail "Required host tool missing: $cmd"
            missing=1
        fi
    done
    [ "$missing" = 0 ]
}

# Compare bytes with a reviewed SHA256; never bless an existing file by hashing it anew.
verify_sha256()
{
    local file="$1" expected="$2" actual
    if [ ! -f "$file" ]; then fail "Required file missing: $file"; return 1; fi
    actual="$(sha256sum -- "$file")" || return 1
    actual="${actual%% *}"
    if [ "$actual" != "$expected" ]; then
        fail "SHA256 mismatch: $file"
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        echo "Move the rejected file aside before retrying; it will not be silently reused." >&2
        return 1
    fi
}

# Fetch over HTTPS to a unique temporary file, verify, then atomically publish the cache.
# A corrupt cache fails closed; a failed/interrupted download cannot become a valid cache.
download_verified()
{
    local url="$1" file="$2" expected="$3" temporary
    if [ -e "$file" ]; then
        verify_sha256 "$file" "$expected" || return 1
        ok "Verified cache: $(basename "$file")"
        return 0
    fi
    mkdir -p "$(dirname "$file")" || return 1
    temporary="$(mktemp "${file}.part.XXXXXX")" || return 1
    info "Downloading $url"
    if ! curl --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 1800 \
        --retry 5 --retry-delay 2 --output "$temporary" "$url"; then
        rm -f "$temporary"
        return 1
    fi
    if ! verify_sha256 "$temporary" "$expected"; then
        rm -f "$temporary"
        return 1
    fi
    mv -f "$temporary" "$file"
}

# Check all three actual Android payloads, including every cache reuse.
verify_patched_image()
{
    local directory="${1:-${PATCHED_DIR}}"
    verify_sha256 "$directory/system.img" "$SYSTEM_IMG_SHA256" &&
    verify_sha256 "$directory/ramdisk.img" "$RAMDISK_IMG_SHA256" &&
    verify_sha256 "$directory/Magisk-v27.0.apk" "$MAGISK_APK_SHA256"
}

# Use commit-addressed archive URLs and verified parts; validate extraction before promotion.
prepare_patched_image()
{
    ensure_host_tools || return 1
    if [ -e "$PATCHED_SYSTEM" ] || [ -e "$PATCHED_RAMDISK" ] || [ -e "$PATCHED_MAGISK" ]; then
        verify_patched_image || return 1
        ok "Verified existing Houdini/Magisk images"
        return 0
    fi
    local i part temporary
    for i in 0 1 2; do
        printf -v part '%03d' "$((i + 1))"
        download_verified \
            "https://raw.githubusercontent.com/xBZZZZ/android_7.1.1_x86_64_libhoudini_magisk/${IMAGE_COMMIT}/${IMAGE_ARCHIVE}.${part}" \
            "${IMAGE_REPO_DIR}/${IMAGE_ARCHIVE}.${part}" "${ARCHIVE_SHA256[$i]}" || return 1
    done
    temporary="$(mktemp -d "${BASE_DIR}/.patched.XXXXXX")" || return 1
    if ! 7z x -y "-o${temporary}" "${IMAGE_REPO_DIR}/${IMAGE_ARCHIVE}.001" ||
       ! verify_patched_image "$temporary"; then
        rm -rf "$temporary"
        return 1
    fi
    # Only replace an empty preparation directory, never overwrite mounted system files.
    if ! rmdir "$PATCHED_DIR" || ! mv "$temporary" "$PATCHED_DIR"; then
        fail "Could not promote verified images; extraction retained at $temporary"
        return 1
    fi
    ok "Verified pre-patched image ready"
}

# The source code, not a first-run floating tag or an editable cache, chooses Ubuntu.
ensure_base_image_pin()
{
    BASE_IMAGE="$UBUNTU_IMAGE"
    if [ -s "$BASE_IMAGE_FILE" ] && [ "$(cat "$BASE_IMAGE_FILE")" != "$UBUNTU_IMAGE" ]; then
        fail "Cached base image differs from the source lock: $BASE_IMAGE_FILE"
        return 1
    fi
    printf '%s\n' "$BASE_IMAGE" > "$BASE_IMAGE_FILE" || return 1
    ok "Using source-pinned Ubuntu base: $BASE_IMAGE"
}


# ============================================================
# Docker files
# ============================================================

# Generate the Android Dockerfile with OS libraries, SDK, verified Emulator, runtime scripts and Shanghai timezone.
write_dockerfile()
{
    printf 'ARG BASE_IMAGE=%s\nARG WEB_BASE_IMAGE=%s\n' "$UBUNTU_IMAGE" "$WEB_BASE_IMAGE" > "${DOCKER_DIR}/Dockerfile" || return 1
    cat >> "${DOCKER_DIR}/Dockerfile" <<'EOF'
FROM ${WEB_BASE_IMAGE} AS certificates
# Bootstrap HTTPS from Node's bundled Mozilla roots in the pinned image.
RUN node -e "require('fs').writeFileSync('/tmp/ca-certificates.crt', require('tls').rootCertificates.join('\\n') + '\\n')"
FROM ${BASE_IMAGE}

COPY --from=certificates /tmp/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources
COPY ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources

ENV DEBIAN_FRONTEND=noninteractive

ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk

ENV PATH=/opt/android-sdk/platform-tools:/opt/android-sdk/emulator:/opt/android-sdk/cmdline-tools/15859902/bin:${PATH}


# ============================================================
# Linux dependencies
# ============================================================

RUN apt-get -o Acquire::Retries=3 -o Acquire::https::Timeout=60 -o APT::Update::Error-Mode=any update && \
    apt-get install -y --no-install-recommends \
        tzdata \
        ca-certificates \
        curl \
        unzip \
        openjdk-17-jre-headless \
        procps \
        psmisc \
        util-linux \
        libgl1 \
        libnss3 \
        libx11-6 \
        libxcomposite1 \
        libxcursor1 \
        libxi6 \
        libxrandr2 \
        libxdamage1 \
        libxfixes3 \
        libxkbcommon0 \
        libxkbcommon-x11-0 \
        libxkbfile1 \
        libxcb1 \
        libxcb-cursor0 \
        libdbus-1-3 \
        libpulse0 \
        libasound2t64 \
        libfontconfig1 \
        libdrm2 \
        libgbm1 \
        libvulkan1 \
        zlib1g && \
    rm -rf /var/lib/apt/lists/*


# All SDK archives are downloaded and verified by the host, then checked again here.
COPY commandlinetools-linux-15859902_latest.zip platform-tools_r37.0.1-linux.zip x86_64-25_r01.zip emulator-linux_x64-15917651.zip sdk.sha256 /tmp/sdk-archives/
RUN cd /tmp/sdk-archives && sha256sum -c sdk.sha256 && \
    mkdir -p /tmp/cmdline-extract /opt/android-sdk/cmdline-tools/15859902 /opt/android-sdk/system-images/android-25/default && \
    unzip -q commandlinetools-linux-15859902_latest.zip -d /tmp/cmdline-extract && \
    cp -a /tmp/cmdline-extract/cmdline-tools/. /opt/android-sdk/cmdline-tools/15859902/ && \
    unzip -q platform-tools_r37.0.1-linux.zip -d /opt/android-sdk && \
    unzip -q x86_64-25_r01.zip -d /opt/android-sdk/system-images/android-25/default && \
    mv emulator-linux_x64-15917651.zip /tmp/emulator.zip && \
    rm -rf /tmp/cmdline-extract /tmp/sdk-archives

# No SDK Manager metadata refresh or mutable package selection occurs during builds.
RUN grep -Eq '^Pkg.Revision[[:space:]]*=[[:space:]]*37\.0\.1[[:space:]]*$' /opt/android-sdk/platform-tools/source.properties && \
    grep -Eq '^Pkg.Revision[[:space:]]*=[[:space:]]*1[[:space:]]*$' /opt/android-sdk/system-images/android-25/default/x86_64/source.properties && \
    adb version


# ============================================================
# Android Emulator
#
# Pinned:
#   release 37.1.11
#   version 37.1.11.0
#   build 15917651
# ============================================================

ARG EMULATOR_BUILD=15917651

ARG EMULATOR_SHA256=95771e0ae431897b2a4bd2d97fa095f29a8b0624a7b216baf529f9306161c266

# Reuse the already-downloaded, SHA256-pinned Emulator archive
# from the Docker build context instead of downloading it again.

RUN set -eux; \
    echo "${EMULATOR_SHA256}  /tmp/emulator.zip" \
        | sha256sum -c -; \
    unzip \
        -q \
        /tmp/emulator.zip \
        -d /opt/android-sdk; \
    rm -f /tmp/emulator.zip; \
    echo "===== Emulator shared-library check ====="; \
    missing="$( \
        { \
            ldd /opt/android-sdk/emulator/emulator; \
            LD_LIBRARY_PATH=/opt/android-sdk/emulator/lib64:/opt/android-sdk/emulator/lib64/qt/lib \
                ldd /opt/android-sdk/emulator/qemu/linux-x86_64/qemu-system-x86_64; \
            LD_LIBRARY_PATH=/opt/android-sdk/emulator/lib64:/opt/android-sdk/emulator/lib64/qt/lib \
                ldd /opt/android-sdk/emulator/qemu/linux-x86_64/qemu-system-x86_64-headless; \
        } \
            2>/dev/null \
        | grep 'not found' \
        || true \
    )"; \
    if [ -n "${missing}" ]; then \
        echo "${missing}"; \
        echo "ERROR: Android Emulator has missing shared libraries"; \
        exit 1; \
    fi; \
    echo "===== Emulator -version ====="; \
    if ! /opt/android-sdk/emulator/emulator \
        -version \
        > /tmp/emulator-version.txt \
        2>&1; then \
        cat /tmp/emulator-version.txt; \
        echo "ERROR: emulator -version failed"; \
        exit 1; \
    fi; \
    cat /tmp/emulator-version.txt; \
    grep \
        -Fq \
        "Android emulator version 37.1.11.0" \
        /tmp/emulator-version.txt; \
    rm -f /tmp/emulator-version.txt; \
    rm -rf /tmp/android-unknown; \
    echo "Android Emulator 37.1.11.0 verified"

# ============================================================
# Runtime scripts
# ============================================================

COPY entrypoint.sh /opt/android/entrypoint.sh
COPY status.sh     /opt/android/status.sh
COPY adbd-guard.sh /opt/android/adbd-guard.sh

RUN chmod +x \
    /opt/android/entrypoint.sh \
    /opt/android/status.sh \
    /opt/android/adbd-guard.sh


# ============================================================
# Runtime
# ============================================================

ENV HOME=/data/home

ENV ANDROID_AVD_HOME=/data/avd

ENV AVD_NAME=android7-houdini-root

ENV EMULATOR_PORT=5556

ENV ANDROID_SERIAL=emulator-5556

# Bake Shanghai timezone rules into the image, independent of host timezone files.
ENV TZ=Asia/Shanghai
RUN mkdir -p /opt/android && \
    dpkg-query -W -f='${Package}=${Version}\n' > /opt/android/apt-packages.txt && \
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo Asia/Shanghai > /etc/timezone && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/opt/android/entrypoint.sh"]
EOF
}


# ============================================================
# Container entrypoint
# ============================================================

# Generate a root watchdog that checks every second and restores stopped adbd; Magisk launches it at guest boot.
write_adbd_guard()
{
    cat > "${DOCKER_DIR}/adbd-guard.sh" <<'EOF'
#!/system/bin/sh
# Detach the guard from ADB sessions; restore the service without publishing ports.
# Some root apps stop adbd, which disconnects the web display/control service.
# Run independently of ADB; Magisk service.d also starts this on guest reboot.
if [ "${1:-}" != "--worker" ]; then
    /system/bin/setsid /system/bin/sh "$0" --worker </dev/null >/dev/null 2>&1 &
    exit 0
fi

# Use a boot-local /dev lock to prevent duplicate watchdog workers.
# /dev is recreated on boot. Prevent duplicate workers from the installer
# and Magisk without leaving a stale lock across guest reboots.
umask 077
lock=/dev/android7-adbd-guard
mkdir "$lock" 2>/dev/null || exit 0
echo $$ > "$lock/pid"
trap 'rm -f "$lock/pid"; rmdir "$lock"' EXIT
trap 'exit 0' INT TERM
while :; do
    if [ "$(getprop init.svc.adbd)" = stopped ]; then
        /system/bin/start adbd
        /system/bin/log -t Android7AdbdGuard 'Restarted adbd after it was stopped'
    fi
    sleep 1
done
EOF
    chmod +x "${DOCKER_DIR}/adbd-guard.sh"
}


# Patch only the pinned web client's unexpected-disconnect path. Manual close
# still stops the stream; reconnection never opens a new SSH/ADB port.
# Generate the derived web image and retry patch against a pinned upstream; manual closure does not reconnect.
write_web_reconnect()
{
    printf 'FROM %s\n' "$WEB_BASE_IMAGE" > "${DOCKER_DIR}/Dockerfile.web" || return 1
    cat >> "${DOCKER_DIR}/Dockerfile.web" <<'EOF'
LABEL cloudphone.component="web"
COPY pinned-adb /app/seed/adb/adb
COPY adb.sha256 /tmp/adb.sha256
RUN sha256sum -c /tmp/adb.sha256 && chmod 0755 /app/seed/adb/adb && rm /tmp/adb.sha256
COPY web-seed-entrypoint.sh /opt/android/web-seed-entrypoint.sh
RUN chmod 0755 /opt/android/web-seed-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/tini", "-g", "--", "/opt/android/web-seed-entrypoint.sh"]
CMD ["/app/start.sh"]
COPY web-reconnect-patch.cjs /tmp/android7-web-reconnect-patch.cjs
RUN node /tmp/android7-web-reconnect-patch.cjs && rm /tmp/android7-web-reconnect-patch.cjs
COPY android7-auth.cjs android7-setup.html /app/dist/
COPY web-auth-patch.cjs /tmp/android7-web-auth-patch.cjs
RUN node /tmp/android7-web-auth-patch.cjs && rm /tmp/android7-web-auth-patch.cjs
# The pinned web base already includes tzdata; configure both libc and app timezone.
ENV TZ=Asia/Shanghai
RUN test -f /usr/share/zoneinfo/Asia/Shanghai && \
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo Asia/Shanghai > /etc/timezone
# Probe the public login page; protected APIs require cookies even for health checks.
HEALTHCHECK --interval=15s --timeout=5s --start-period=180s --retries=5 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:8000/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
EOF

    cat > "${DOCKER_DIR}/web-seed-entrypoint.sh" <<'EOF'
#!/bin/sh
set -eu
# Seed only missing dependency directories. Existing user-managed data is preserved.
mkdir -p /data/dependencies /data/home /data/logs
for component in adb node scrcpy-server; do
    if [ ! -e "/data/dependencies/$component" ]; then
        cp -aL "/app/seed/$component" "/data/dependencies/$component"
        chown -R 1000:1000 "/data/dependencies/$component"
    fi
done
exec /usr/local/bin/entrypoint.sh "$@"
EOF

    cat > "${DOCKER_DIR}/web-reconnect-patch.cjs" <<'EOF'
const fs = require('node:fs');
const root = '/app/dist/public';
// Require exactly one patch target; fail closed when upstream changes.
function replaceOnce(text, before, after) {
    if (text.split(before).length !== 2) {
        throw new Error('Pinned ws-scrcpy web client changed; refusing an unchecked patch');
    }
    return text.replace(before, after);
}
let modal = fs.readFileSync(`${root}/64.bundle.js`, 'utf8');
modal = replaceOnce(modal, 'class s extends c.a{handle;', 'class s extends c.a{handle;closing=!1;');
modal = replaceOnce(modal, 'onDisconnect:()=>this.close()',
    'onDisconnect:()=>{if(this.closing)return;this.close();window.dispatchEvent(new CustomEvent("android7-stream-disconnected",{detail:{udid:e.udid}}))}');
modal = replaceOnce(modal, 'onBeforeClose(){this.handle?.stop()',
    'onBeforeClose(){this.closing=!0,this.handle?.stop()');
fs.writeFileSync(`${root}/64.bundle.js`, modal);
fs.writeFileSync(`${root}/android7-reconnect.js`, `
(() => {
    let pending;
    // Clear reconnect timers and UI so users can cancel.
    function cancel() {
        if (!pending) return;
        clearTimeout(pending.timer);
        pending.notice.remove();
        pending = undefined;
    }
    document.addEventListener('click', event => {
        if (event.target.closest?.('a.link-stream')) cancel();
    }, true);
    window.addEventListener('android7-stream-disconnected', event => {
        cancel();
        const udid = event.detail?.udid;
        if (typeof udid !== 'string' || !udid) return;
        const notice = document.createElement('div');
        notice.setAttribute('role', 'status');
        notice.style.cssText = 'position:fixed;bottom:20px;left:20px;z-index:99999;background:#263238;color:white;padding:14px;border-radius:8px';
        const message = document.createElement('span');
        message.textContent = 'Device disconnected. Reconnecting... ';
        const button = document.createElement('button');
        button.textContent = 'Cancel';
        button.onclick = cancel;
        notice.append(message, button);
        document.body.append(notice);
        const state = pending = {notice, deadline: Date.now() + 30000};
        // Reopen the stream when its link returns; stop after 30 seconds or cancellation.
        function retry() {
            if (pending !== state) return;
            if (document.querySelector('dialog.connect-modal[open]')) return cancel();
            if (Date.now() > state.deadline) {
                message.textContent = 'Device is still unavailable. Try connecting again later. ';
                button.textContent = 'Close';
                return;
            }
            const row = [...document.querySelectorAll('.device[data-udid]')]
                .find(row => row.dataset.udid === udid);
            const link = row?.querySelector('a.link-stream');
            if (link) {
                cancel();
                link.click();
                return;
            }
            state.timer = setTimeout(retry, 500);
        }
        state.timer = setTimeout(retry, 1500);
    });
})();
`);
let index = fs.readFileSync(`${root}/index.html`, 'utf8');
index = replaceOnce(index, '</body>', '<script src="android7-reconnect.js"></script>\n</body>');
fs.writeFileSync(`${root}/index.html`, index);
EOF
}

# Native session authentication, enabled once for both new and legacy installs.
# Only the original passwordless admin may use the one-time setup endpoint.
# Generate first-visit password setup and auth patches; enable login by default, preserve passwords and reuse upstream hashing/sessions.
write_web_auth()
{
    cat > "${DOCKER_DIR}/web-auth-patch.cjs" <<'EOF'
const fs = require('node:fs');
const file = '/app/dist/index.js';
let source = fs.readFileSync(file, 'utf8');
// Patch the pinned server bundle; abort on an unexpected match count.
function patch(before, after) {
    if (source.split(before).length !== 2) throw new Error('Pinned auth implementation changed; refusing an unchecked patch');
    source = source.replace(before, after);
}
patch('this.instance=new P(r,t)', 'this.instance=new P(r,t),require("./android7-auth.cjs").initialize(this.instance)');
patch('u=new Set(["/api/auth/login",', 'u=new Set(["/api/auth/setup","/api/auth/login",');
patch('const r=this.getDb();if(!p(r))return!1;',
    'const r=this.getDb();if(require("./android7-auth.cjs").serveSetupPage(e,t,r))return!0;if(!p(r))return!1;');
patch('const s=T.TS.getInstance().db;if("POST"===e.method&&"/api/auth/login"===r)',
    'const s=T.TS.getInstance().db;if(await require("./android7-auth.cjs").handleSetup(e,t,s,{readBody:ce,hashPassword:S,createSession:id=>new P(s.sqlite).create(id,Date.now()),sessionCookie:token=>Ae(e,token)}))return!0;if("POST"===e.method&&"/api/auth/login"===r)');
fs.writeFileSync(file, source);
EOF

    cat > "${DOCKER_DIR}/android7-auth.cjs" <<'EOF'
const fs = require('node:fs');
const path = require('node:path');
const INITIALIZED = 'android7AuthInitialized';
const SETUP_REQUIRED = 'android7PasswordSetupRequired';

// Identify only the sole original passwordless admin; never overwrite other users.
function isOriginalPasswordlessAdmin(db) {
    const users = db.users.list();
    return users.length === 1 && users[0].id === 1 && users[0].username === 'admin'
        && users[0].role === 'admin' && !users[0].disabled && users[0].passwordHash === null;
}
// Enable auth transactionally on first migration; subsequent boots preserve user settings.
function initialize(db) {
    if (db.appSettings.get(INITIALIZED) === true) return;
    db.sqlite.exec('BEGIN IMMEDIATE');
    try {
        db.appSettings.set('authEnabled', true);
        db.appSettings.set(SETUP_REQUIRED, isOriginalPasswordlessAdmin(db));
        db.appSettings.set(INITIALIZED, true);
        db.sqlite.exec('COMMIT');
    } catch (error) {
        db.sqlite.exec('ROLLBACK');
        throw error;
    }
}
// Check both the persisted marker and account state to prevent reclaiming an admin.
function needsSetup(db) {
    return db.appSettings.get(SETUP_REQUIRED) === true && isOriginalPasswordlessAdmin(db);
}
// Send uncached JSON responses so setup state cannot become stale in a browser cache.
function json(response, status, data) {
    response.writeHead(status, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'});
    response.end(JSON.stringify(data));
}
// Serve the setup homepage only during initialization; leave other requests to native routes.
function serveSetupPage(request, response, db) {
    const pathname = new URL(request.url || '/', 'http://localhost').pathname;
    if (!['GET', 'HEAD'].includes(request.method) || !['/', '/index.html'].includes(pathname) || !needsSetup(db)) return false;
    response.writeHead(200, {'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store'});
    response.end(request.method === 'HEAD' ? undefined : fs.readFileSync(path.join(__dirname, 'android7-setup.html')));
    return true;
}
// Validate the password and create its hash/session transactionally; only one concurrent setup succeeds.
async function handleSetup(request, response, db, auth) {
    if (new URL(request.url || '/', 'http://localhost').pathname !== '/api/auth/setup') return false;
    if (request.method === 'GET') {
        json(response, 200, {required: needsSetup(db)});
        return true;
    }
    if (request.method !== 'POST') {
        json(response, 405, {error: 'method not allowed'});
        return true;
    }
    if (!needsSetup(db)) {
        json(response, 409, {error: 'password setup already completed'});
        return true;
    }
    // The upstream request wrapper still checks Host, Origin and the CSRF cookie.
    const body = await auth.readBody(request, 4096);
    const password = body.password;
    if (typeof password !== 'string' || password.length < 8 || password.length > 128 || password !== body.confirmPassword) {
        json(response, 400, {error: 'password must be 8-128 characters and confirmation must match'});
        return true;
    }
    db.sqlite.exec('BEGIN IMMEDIATE');
    let token;
    try {
        // Recheck after reading the body and acquiring the transaction: only one
        // concurrent first visitor can claim the original admin account.
        if (!needsSetup(db)) {
            db.sqlite.exec('ROLLBACK');
            json(response, 409, {error: 'password setup already completed'});
            return true;
        }
        db.users.setPasswordHash(1, auth.hashPassword(password));
        db.users.clearLockout(1);
        db.appSettings.set('authEnabled', true);
        db.appSettings.set(SETUP_REQUIRED, false);
        token = auth.createSession(1);
        db.sqlite.exec('COMMIT');
    } catch (error) {
        db.sqlite.exec('ROLLBACK');
        throw error;
    }
    response.setHeader('Set-Cookie', auth.sessionCookie(token));
    json(response, 200, {ok: true});
    return true;
}
module.exports = {initialize, needsSetup, serveSetupPage, handleSetup};
EOF

    cat > "${DOCKER_DIR}/android7-setup.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Set administrator password - Android Cloud Phone</title>
<style>
*{box-sizing:border-box}body{font-family:system-ui,sans-serif;background:#f3f5f8;color:#1d2939;min-height:100vh;margin:0;padding:24px;display:grid;place-items:center}main{background:white;width:min(100%,420px);padding:32px;border:1px solid #dce2ea;border-radius:16px;box-shadow:0 12px 40px #1822300a}h1{font-size:24px;margin:0 0 12px}p{line-height:1.6;color:#536174}label{display:block;margin-top:18px;font-size:14px;font-weight:600}input{width:100%;padding:12px;margin-top:6px;border:1px solid #b8c3d1;border-radius:7px;font:inherit}input:focus{outline:2px solid #2563eb;outline-offset:1px}input[readonly]{background:#f3f5f8;color:#536174}button{margin-top:12px;padding:13px;width:100%;border:0;border-radius:7px;background:#2563eb;color:white;font:inherit;font-weight:600;cursor:pointer}button:disabled{opacity:.6;cursor:wait}#error{color:#b42318;min-height:22px;font-size:14px;margin-top:14px}
</style>
</head>
<body>
<main>
<h1>Set administrator password</h1>
<p>Set an administrator password before first use. Future visits require sign-in.</p>
<form id="setup">
<label for="username">Administrator account</label>
<input id="username" name="username" value="admin" autocomplete="username" readonly>
<label for="password">Password</label>
<input id="password" name="password" type="password" autocomplete="new-password" minlength="8" maxlength="128" placeholder="At least 8 characters" required autofocus>
<label for="confirmPassword">Confirm password</label>
<input id="confirmPassword" name="confirmPassword" type="password" autocomplete="new-password" minlength="8" maxlength="128" required>
<div id="error" role="alert" aria-live="polite"></div>
<button type="submit">Set password and continue</button>
</form>
</main>
<script>
const form=document.getElementById('setup');
const error=document.getElementById('error');
const button=form.querySelector('button');
form.addEventListener('submit',async event=>{
    event.preventDefault();
    const password=document.getElementById('password').value;
    const confirmPassword=document.getElementById('confirmPassword').value;
    error.textContent='';
    if(password!==confirmPassword){error.textContent='Passwords do not match.';return;}
    button.disabled=true;
    try{
        const response=await fetch('/api/auth/setup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password,confirmPassword})});
        if(response.ok){form.reset();location.replace('/');return;}
        error.textContent=response.status===409?'Password is already set. Reload to sign in.':response.status===400?'Use 8-128 characters and matching passwords.':'Setup failed. Reload and retry.';
    }catch{error.textContent='Connection failed. Check your network and retry.';}
    button.disabled=false;
});
</script>
</body>
</html>
EOF
}


# Generate the container entrypoint: configure a 6 GiB AVD, boot the emulator, install the guard and handle shutdown.
write_entrypoint()
{
    cat > "${DOCKER_DIR}/entrypoint.sh" <<'EOF'
#!/usr/bin/env bash

set -u


# ============================================================
# Runtime configuration
# ============================================================

SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"

AVD_NAME="${AVD_NAME:-android7-houdini-root}"

EMULATOR_PORT="${EMULATOR_PORT:-5556}"

ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-${EMULATOR_PORT}}"

# Allocate 6 GiB to the Android guest; reserve additional host RAM for emulator/web overhead.
ANDROID_MEMORY_MB=6144

AVD_HOME="${ANDROID_AVD_HOME:-/data/avd}"

AVD_DIR="${AVD_HOME}/${AVD_NAME}.avd"

AVD_INI="${AVD_HOME}/${AVD_NAME}.ini"

SYSTEM_IMAGE_DIR="${SDK_ROOT}/system-images/android-25/default/x86_64"

PATCHED_SYSTEM="/opt/android-image/system.img"

PATCHED_RAMDISK="/opt/android-image/ramdisk.img"

MAGISK_APK="/opt/android-image/Magisk-v27.0.apk"

LOG_DIR="/data/logs"

LOG_FILE="${LOG_DIR}/emulator.log"

READY_FILE="/data/android.ready"

EMULATOR="${SDK_ROOT}/emulator/emulator"

BOOT_TIMEOUT=360


export ANDROID_SDK_ROOT="${SDK_ROOT}"
export ANDROID_HOME="${SDK_ROOT}"

export ANDROID_AVD_HOME="${AVD_HOME}"

export ANDROID_SERIAL="${ANDROID_SERIAL}"

export PATH="${SDK_ROOT}/platform-tools:${SDK_ROOT}/emulator:${SDK_ROOT}/cmdline-tools/15859902/bin:${PATH}"


# ============================================================
# Helpers
# ============================================================

# Print progress messages, treating arguments as plain text.
info()
{
    printf '\n[INFO] %s\n' "$*"
}


# Print a success message without changing application state.
ok()
{
    printf '[ OK ] %s\n' "$*"
}


# Write failure details to stderr; callers must return or exit explicitly.
fail()
{
    printf '[FAIL] %s\n' "$*" >&2
}


# ============================================================
# Basic validation
# ============================================================

mkdir -p \
    "${HOME}" \
    "${HOME}/.android" \
    "${AVD_HOME}" \
    "${LOG_DIR}" \
    /data/tmp

export TMPDIR=/data/tmp


if [ ! -e /dev/kvm ]; then

    fail "/dev/kvm does not exist inside container."

    exit 1

fi


if [ ! -r /dev/kvm ] ||
   [ ! -w /dev/kvm ]; then

    fail "/dev/kvm exists but is not accessible."

    ls -l /dev/kvm || true

    id || true

    exit 1

fi


for f in \
    "${PATCHED_SYSTEM}" \
    "${PATCHED_RAMDISK}" \
    "${MAGISK_APK}" \
    "${SYSTEM_IMAGE_DIR}/userdata.img"
do

    if [ ! -f "${f}" ]; then

        fail "Required file missing:"
        echo "  ${f}"

        exit 1

    fi

done


# ============================================================
# Create AVD config directly
#
# Official API 25 image supplies:
#
#   kernel
#   userdata template
#   emulator metadata
#
# Prebuilt images supply:
#
#   system.img  -> Android 7.1.1 + Houdini
#   ramdisk.img -> Houdini + Magisk
# ============================================================

# Rewrite AVD hardware configuration and remove stale locks; retain userdata with 4 CPUs, 6 GiB and 720x1280 display.
create_avd()
{
    mkdir -p "${AVD_DIR}"

    cat > "${AVD_INI}" <<AVDINI
avd.ini.encoding=UTF-8
path=${AVD_DIR}
target=android-25
AVDINI

    cat > "${AVD_DIR}/config.ini" <<AVDCONFIG
AvdId=${AVD_NAME}
avd.ini.encoding=UTF-8
avd.ini.displayname=${AVD_NAME}

abi.type=x86_64

hw.cpu.arch=x86_64
hw.cpu.ncore=4

hw.ramSize=${ANDROID_MEMORY_MB}
vm.heapSize=256

disk.dataPartition.size=8G

image.sysdir.1=system-images/android-25/default/x86_64/

tag.id=default
tag.display=Default

hw.keyboard=yes
hw.mainKeys=no

hw.lcd.width=720
hw.lcd.height=1280
hw.lcd.density=320

hw.camera.back=none
hw.camera.front=none

hw.audioInput=no

hw.gpu.enabled=yes
hw.gpu.mode=software

showDeviceFrame=no

fastboot.forceColdBoot=yes
fastboot.forceFastBoot=no
AVDCONFIG

    # Clean only stale runtime locks.
    find "${AVD_DIR}" \
        -maxdepth 2 \
        -name '*.lock' \
        -exec rm -rf {} + \
        2>/dev/null ||
        true
}


create_avd


# ============================================================
# ADB
# ============================================================

adb start-server >/dev/null 2>&1 || true


# ============================================================
# Graceful Docker stop
# ============================================================

EMU_PID=""


# Handle container stop signals, request emulator shutdown, terminate remaining processes and clear readiness.
shutdown()
{
    info "Stopping Android Emulator"

    rm -f "${READY_FILE}"

    adb \
        -s "${ANDROID_SERIAL}" \
        emu kill \
        >/dev/null 2>&1 ||
        true

    sleep 2

    if [ -n "${EMU_PID}" ] &&
       kill -0 "${EMU_PID}" \
           >/dev/null 2>&1
    then

        kill "${EMU_PID}" \
            >/dev/null 2>&1 ||
            true

        sleep 2

    fi

    if [ -n "${EMU_PID}" ] &&
       kill -0 "${EMU_PID}" \
           >/dev/null 2>&1
    then

        kill -9 "${EMU_PID}" \
            >/dev/null 2>&1 ||
            true

    fi
}


trap shutdown TERM INT


# ============================================================
# Start Emulator
# ============================================================

: > "${LOG_FILE}"

info "Starting Android 7.1.1"

echo "AVD:    ${AVD_NAME}"
echo "Serial: ${ANDROID_SERIAL}"
echo "Log:    ${LOG_FILE}"

# API 25's Goldfish DMA driver panics with 6 GiB RAM. Keep GL rendering
# enabled, but use the non-DMA transfer path for this legacy guest kernel.
"${EMULATOR}" \
    -avd "${AVD_NAME}" \
    -port "${EMULATOR_PORT}" \
    -system "${PATCHED_SYSTEM}" \
    -ramdisk "${PATCHED_RAMDISK}" \
    -no-window \
    -no-audio \
    -no-boot-anim \
    -no-snapshot \
    -accel on \
    -gpu swiftshader_indirect \
    -feature -GLDMA \
    -camera-back none \
    -camera-front none \
    -memory "${ANDROID_MEMORY_MB}" \
    >> "${LOG_FILE}" \
    2>&1 &

EMU_PID=$!


sleep 3


if ! kill -0 "${EMU_PID}" \
    >/dev/null 2>&1
then

    fail "Android Emulator exited immediately."

    echo

    tail -n 150 "${LOG_FILE}" || true

    exit 1

fi


# ============================================================
# Wait for ADB
# ============================================================

info "Waiting for ADB"

elapsed=0

while [ "${elapsed}" -lt "${BOOT_TIMEOUT}" ]
do

    if ! kill -0 "${EMU_PID}" \
        >/dev/null 2>&1
    then

        fail "Emulator exited while waiting for ADB."

        tail -n 150 "${LOG_FILE}" || true

        exit 1

    fi

    state="$(
        adb \
            devices \
            2>/dev/null |
        awk \
            -v serial="${ANDROID_SERIAL}" \
            '$1 == serial {print $2}'
    )"

    if [ "${state}" = "device" ]; then

        ok "ADB online"

        break

    fi

    if [ $((elapsed % 10)) -eq 0 ]; then

        echo \
            "[WAIT] adb=${state:-not-visible}, ${elapsed}s"

    fi

    sleep 2

    elapsed=$((elapsed + 2))

done


if [ "${elapsed}" -ge "${BOOT_TIMEOUT}" ]; then

    fail "ADB timeout."

    tail -n 150 "${LOG_FILE}" || true

    exit 1

fi


# ============================================================
# Wait for boot
# ============================================================

info "Waiting for Android boot"

elapsed=0

while [ "${elapsed}" -lt "${BOOT_TIMEOUT}" ]
do

    boot="$(
        adb \
            -s "${ANDROID_SERIAL}" \
            shell \
            getprop \
            sys.boot_completed \
            2>/dev/null |
        tr -d '\r'
    )"

    if [ "${boot}" = "1" ]; then

        ok "Android boot completed"

        break

    fi

    if ! kill -0 "${EMU_PID}" \
        >/dev/null 2>&1
    then

        fail "Emulator exited during Android boot."

        tail -n 150 "${LOG_FILE}" || true

        exit 1

    fi

    if [ $((elapsed % 10)) -eq 0 ]; then

        echo "[WAIT] Android boot ${elapsed}s"

    fi

    sleep 2

    elapsed=$((elapsed + 2))

done


if [ "${elapsed}" -ge "${BOOT_TIMEOUT}" ]; then

    fail "Android boot timeout."

    exit 1

fi


# ============================================================
# Magisk Manager
# ============================================================

# Install the ADB guard via AOSP su before reporting readiness.
# Install before declaring the cloud phone ready. The worker detaches from
# ADB so it can restore adbd even after a root app stops the transport.
info "Installing ADB connection guard"

adb -s "${ANDROID_SERIAL}" push \
    /opt/android/adbd-guard.sh /data/local/tmp/android7-adbd-guard.sh || exit 1

adb -s "${ANDROID_SERIAL}" shell /system/xbin/su 0 sh -c \
    "'mkdir -p /data/adb/service.d &&
      cp /data/local/tmp/android7-adbd-guard.sh /data/adb/service.d/android7-adbd-guard.sh &&
      chmod 0700 /data/adb/service.d/android7-adbd-guard.sh &&
      /system/bin/sh /data/adb/service.d/android7-adbd-guard.sh'" || exit 1

if ! adb \
    -s "${ANDROID_SERIAL}" \
    shell \
    pm path com.topjohnwu.magisk \
    2>/dev/null |
    grep -q '^package:'
then

    info "Installing Magisk Manager"

    adb \
        -s "${ANDROID_SERIAL}" \
        install \
        -r \
        "${MAGISK_APK}" ||
        true

fi


# ============================================================
# Ready
# ============================================================

touch "${READY_FILE}"

echo

/opt/android/status.sh || true

echo
ok "Android 7 cloud phone is running"


# ============================================================
# Tie entrypoint lifetime to the emulator and clear readiness on exit; Docker handles restart.
# Keep PID 1 alive while Emulator is alive
# ============================================================

wait "${EMU_PID}"

rc=$?

rm -f "${READY_FILE}"

echo
fail "Android Emulator exited: rc=${rc}"

exit "${rc}"
EOF

    chmod +x "${DOCKER_DIR}/entrypoint.sh"
}


# ============================================================
# Container status command
# ============================================================

# Generate status/health probes for boot, ADB, ABI, Houdini and root with bounded probe timeouts.
write_status_script()
{
    cat > "${DOCKER_DIR}/status.sh" <<'EOF'
#!/usr/bin/env bash

set -u

SERIAL="${ANDROID_SERIAL:-emulator-5556}"


# Read an Android property with a timeout and strip carriage returns; probes handle empty results.
prop()
{
    timeout -k 1 3 adb \
        -s "${SERIAL}" \
        shell \
        getprop \
        "$1" \
        2>/dev/null |
        tr -d '\r'
}


adb_state="$(
    timeout -k 1 2 adb \
        devices \
        2>/dev/null |
    awk \
        -v serial="${SERIAL}" \
        '$1 == serial {print $2}'
)"


if [ "${1:-}" = "--health" ]; then

    if [ "${adb_state}" != "device" ]; then
        exit 1
    fi

    boot="$(prop sys.boot_completed)"

    if [ "${boot}" != "1" ]; then
        exit 1
    fi

    exit 0
fi


echo "============================================================"
echo "ANDROID 7 CLOUD PHONE"
echo "============================================================"

printf '%-18s %s\n' \
    "ADB:" \
    "${adb_state:-not-visible}"


if [ "${adb_state}" != "device" ]; then
    exit 0
fi


boot="$(prop sys.boot_completed)"
android="$(prop ro.build.version.release)"
sdk="$(prop ro.build.version.sdk)"
abi="$(prop ro.product.cpu.abilist)"
bridge="$(prop ro.dalvik.vm.native.bridge)"


printf '%-18s %s\n' \
    "Boot:" \
    "${boot:-unknown}"

printf '%-18s %s\n' \
    "Android:" \
    "${android:-unknown}"

printf '%-18s %s\n' \
    "API:" \
    "${sdk:-unknown}"

printf '%-18s %s\n' \
    "ABI:" \
    "${abi:-unknown}"

printf '%-18s %s\n' \
    "Native bridge:" \
    "${bridge:-unknown}"


# ============================================================
# Houdini
# ============================================================

houdini32="$(
    adb \
        -s "${SERIAL}" \
        shell \
        /system/lib/arm/houdini \
        --version \
        2>/dev/null |
    tr -d '\r'
)"

houdini64="$(
    adb \
        -s "${SERIAL}" \
        shell \
        /system/lib64/arm64/houdini64 \
        --version \
        2>/dev/null |
    tr -d '\r'
)"


printf '%-18s %s\n' \
    "Houdini32:" \
    "${houdini32:-NOT FOUND}"

printf '%-18s %s\n' \
    "Houdini64:" \
    "${houdini64:-NOT FOUND}"


# ============================================================
# Root
# ============================================================

root_output="$(
    timeout 6 \
        adb \
        -s "${SERIAL}" \
        shell \
        su -c id \
        2>/dev/null |
    tr -d '\r'
)"


if echo "${root_output}" |
    grep -q 'uid=0(root)'
then

    root_state="OK"

else

    root_state="NOT VERIFIED"

    if timeout 6 adb -s "${SERIAL}" shell /system/xbin/su 0 id \
        2>/dev/null | grep -q 'uid=0(root)'; then
        root_state="OK (AOSP su; Magisk not authorized)"
    fi

fi


printf '%-18s %s\n' \
    "Root:" \
    "${root_state}"


# ============================================================
# Overall check
# ============================================================

passed=1

[ "${boot}" = "1" ] ||
    passed=0

[ "${android}" = "7.1.1" ] ||
    passed=0

[ "${sdk}" = "25" ] ||
    passed=0

echo "${bridge}" |
    grep -qi houdini ||
    passed=0

echo "${houdini32}" | grep -q 'Houdini version:' || passed=0
echo "${houdini64}" | grep -q 'Houdini version:' || passed=0
case ",${abi}," in
    *,armeabi-v7a,*) ;;
    *) passed=0 ;;
esac
case ",${abi}," in
    *,arm64-v8a,*) ;;
    *) passed=0 ;;
esac


if [ "${passed}" = "1" ]; then

    echo
    echo "[VERIFY] ANDROID + HOUDINI PASS"

else

    echo
    echo "[VERIFY] CHECK REQUIRED"

fi


echo "============================================================"
EOF

    chmod +x "${DOCKER_DIR}/status.sh"
}


# ============================================================
# Compose file
# ============================================================

# Generate both modes from one topology; only build instructions and storage differ.
write_compose()
{
    local mode="${1:-dev}" destination="$COMPOSE_FILE"
    if [ "$mode" = image ]; then destination="$IMAGE_COMPOSE_FILE"; fi
    {
        cat <<'EOF'
services:
  android7:
    image: "${ANDROID_IMAGE}"
    container_name: "${ANDROID_CONTAINER}"
    devices:
      - /dev/kvm:/dev/kvm
    user: "0:0"
    ports:
      - "127.0.0.1:8000:8000"
    environment:
      TZ: Asia/Shanghai
      HOME: /data/home
      ANDROID_SDK_ROOT: /opt/android-sdk
      ANDROID_HOME: /opt/android-sdk
      ANDROID_AVD_HOME: /data/avd
      AVD_NAME: android7-houdini-root
      EMULATOR_PORT: "5556"
      ANDROID_SERIAL: emulator-5556
    volumes:
      - "${ANDROID_DATA}:/data"
EOF
        if [ "$mode" = dev ]; then
            cat <<'EOF'
      - ./patched:/opt/android-image:ro
      - ./patched/system.img:/opt/android-sdk/system-images/android-25/default/x86_64/system.img:ro
    build:
      context: ./docker
      args:
        BASE_IMAGE: "${BASE_IMAGE}"
EOF
        fi
        cat <<'EOF'
    shm_size: "2gb"
    restart: unless-stopped
    stop_grace_period: 45s
    healthcheck:
      test: ["CMD", "/opt/android/status.sh", "--health"]
      interval: 10s
      timeout: 8s
      retries: 12
      start_period: 180s
  ws-scrcpy-web:
    image: "${WEB_IMAGE}"
    container_name: "${WEB_CONTAINER}"
    network_mode: service:android7
    depends_on:
      android7:
        condition: service_healthy
        restart: true
    environment:
      TZ: Asia/Shanghai
      WS_SCRCPY_ALLOW_REMOTE_ADMIN: "0"
    volumes:
      - "${WEB_DATA}:/data"
    restart: unless-stopped
    stop_grace_period: 30s
EOF
        if [ "$mode" = dev ]; then
            cat <<'EOF'
    build:
      context: ./docker
      dockerfile: Dockerfile.web
EOF
        else
            cat <<'EOF'
volumes:
  android-data:
    name: "${ANDROID_VOLUME}"
  web-data:
    name: "${WEB_VOLUME}"
EOF
        fi
    } > "$destination"
}


# Save image names and host UID/GID metadata; these values do not replace state directory backups.
write_env()
{
    local host_uid
    local host_gid
    local kvm_gid

    host_uid="$(id -u)"
    host_gid="$(id -g)"
    kvm_gid="$(
        stat \
            -c '%g' \
            /dev/kvm
    )"

    cat > "${ENV_FILE}" <<EOF
BASE_IMAGE=${BASE_IMAGE}
RUNTIME_IMAGE=${RUNTIME_IMAGE}
ANDROID_IMAGE=${RUNTIME_IMAGE}
WEB_IMAGE=android7-ws-scrcpy-web:auth-setup-v2
ANDROID_CONTAINER=${CONTAINER_NAME}
WEB_CONTAINER=android7-ws-scrcpy-web
ANDROID_DATA=./docker-state
WEB_DATA=./ws-scrcpy-data

HOST_UID=${host_uid}
HOST_GID=${host_gid}

KVM_GID=${kvm_gid}
EOF
}


# ============================================================
# Runtime files
# ============================================================

# Download only fixed SDK artifacts and generate build-time checksums and snapshot sources.
prepare_docker_runtime()
{
    ensure_base_image_pin || return 1
    local i file
    for i in "${!SDK_FILES[@]}"; do
        file="${SDK_FILES[$i]}"
        download_verified "${SDK_URLS[$i]}" "${BASE_DIR}/downloads/${file}" "${SDK_SHA256[$i]}" || return 1
        cp -f "${BASE_DIR}/downloads/${file}" "${DOCKER_DIR}/${file}" || return 1
    done
    {
        for i in "${!SDK_FILES[@]}"; do printf '%s  %s\n' "${SDK_SHA256[$i]}" "${SDK_FILES[$i]}"; done
    } > "${DOCKER_DIR}/sdk.sha256" || return 1
    printf '%s  %s\n' \
        "$SYSTEM_IMG_SHA256" system.img "$RAMDISK_IMG_SHA256" ramdisk.img "$MAGISK_APK_SHA256" Magisk-v27.0.apk \
        > "${DOCKER_DIR}/patched.sha256" || return 1
    7z x -so "${BASE_DIR}/downloads/${SDK_FILES[1]}" platform-tools/adb > "${DOCKER_DIR}/pinned-adb" || return 1
    verify_sha256 "${DOCKER_DIR}/pinned-adb" "$ADB_SHA256" || return 1
    printf '%s  %s\n' "$ADB_SHA256" /app/seed/adb/adb > "${DOCKER_DIR}/adb.sha256" || return 1
    cat > "${DOCKER_DIR}/ubuntu.sources" <<EOF
Types: deb
URIs: https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/
Suites: noble noble-updates noble-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
Check-Valid-Until: no
By-Hash: no
EOF
    # Historical snapshots expire by design. Signatures and package hashes stay enforced.
    write_dockerfile || return 1
    write_adbd_guard || return 1
    write_web_reconnect || return 1
    write_web_auth || return 1
    write_entrypoint || return 1
    write_status_script || return 1
    write_env || return 1
    write_compose || return 1
}


# ============================================================
# Docker image
# ============================================================

# Build Android and web base images with Docker cache for development or two-image releases.
ensure_runtime_image()
{
    # Re-evaluate generated files; Docker reuses unchanged build layers.
    info "Building Android 7 Docker runtime"

    echo
    echo "SDK archives are already checksum-verified; APT uses the pinned snapshot."
    echo "Docker will cache them for future starts."

    dc build "${SERVICE_NAME}" ws-scrcpy-web ||
        return 1

    ok "Android 7 Docker image built"

    return 0
}


# ============================================================
# Manifest
# ============================================================

# Record image versions, source commit and Android file hashes for audit; the manifest contains no image payload.
write_manifest()
{
    {
        echo "Android 7 Docker Cloud Phone"
        echo "Generated=$(date -Is)"

        echo

        echo "[houdini-magisk]"
        echo "repository=${IMAGE_REPO}"
        echo "commit=${IMAGE_COMMIT}"

        echo

        echo "[docker-base]"
        echo "${BASE_IMAGE}"

        echo

        echo "[runtime-image]"
        echo "${RUNTIME_IMAGE}"

        docker_cmd \
            image inspect \
            "${RUNTIME_IMAGE}" \
            --format \
            'image_id={{.Id}}' \
            2>/dev/null ||
            true

        echo

        echo "[patched-images]"

        sha256sum \
            "${PATCHED_SYSTEM}" \
            "${PATCHED_RAMDISK}" \
            "${PATCHED_MAGISK}" \
            2>/dev/null ||
            true

        echo
        echo "[web-image]"
        echo "android7-ws-scrcpy-web:auth-setup-v2"
        docker_cmd image inspect android7-ws-scrcpy-web:auth-setup-v2 \
            --format 'image_id={{.Id}}' 2>/dev/null || true

        echo
        echo "[source-lock]"
        echo "ubuntu=${UBUNTU_IMAGE}"
        echo "web=${WEB_BASE_IMAGE}"
        echo "apt_snapshot=${UBUNTU_SNAPSHOT}"
        echo "release_android=${RELEASE_IMAGE}"
        echo "release_web=${RELEASE_WEB_IMAGE}"
        local i
        for i in "${!SDK_FILES[@]}"; do echo "${SDK_URLS[$i]} sha256=${SDK_SHA256[$i]}"; done
        cat "${DOCKER_DIR}/patched.sha256"
        echo
        echo "[apt-packages]"
        docker_cmd run --rm --network none --entrypoint cat "$RUNTIME_IMAGE" /opt/android/apt-packages.txt || return 1
        echo
        echo "[runtime-defaults]"
        echo "container_timezone=Asia/Shanghai"
        echo "android_memory_mb=6144"
        echo "emulator_version=37.1.11.0"

    } > "${MANIFEST_FILE}"

    return 0
}


# ============================================================
# Full first-start preparation
# ============================================================

# Prepare normal startup in dependency order and stop on critical failures before launching incomplete images.
prepare_all()
{
    prepare_dirs

    ensure_docker ||
        return 1

    check_kvm ||
        return 1

    prepare_patched_image ||
        return 1

    prepare_docker_runtime ||
        return 1

    ensure_runtime_image ||
        return 1

    write_manifest || return 1

    return 0
}


# ============================================================
# Start
# ============================================================

# Prepare and start both services, retaining data, then display the URL and status.
cmd_start()
{
    prepare_all ||
        return 1

    info "Starting Android 7 Docker cloud phone"

    dc up \
        -d ||
        return 1

    echo
    echo "Container started."
    echo "Web display: http://localhost:8000"
    echo
    echo "Boot progress:"
    echo
    echo "  ./android7.sh log"
    echo
    echo "Status:"
    echo
    echo "  ./android7.sh status"

    echo

    # Wait briefly for container creation only.
    sleep 2

    cmd_status

    return 0
}


# Package only Android system files; the web service remains a separate image.
write_release_files()
{
    cat > "${DOCKER_DIR}/Dockerfile.release" <<'EOF' || return 1
ARG ANDROID_IMAGE=android7-cloudphone:api25-houdini-magisk-v1
FROM ${ANDROID_IMAGE}
LABEL org.opencontainers.image.title="Yan Yu Jiang Hu x86 Android 7" \
      org.opencontainers.image.description="Android runtime for the two-container cloud phone" \
      cloudphone.component="android"
COPY patched/system.img /opt/android-sdk/system-images/android-25/default/x86_64/system.img
COPY patched/ramdisk.img patched/Magisk-v27.0.apk /opt/android-image/
COPY docker/patched.sha256 /opt/android-image/patched.sha256
RUN ln -s /opt/android-sdk/system-images/android-25/default/x86_64/system.img /opt/android-image/system.img && \
    cd /opt/android-image && sha256sum -c patched.sha256
VOLUME ["/data"]
HEALTHCHECK --interval=10s --timeout=8s --start-period=180s --retries=12 \
    CMD ["/opt/android/status.sh", "--health"]
EOF
    cat > "${DOCKER_DIR}/Dockerfile.release.dockerignore" <<'EOF'
**
!docker/
!docker/patched.sha256
!patched/
!patched/system.img
!patched/ramdisk.img
!patched/Magisk-v27.0.apk
EOF
}

# Let Docker validate/reuse stored credentials or open its interactive Hub login flow.
# Use the same docker/sudo docker context for login and pushes; never read credentials.
push_release_images()
{
    local image
    info "Checking Docker Hub sign-in; Docker will reuse valid saved credentials"
    if ! docker_cmd login; then
        fail "Docker Hub login failed or was cancelled. Both built images remain local."
        return 1
    fi
    for image in "$@"; do
        info "Pushing $image to Docker Hub"
        if ! docker_cmd push "$image"; then
            fail "Push failed: $image. Any earlier successful push remains published."
            echo "Local images are retained. Check network access and repository permissions, then retry."
            return 1
        fi
    done
    ok "Both images published to Docker Hub."
}

# Build and publish both release images without starting or copying private runtime state.
cmd_build_image()
{
    local android_image="${1:-$RELEASE_IMAGE}" web_image="${2:-$RELEASE_WEB_IMAGE}"
    local image namespace
    # Normalize Hub aliases and reject other registries before starting a long build.
    android_image="${android_image#docker.io/}"
    android_image="${android_image#index.docker.io/}"
    web_image="${web_image#docker.io/}"
    web_image="${web_image#index.docker.io/}"
    if [[ "$android_image" == *@* || "$web_image" == *@* || "$android_image" = "$web_image" ]]; then
        fail "Build requires two distinct image tags, not digest references."; return 2
    fi
    for image in "$android_image" "$web_image"; do
        namespace="${image%%/*}"
        if [[ "$image" != */* || "$namespace" == *.* || "$namespace" == *:* || "$namespace" = localhost || "${image##*/}" != *:* ]]; then
            fail "Build/push requires Docker Hub tags: USER/REPOSITORY:TAG ($image)"
            return 2
        fi
    done
    prepare_all || return 1
    write_release_files || return 1
    info "Building Android release image: $android_image"
    docker_cmd build --file "${DOCKER_DIR}/Dockerfile.release" \
        --build-arg "ANDROID_IMAGE=${RUNTIME_IMAGE}" --tag "$android_image" "$BASE_DIR" || return 1
    docker_cmd tag android7-ws-scrcpy-web:auth-setup-v2 "$web_image" || return 1
    ok "Both images ready: $android_image and $web_image"
    push_release_images "$android_image" "$web_image" || return 1
    echo "Deploy: ./android7.sh image start $android_image $web_image"
}


# Stop services while retaining containers and both state directories for restart or consistent backup.
cmd_stop()
{
    prepare_dirs

    ensure_docker ||
        return 1

    if [ ! -f "${COMPOSE_FILE}" ]; then

        ok "Android 7 has not been initialized."

        return 0

    fi

    info "Stopping Android 7"

    dc stop

    local rc=$?

    if [ "${rc}" -eq 0 ]; then
        ok "Android 7 stopped"
    fi

    return "${rc}"
}


# ============================================================
# Down
#
# Remove container/network.
# Persistent bind data remains.
# ============================================================

# Remove Compose containers/network while retaining host bind-mounted data and images.
cmd_down()
{
    prepare_dirs

    ensure_docker ||
        return 1

    if [ ! -f "${COMPOSE_FILE}" ]; then

        ok "Android 7 has not been initialized."

        return 0

    fi

    info "Taking Android 7 down"

    dc down \
        --remove-orphans

    local rc=$?

    if [ "${rc}" -eq 0 ]; then

        ok "Android 7 is down"

        echo "Persistent userdata preserved:"
        echo "  ${STATE_DIR}"

    fi

    return "${rc}"
}


# ============================================================
# Restart
# ============================================================

# Restart existing services, falling back to normal start if absent; use start for configuration changes.
cmd_restart()
{
    prepare_dirs

    ensure_docker ||
        return 1

    if ! docker_cmd \
        inspect \
        "${CONTAINER_NAME}" \
        >/dev/null 2>&1
    then

        cmd_start

        return $?

    fi

    info "Restarting Android 7"

    dc restart ||
        return 1

    sleep 2

    cmd_status

    return 0
}


# ============================================================
# Reset
#
# Factory reset Android userdata.
#
# Docker image and downloaded Android image remain.
# ============================================================

# Require YES before deleting Android AVD data and starting again; web accounts are outside the deletion scope.
cmd_reset()
{
    hr

    echo "ANDROID 7 FACTORY RESET"

    hr

    echo
    echo "This deletes Android userdata:"
    echo
    echo "  - installed applications"
    echo "  - application data"
    echo "  - Android settings"
    echo "  - Android accounts/login state"
    echo
    echo "This preserves:"
    echo
    echo "  - Docker runtime image"
    echo "  - Android SDK"
    echo "  - Android Emulator"
    echo "  - Houdini system.img"
    echo "  - Magisk ramdisk.img"
    echo "  - source/download cache"
    echo

    read \
        -r \
        -p "Type YES to continue: " \
        answer

    if [ "${answer}" != "YES" ]; then

        echo "Reset cancelled."

        return 0

    fi

    cmd_down ||
        return 1

    info "Removing persistent Android AVD userdata"

    rm -rf \
        "${STATE_DIR}/avd" \
        "${STATE_DIR}/android.ready"

    mkdir -p "${STATE_DIR}"

    ok "Android userdata cleared"

    echo

    cmd_start
}


# ============================================================
# Logs
# ============================================================

# Follow the latest 200 service log lines; Ctrl+C exits the viewer without stopping the phone.
cmd_log()
{
    prepare_dirs

    ensure_docker ||
        return 1

    if [ ! -f "${COMPOSE_FILE}" ]; then

        echo "Android 7 has not been initialized yet."
        echo
        echo "Run:"
        echo "  ./android7.sh start"

        return 0

    fi

    echo
    echo "Ctrl+C only exits log view."
    echo "It does NOT stop Android."
    echo

    dc logs \
        --tail 200 \
        -f
}


# ============================================================
# Status
# ============================================================

# Show container state, health and Android diagnostics, or explain how to initialize the project.
cmd_status()
{
    prepare_dirs

    ensure_docker ||
        return 1

    hr

    echo "ANDROID 7 DOCKER CLOUD PHONE"

    hr

    printf '%-20s %s\n' \
        "Directory:" \
        "${BASE_DIR}"

    printf '%-20s %s\n' \
        "Container:" \
        "${CONTAINER_NAME}"

    printf '%-20s %s\n' \
        "Persistent state:" \
        "${STATE_DIR}"

    if [ ! -f "${COMPOSE_FILE}" ]; then

        printf '%-20s %s\n' \
            "State:" \
            "NOT INITIALIZED"

        echo
        echo "Run:"
        echo "  ./android7.sh start"

        hr

        return 0

    fi

    local exists=0

    if docker_cmd \
        inspect \
        "${CONTAINER_NAME}" \
        >/dev/null 2>&1
    then

        exists=1

    fi

    if [ "${exists}" = "0" ]; then

        printf '%-20s %s\n' \
            "State:" \
            "DOWN"

        hr

        return 0

    fi

    local state
    local health

    state="$(
        docker_cmd \
            inspect \
            "${CONTAINER_NAME}" \
            --format \
            '{{.State.Status}}' \
            2>/dev/null ||
        true
    )"

    health="$(
        docker_cmd \
            inspect \
            "${CONTAINER_NAME}" \
            --format \
            '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
            2>/dev/null ||
        true
    )"

    printf '%-20s %s\n' \
        "Docker state:" \
        "${state:-unknown}"

    printf '%-20s %s\n' \
        "Health:" \
        "${health:-unknown}"

    if [ "${state}" != "running" ]; then

        echo

        dc ps

        hr

        return 0

    fi

    echo

    docker_cmd \
        exec \
        "${CONTAINER_NAME}" \
        /opt/android/status.sh ||
        true

    return 0
}


# Compose deployment always keeps Android and web in separate containers.
idc()
{
    docker_cmd compose --project-name "$IMAGE_PROJECT" --env-file "$IMAGE_ENV_FILE" \
        --file "$IMAGE_COMPOSE_FILE" "$@"
}

# Persist the selected pair so later start/restart never silently switches image versions.
write_image_config()
{
    local android_image="$1" web_image="$2"
    cat > "$IMAGE_ENV_FILE" <<EOF || return 1
ANDROID_IMAGE=$android_image
WEB_IMAGE=$web_image
ANDROID_CONTAINER=$RELEASE_CONTAINER
WEB_CONTAINER=$RELEASE_WEB_CONTAINER
ANDROID_DATA=android-data
WEB_DATA=web-data
ANDROID_VOLUME=$RELEASE_VOLUME
WEB_VOLUME=$RELEASE_WEB_VOLUME
EOF
    write_compose image
}

# Reject old combined containers instead of treating their nested web state as a fresh account.
check_image_containers()
{
    local target project
    for target in "$RELEASE_CONTAINER" "$RELEASE_WEB_CONTAINER"; do
        if docker_cmd container inspect "$target" >/dev/null 2>&1; then
            project="$(docker_cmd container inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$target")" || return 1
            if [ "$project" != "$IMAGE_PROJECT" ]; then
                fail "$target is not managed by this two-container deployment."
                echo "Preserve its data and migrate it first; see README.en.md."
                return 1
            fi
        fi
    done
}

# Reuse or pull both images, verify component roles, then start the shared Compose topology.
cmd_image_start()
{
    local android_image="${1:-${RELEASE_IMAGE}}"
    local web_image="${2:-${RELEASE_WEB_IMAGE}}"
    local reference expected actual variable tag
    if [ "$#" = 0 ] && [ -f "$IMAGE_ENV_FILE" ]; then
        android_image="$(sed -n 's/^ANDROID_IMAGE=//p' "$IMAGE_ENV_FILE")"
        web_image="$(sed -n 's/^WEB_IMAGE=//p' "$IMAGE_ENV_FILE")"
        # Convert old saved tag@digest references to tags without retaining a pin.
        for variable in android_image web_image; do
            reference="${!variable}"
            if [[ "$reference" == *@* ]]; then
                tag="${reference%%@*}"
                if [[ "${tag##*/}" != *:* ]]; then
                    fail "Saved digest has no tag. Pass both IMAGE:TAG arguments to image start."
                    return 2
                fi
                printf -v "$variable" '%s' "$tag"
                warn "Using saved image tag without its old digest: $tag"
            fi
        done
    fi
    for reference in "$android_image" "$web_image"; do
        if [[ ! "$reference" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/:-]*$ || "$reference" == sha256:* ]]; then
            fail "Use an image tag, not a digest: $reference"; return 2
        fi
    done
    ensure_docker || return 1
    check_kvm || return 1
    check_image_containers || return 1
    for expected in android web; do
        reference="$android_image"
        if [ "$expected" = web ]; then reference="$web_image"; fi
        if ! docker_cmd image inspect "$reference" >/dev/null 2>&1; then
            info "Pulling $reference"
            if ! docker_cmd pull "$reference"; then
                fail "Image is unavailable locally and could not be pulled: $reference"
                echo "For unpublished images, run './android7.sh image build' first."
                echo "For custom builds, pass both built tags to image start."
                return 1
            fi
        else
            ok "Using local image: $reference"
        fi
        actual="$(docker_cmd image inspect --format '{{index .Config.Labels "cloudphone.component"}}' "$reference")" || return 1
        if [ "$actual" != "$expected" ]; then
            fail "$reference is not a two-container $expected image. Build/pull the correct pair."
            return 1
        fi
    done
    write_image_config "$android_image" "$web_image" || return 1
    idc up -d --no-build --pull never || return 1
    ok "Android and web containers started."
    echo "Web: http://127.0.0.1:8000"
}

# Reset only Android AVD state; keep web credentials and the selected image pair.
cmd_image_reset()
{
    local answer='' android_volume web_volume android_image web_image helper users
    if [ ! -f "$IMAGE_ENV_FILE" ] || [ ! -f "$IMAGE_COMPOSE_FILE" ]; then
        fail "No image deployment configuration. Run image start first."; return 1
    fi
    android_volume="$(sed -n 's/^ANDROID_VOLUME=//p' "$IMAGE_ENV_FILE")"
    web_volume="$(sed -n 's/^WEB_VOLUME=//p' "$IMAGE_ENV_FILE")"
    android_image="$(sed -n 's/^ANDROID_IMAGE=//p' "$IMAGE_ENV_FILE")"
    web_image="$(sed -n 's/^WEB_IMAGE=//p' "$IMAGE_ENV_FILE")"
    if [[ ! "$android_volume" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ||
          ! "$web_volume" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ || "$android_volume" = "$web_volume" ]]; then
        fail "Reset requires separate, valid Android and web data volumes."; return 1
    fi
    echo "ANDROID FACTORY RESET (image mode)"
    echo "This deletes installed apps, app data, Android accounts and settings."
    echo "Target: $android_volume (avd/ and android.ready only)"
    echo "Web accounts/passwords, images and other volume contents are preserved."
    echo "Both services will be stopped, then started again."
    if ! read -r -p "Type YES to reset Android: " answer || [ "$answer" != YES ]; then
        echo "Reset cancelled."
        return 0
    fi
    ensure_docker || return 1
    check_kvm || return 1
    check_image_containers || return 1
    # Check prerequisites before stopping anything; reset never builds or publishes.
    docker_cmd volume inspect "$android_volume" "$web_volume" >/dev/null || return 1
    helper="$(docker_cmd image inspect --format '{{.Id}}' "$android_image")" || return 1
    docker_cmd image inspect "$web_image" >/dev/null || return 1
    idc down || return 1
    users="$(docker_cmd ps -aq --filter "volume=$android_volume")" || return 1
    if [ -n "$users" ]; then
        fail "Another container references $android_volume; Android data was not reset."
        return 1
    fi
    docker_cmd run --rm --pull never --network none --user 0:0 --entrypoint /bin/sh \
        --mount "type=volume,src=$android_volume,dst=/reset-data" "$helper" \
        -ec 'rm -rf -- /reset-data/avd /reset-data/android.ready' || return 1
    ok "Android AVD state cleared; web accounts and passwords retained."
    if ! idc up -d --no-build --pull never; then
        fail "Android was reset, but startup failed. Check image log and retry image start."
        return 1
    fi
    ok "Both services started after Android reset."
}

# Permanently remove one deployment's containers and Android/web state after confirmation.
# Keep images and build caches. Never start a replacement phone or touch the other mode.
cmd_purge()
{
    local mode="$1" answer='' target path users helper=''
    local -a containers paths=() volumes=()
    case "$mode" in
        image)
            containers=("$RELEASE_WEB_CONTAINER" "$RELEASE_CONTAINER")
            volumes=("$RELEASE_WEB_VOLUME" "$RELEASE_VOLUME")
            ;;
        dev)
            containers=(android7-ws-scrcpy-web "$CONTAINER_NAME")
            paths=("${BASE_DIR}/docker-state" "${BASE_DIR}/ws-scrcpy-data")
            ;;
        *) fail "Unknown purge mode: $mode"; return 2 ;;
    esac
    echo "PERMANENTLY DELETE ${mode} deployment data"
    echo "This removes Android apps, accounts, settings, files and web accounts/passwords."
    printf 'Containers: %s\n' "${containers[*]}"
    if [ "$mode" = image ]; then
        printf 'Data volume: %s\n' "${volumes[@]}"
    else
        printf 'Data directory: %s\n' "${paths[@]}"
    fi
    echo "Images and build/download caches are retained. The phone will stay stopped."
    if ! read -r -p "Type YES to permanently delete this data: " answer || [ "$answer" != YES ]; then
        echo "Purge cancelled."
        return 0
    fi
    ensure_docker --engine-only || return 1

    # A local project image supplies root permissions for root-owned development files.
    # Reject redirected directories and do not download anything just to delete data.
    for path in "${paths[@]}"; do
        if [ -L "$path" ] || { [ -e "$path" ] && [ ! -d "$path" ]; }; then
            fail "Refusing an unexpected data path: $path"; return 1
        fi
        if [ -d "$path" ] && [ -z "$helper" ]; then
            for target in "$RUNTIME_IMAGE" android7-ws-scrcpy-web:auth-setup-v2; do
                if docker_cmd image inspect "$target" >/dev/null 2>&1; then helper="$target"; break; fi
            done
            if [ -z "$helper" ]; then
                fail "A local Android or web runtime image is required to clear development data."
                return 1
            fi
        fi
    done
    # Stop gracefully before removal; abort on failures so live state is not deleted.
    for target in "${containers[@]}"; do
        if docker_cmd container inspect "$target" >/dev/null 2>&1; then
            docker_cmd stop "$target" || return 1
            docker_cmd rm "$target" || return 1
        fi
    done
    if [ "$mode" = image ]; then
        for target in "${volumes[@]}"; do
            users="$(docker_cmd ps -aq --filter "volume=$target")" || return 1
            if [ -n "$users" ]; then fail "Another container references $target; volumes retained."; return 1; fi
        done
        for target in "${volumes[@]}"; do
            if docker_cmd volume inspect "$target" >/dev/null 2>&1; then
                docker_cmd volume rm "$target" || return 1
            fi
        done
    else
        # Check both paths before deleting either, including references by stopped containers.
        for path in "${paths[@]}"; do
            users="$(docker_cmd ps -aq --filter "volume=$path")" || return 1
            if [ -n "$users" ]; then
                fail "Another container still references $path; data was not cleared."
                return 1
            fi
        done
        for path in "${paths[@]}"; do
            [ -d "$path" ] || continue
            docker_cmd run --rm --network none --user 0:0 --entrypoint /bin/sh \
                --mount "type=bind,src=$path,dst=/purge-data" "$helper" \
                -ec 'find /purge-data -mindepth 1 -maxdepth 1 -exec rm -rf --one-file-system -- {} +' || return 1
        done
    fi
    ok "${mode} containers and all Android/web runtime data removed."
    echo "The next start creates a fresh phone and requires a new administrator password."
}

# Dispatch image operations. Both modes require Compose; deployment never builds sources.
cmd_image()
{
    local action="${1:-help}"
    if [ "$#" -gt 0 ]; then shift; fi
    if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then cmd_help image; return; fi
    case "$action" in
        help|-h|--help) cmd_help image ;;
        pull|start|build)
            if [ "$#" != 0 ] && [ "$#" != 2 ]; then
                fail "Provide both ANDROID_IMAGE and WEB_IMAGE, or neither."; return 2
            fi
            if [ "$action" = build ]; then cmd_build_image "$@"; else cmd_image_start "$@"; fi
            ;;
        reset|purge)
            if [ "$#" != 0 ]; then fail "$action takes no extra arguments."; return 2; fi
            if [ "$action" = reset ]; then cmd_image_reset; else cmd_purge image; fi
            ;;
        stop|restart|down|log|status)
            if [ "$#" != 0 ]; then fail "$action takes no image arguments."; return 2; fi
            ensure_docker || return 1
            check_image_containers || return 1
            if [ ! -f "$IMAGE_ENV_FILE" ] || [ ! -f "$IMAGE_COMPOSE_FILE" ]; then
                fail "No image deployment configuration. Run image start first."; return 1
            fi
            case "$action" in
                stop) idc stop ;;
                restart) idc restart ;;
                down) idc down ;;
                log) idc logs --tail 100 -f ;;
                status) idc ps -a ;;
            esac
            ;;
        *) fail "Unknown image command: $action"; cmd_help image; return 2 ;;
    esac
}

# Dispatch the original two-container source-development workflow.
cmd_dev()
{
    if [ "$#" -gt 1 ]; then
        if [[ "${2:-}" == -h || "${2:-}" == --help ]]; then cmd_help dev; return; fi
        fail "Development commands take no extra arguments."; return 2
    fi
    case "${1:-help}" in
        start) cmd_start ;;
        stop) cmd_stop ;;
        restart) cmd_restart ;;
        down) cmd_down ;;
        reset) cmd_reset ;;
        purge) cmd_purge dev ;;
        log) cmd_log ;;
        status) cmd_status ;;
        help|-h|--help) cmd_help dev ;;
        *) fail "Unknown development command: ${1}"; cmd_help dev; return 2 ;;
    esac
}

# Show concise top-level help or details for a single command group.
cmd_help()
{
    case "${1:-}" in
        '')
            cat <<EOF_HELP
Yan Yu Jiang Hu - Android 7 Cloud Phone

Usage: ./android7.sh <group> <command> [options]

Quick start:
  ./android7.sh image pull       Reuse a local image, or pull it, then start

Command groups:
  image                         Deploy or build the Android + web image pair
  dev                           Build and manage the source development stack
  help [image|dev]               Show this page or detailed group help

Examples:
  ./android7.sh image pull
  ./android7.sh image status
  ./android7.sh image build
  ./android7.sh help image
  ./android7.sh dev start

Defaults:
  Android:   ${RELEASE_IMAGE}
  Web image: ${RELEASE_WEB_IMAGE}
  Containers: ${RELEASE_CONTAINER} + ${RELEASE_WEB_CONTAINER}
  Data:      ${RELEASE_VOLUME} + ${RELEASE_WEB_VOLUME}
  Web:       http://127.0.0.1:8000
  Android:   7.1.1 x86_64, 6 GiB RAM, KVM
  Timezone:  Asia/Shanghai
  Sign-in:   Set the admin password on first visit

Requirements: Linux x86_64, Docker Engine, Compose and /dev/kvm.
EOF_HELP
            ;;
        image)
            cat <<EOF_HELP
Usage: ./android7.sh image <command> [ANDROID_IMAGE WEB_IMAGE]
Provide both IMAGE:TAG arguments or neither. Deployment uses tags only.

Commands:
  pull/start        Reuse or pull both images, then start two containers
  build             Build both images, sign in to Docker Hub if needed, then push both
  stop              Stop both containers; retain all data
  restart           Restart both containers
  down              Remove both containers/network; retain both data volumes
  reset             After YES, reset Android and restart both services; keep web accounts
  purge             After YES, remove both containers and DELETE Android/web data
  log               Follow logs from both services
  status            Show both services and their health
  help              Show this page

Default images:
  $RELEASE_IMAGE
  $RELEASE_WEB_IMAGE
Containers: $RELEASE_CONTAINER + $RELEASE_WEB_CONTAINER
Volumes:    $RELEASE_VOLUME + $RELEASE_WEB_VOLUME

Examples:
  ./android7.sh image build
  ./android7.sh image start
  ./android7.sh image start myrepo/phone:android myrepo/phone:web

Build targets must be Docker Hub USER/REPOSITORY:TAG names you can push to.
Docker reuses saved credentials or prompts for login. Build does not start containers.
Defaults reuse local tags; missing images are pulled only after publication.
A rebuild may change the output digest even when dependency sources are pinned.
Selected references are saved in .android7-image.env and reused by later starts.
Release-image digests are not pinned. Downloaded build inputs remain hash-checked.
To update, pull both new images and pass both references to image start.
The old combined 1.0 image is not supported. Preserve/migrate its data first.
See README.en.md for manual Docker commands and OVERVIEW.en.md for the pipeline.
EOF_HELP
            ;;
        dev)
            cat <<EOF_HELP
Usage: ./android7.sh dev <command>

Commands:
  start      Prepare sources, build and start the two development containers
  stop       Stop development services, keeping containers and state
  restart    Restart existing services; initialize them if not yet created
  down       Remove development containers/network, keeping state and images
  reset      Delete Android AVD apps/accounts/settings after typing YES;
             web accounts and passwords are preserved
  purge      Stop/remove both containers and DELETE all Android/web data;
             requires YES; keep images/build caches; do not restart
  log        Follow development logs
  status     Show Android, ADB, root and container diagnostics
  help       Show this page

Containers: android7-cloudphone + android7-ws-scrcpy-web
State:      ${STATE_DIR} and ${BASE_DIR}/ws-scrcpy-data
Web:        http://127.0.0.1:8000

Do not run development and image deployments on the same host port.
Generated Docker/Compose files are overwritten by the next dev start/build.
Edit android7.sh instead. Original flat commands remain aliases for dev commands.
EOF_HELP
            ;;
        *) fail "Unknown help topic: $1"; return 2 ;;
    esac
}

# Dispatch explicit image/dev groups; keep the original flat development aliases.
main()
{
    local command="${1:-help}"
    if [ "$#" -gt 0 ]; then shift; fi
    case "$command" in
        image) cmd_image "$@" ;;
        dev) cmd_dev "$@" ;;
        help|-h|--help) cmd_help "${1:-}" ;;
        build-image) cmd_image build "$@" ;;
        start|stop|restart|down|reset|purge|log|status) cmd_dev "$command" "$@" ;;
        *) fail "Unknown command: ${command}"; cmd_help; return 2 ;;
    esac
}

# Direct execution dispatches commands; sourcing exposes functions for validation.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
