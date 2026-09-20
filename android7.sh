#!/usr/bin/env bash

# ============================================================
# Android 7 Cloud Phone - Docker Edition
#
# Android 7.1.1 / API 25 / x86_64
# Houdini ARM32 + ARM64
# Magisk 27 root
# Android Emulator + KVM
#
# Commands:
#
#   ./android7.sh start
#   ./android7.sh stop
#   ./android7.sh restart
#   ./android7.sh reset
#   ./android7.sh down
#   ./android7.sh log
#   ./android7.sh status
#   ./android7.sh help
#
# First "start":
#   - verifies Docker + KVM
#   - reuses/downloads pre-patched Houdini/Magisk image
#   - generates Docker runtime files
#   - pins Ubuntu base image to a digest
#   - builds Android Emulator image
#   - starts Android
#
# No "set -e":
# errors remain visible.
# ============================================================

set -u


# ============================================================
# Paths
# ============================================================

BASE_DIR="${HOME}/android7"

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


# ============================================================
# Helpers
# ============================================================

hr()
{
    printf '%s\n' \
        "============================================================"
}


info()
{
    printf '\n[INFO] %s\n' "$*"
}


ok()
{
    printf '[ OK ] %s\n' "$*"
}


warn()
{
    printf '[WARN] %s\n' "$*" >&2
}


fail()
{
    printf '[FAIL] %s\n' "$*" >&2
}


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


docker_cmd()
{
    "${DOCKER_CMD[@]}" "$@"
}


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

    if ! docker_cmd compose version >/dev/null 2>&1; then

        info "Installing Docker Compose plugin"

        sudo apt-get update || return 1

        sudo apt-get install -y \
            docker-compose-plugin ||
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

ensure_host_tools()
{
    local missing=0

    for cmd in git 7z sha256sum
    do

        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing=1
        fi

    done

    if [ "${missing}" = "0" ]; then
        return 0
    fi

    info "Installing image preparation tools"

    sudo apt-get update || return 1

    sudo apt-get install -y \
        git \
        p7zip-full \
        coreutils ||
        return 1

    return 0
}


# ============================================================
# Existing pre-patched Android image
# ============================================================

prepare_patched_image()
{
    ensure_host_tools ||
        return 1

    # --------------------------------------------------------
    # If we already have the extracted image AND the source
    # repository is pinned to the expected commit, reuse it.
    # --------------------------------------------------------

    if [ -f "${PATCHED_SYSTEM}" ] &&
       [ -f "${PATCHED_RAMDISK}" ] &&
       [ -f "${PATCHED_MAGISK}" ] &&
       [ -d "${IMAGE_REPO_DIR}/.git" ]
    then

        local current=""

        current="$(
            git \
                -C "${IMAGE_REPO_DIR}" \
                rev-parse HEAD \
                2>/dev/null ||
            true
        )"

        if [ "${current}" = "${IMAGE_COMMIT}" ]; then

            ok "Existing Houdini/Magisk image reused"

            return 0

        fi

    fi

    info "Preparing pre-patched Android 7 Houdini/Magisk image"

    if [ ! -d "${IMAGE_REPO_DIR}/.git" ]; then

        rm -rf "${IMAGE_REPO_DIR}"

        run git clone \
            "${IMAGE_REPO}" \
            "${IMAGE_REPO_DIR}" ||
            return 1

    fi

    run git \
        -C "${IMAGE_REPO_DIR}" \
        fetch \
        origin \
        "${IMAGE_COMMIT}" ||
        return 1

    run git \
        -C "${IMAGE_REPO_DIR}" \
        checkout \
        --detach \
        "${IMAGE_COMMIT}" ||
        return 1

    local current

    current="$(
        git \
            -C "${IMAGE_REPO_DIR}" \
            rev-parse HEAD
    )"

    if [ "${current}" != "${IMAGE_COMMIT}" ]; then

        fail "Image repository commit mismatch."

        return 1

    fi

    for part in 001 002 003
    do

        if [ ! -f \
            "${IMAGE_REPO_DIR}/${IMAGE_ARCHIVE}.${part}" ]
        then

            fail "Missing archive volume:"
            echo \
                "${IMAGE_REPO_DIR}/${IMAGE_ARCHIVE}.${part}"

            return 1

        fi

    done

    run 7z t \
        "${IMAGE_REPO_DIR}/${IMAGE_ARCHIVE}.001" ||
        return 1

    rm -rf "${PATCHED_DIR}"

    mkdir -p "${PATCHED_DIR}"

    run 7z x \
        -y \
        "-o${PATCHED_DIR}" \
        "${IMAGE_REPO_DIR}/${IMAGE_ARCHIVE}.001" ||
        return 1

    for f in \
        system.img \
        ramdisk.img \
        Magisk-v27.0.apk
    do

        if [ ! -f "${PATCHED_DIR}/${f}" ]; then

            fail "Missing extracted file:"
            echo "  ${PATCHED_DIR}/${f}"

            return 1

        fi

    done

    ok "Pre-patched image ready"

    return 0
}


# ============================================================
# Pin Docker base image
# ============================================================

ensure_base_image_pin()
{
    if [ -s "${BASE_IMAGE_FILE}" ]; then

        BASE_IMAGE="$(
            cat "${BASE_IMAGE_FILE}"
        )"

        ok "Docker base already pinned:"
        echo "  ${BASE_IMAGE}"

        return 0

    fi

    info "Pinning Ubuntu 24.04 Docker base image"

    run docker_cmd pull ubuntu:24.04 ||
        return 1

    local digest

    digest="$(
        docker_cmd \
            image inspect \
            ubuntu:24.04 \
            --format \
            '{{index .RepoDigests 0}}'
    )"

    if [ -z "${digest}" ] ||
       ! echo "${digest}" |
       grep -q '@sha256:'
    then

        fail "Unable to resolve Ubuntu image digest."

        return 1

    fi

    printf '%s\n' "${digest}" \
        > "${BASE_IMAGE_FILE}"

    BASE_IMAGE="${digest}"

    ok "Ubuntu base pinned:"
    echo "  ${BASE_IMAGE}"

    return 0
}


# ============================================================
# Docker files
# ============================================================

write_dockerfile()
{
    cat > "${DOCKER_DIR}/Dockerfile" <<'EOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk

ENV PATH=/opt/android-sdk/platform-tools:/opt/android-sdk/emulator:/opt/android-sdk/cmdline-tools/15859902/bin:${PATH}


# ============================================================
# Linux dependencies
# ============================================================

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
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


# ============================================================
# Android Command-line Tools
#
# Pinned:
#   build 15859902
# ============================================================

ARG CMDLINE_BUILD=15859902

ARG CMDLINE_SHA256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583

RUN set -eux; \
    url="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_BUILD}_latest.zip"; \
    curl \
        --fail \
        --location \
        --retry 5 \
        --output /tmp/cmdline.zip \
        "${url}"; \
    echo "${CMDLINE_SHA256}  /tmp/cmdline.zip" \
        | sha256sum -c -; \
    mkdir -p /tmp/cmdline-extract; \
    unzip \
        -q \
        /tmp/cmdline.zip \
        -d /tmp/cmdline-extract; \
    mkdir -p \
        "/opt/android-sdk/cmdline-tools/${CMDLINE_BUILD}"; \
    cp -a \
        /tmp/cmdline-extract/cmdline-tools/. \
        "/opt/android-sdk/cmdline-tools/${CMDLINE_BUILD}/"; \
    rm -rf \
        /tmp/cmdline.zip \
        /tmp/cmdline-extract


# ============================================================
# SDK packages
#
# API 25 x86_64:
#   revision 1
#
# Platform-Tools:
#   require 37.0.1
# ============================================================

RUN set -eux; \
    yes \
        | sdkmanager \
            --sdk_root=/opt/android-sdk \
            --licenses \
            >/dev/null 2>&1 \
        || true; \
    sdkmanager \
        --sdk_root=/opt/android-sdk \
        "platform-tools" \
        "system-images;android-25;default;x86_64"; \
    platform_rev="$( \
        sed -n \
            's/^Pkg\.Revision[[:space:]]*=[[:space:]]*//p' \
            /opt/android-sdk/platform-tools/source.properties \
        | head -n1 \
        | tr -d '\r' \
    )"; \
    system_rev="$( \
        sed -n \
            's/^Pkg\.Revision[[:space:]]*=[[:space:]]*//p' \
            /opt/android-sdk/system-images/android-25/default/x86_64/source.properties \
        | head -n1 \
        | tr -d '\r' \
    )"; \
    echo "Platform-Tools revision: ${platform_rev}"; \
    echo "API25 image revision:    ${system_rev}"; \
    test "${platform_rev}" = "37.0.1"; \
    test "${system_rev}" = "1"; \
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
COPY emulator-linux_x64-15917651.zip /tmp/emulator.zip

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

RUN chmod +x \
    /opt/android/entrypoint.sh \
    /opt/android/status.sh


# ============================================================
# Runtime
# ============================================================

ENV HOME=/data/home

ENV ANDROID_AVD_HOME=/data/avd

ENV AVD_NAME=android7-houdini-root

ENV EMULATOR_PORT=5556

ENV ANDROID_SERIAL=emulator-5556

ENTRYPOINT ["/opt/android/entrypoint.sh"]
EOF
}


# ============================================================
# Container entrypoint
# ============================================================

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

info()
{
    printf '\n[INFO] %s\n' "$*"
}


ok()
{
    printf '[ OK ] %s\n' "$*"
}


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

hw.ramSize=3072
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
    -camera-back none \
    -camera-front none \
    -memory 3072 \
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

write_status_script()
{
    cat > "${DOCKER_DIR}/status.sh" <<'EOF'
#!/usr/bin/env bash

set -u

SERIAL="${ANDROID_SERIAL:-emulator-5556}"


prop()
{
    adb \
        -s "${SERIAL}" \
        shell \
        getprop \
        "$1" \
        2>/dev/null |
        tr -d '\r'
}


adb_state="$(
    adb \
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

write_compose()
{
    cat > "${COMPOSE_FILE}" <<'EOF'
services:

  android7:

    build:
      context: ./docker

      args:
        BASE_IMAGE: "${BASE_IMAGE}"

    image: "${RUNTIME_IMAGE}"

    container_name: android7-cloudphone

    devices:
      - /dev/kvm:/dev/kvm

    user: "0:0"

    ports:
      - "127.0.0.1:8000:8000"

    environment:

      HOME: /data/home

      ANDROID_SDK_ROOT: /opt/android-sdk
      ANDROID_HOME: /opt/android-sdk

      ANDROID_AVD_HOME: /data/avd

      AVD_NAME: android7-houdini-root

      EMULATOR_PORT: "5556"

      ANDROID_SERIAL: emulator-5556

    volumes:

      - ./patched:/opt/android-image:ro

      # This Emulator also reads system.img directly from the SDK directory.
      - ./patched/system.img:/opt/android-sdk/system-images/android-25/default/x86_64/system.img:ro

      - ./docker-state:/data

    shm_size: "2gb"

    restart: unless-stopped

    stop_grace_period: 30s

    healthcheck:

      test:
        [
          "CMD",
          "/opt/android/status.sh",
          "--health"
        ]

      interval: 10s

      timeout: 8s

      retries: 12

      start_period: 90s

  ws-scrcpy-web:
    image: bilbospocketses/ws-scrcpy-web:0.1.30-beta.129@sha256:11c60e4ed73e793b2e93d5cdae54c4d7f3b7e3fa7e40aa003fa28120bd5d011b
    container_name: android7-ws-scrcpy-web
    network_mode: service:android7
    depends_on:
      android7:
        condition: service_healthy
        restart: true
    environment:
      WS_SCRCPY_ALLOW_REMOTE_ADMIN: "1"
    volumes:
      - ./ws-scrcpy-data:/data
    restart: unless-stopped
    stop_grace_period: 30s
EOF
}


# ============================================================
# Environment
# ============================================================

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

HOST_UID=${host_uid}
HOST_GID=${host_gid}

KVM_GID=${kvm_gid}
EOF
}


# ============================================================
# Runtime files
# ============================================================

prepare_docker_runtime()
{
    ensure_base_image_pin ||
        return 1

    # --------------------------------------------------------
    # Reuse the Emulator ZIP already downloaded by the
    # previous native setup.
    #
    # This prevents Docker from downloading another 318 MB
    # every time an Emulator build layer fails.
    # --------------------------------------------------------

    local emulator_cache="${BASE_DIR}/downloads/emulator-linux_x64-15917651.zip"
    local emulator_context="${DOCKER_DIR}/emulator-linux_x64-15917651.zip"
    local emulator_sha="95771e0ae431897b2a4bd2d97fa095f29a8b0624a7b216baf529f9306161c266"

    if [ ! -f "${emulator_cache}" ]; then

        info "Downloading pinned Android Emulator archive"

        mkdir -p "${BASE_DIR}/downloads"

        run curl \
            --fail \
            --location \
            --retry 5 \
            --retry-delay 2 \
            --output "${emulator_cache}" \
            "https://dl.google.com/android/repository/emulator-linux_x64-15917651.zip" ||
            return 1

    fi

    local actual_sha

    actual_sha="$(
        sha256sum "${emulator_cache}" |
        awk '{print $1}'
    )"

    if [ "${actual_sha}" != "${emulator_sha}" ]; then

        fail "Cached Android Emulator SHA256 mismatch"

        echo "File:"
        echo "  ${emulator_cache}"

        echo "Expected:"
        echo "  ${emulator_sha}"

        echo "Actual:"
        echo "  ${actual_sha}"

        return 1

    fi

    ok "Reusing cached Android Emulator archive"

    cp -f \
        "${emulator_cache}" \
        "${emulator_context}" ||
        return 1

    write_dockerfile
    write_entrypoint
    write_status_script

    write_env
    write_compose

    return 0
}


# ============================================================
# Docker image
# ============================================================

ensure_runtime_image()
{
    # Re-evaluate generated files; Docker reuses unchanged build layers.
    info "Building Android 7 Docker runtime"

    echo
    echo "The first build downloads Android SDK components."
    echo "Docker will cache them for future starts."

    dc build "${SERVICE_NAME}" ||
        return 1

    ok "Android 7 Docker image built"

    return 0
}


# ============================================================
# Manifest
# ============================================================

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

    } > "${MANIFEST_FILE}"

    return 0
}


# ============================================================
# Full first-start preparation
# ============================================================

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

    write_manifest

    return 0
}


# ============================================================
# Start
# ============================================================

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


# ============================================================
# Stop
#
# Keep container + userdata.
# ============================================================

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


# ============================================================
# Help
# ============================================================

cmd_help()
{
    cat <<'EOF'

Android 7 Docker Cloud Phone
============================

Usage:

    ./android7.sh start
    ./android7.sh stop
    ./android7.sh restart
    ./android7.sh reset
    ./android7.sh down
    ./android7.sh log
    ./android7.sh status
    ./android7.sh help


start
-----

Start the Android 7 cloud phone.

The first start automatically:

    1. checks Docker
    2. checks /dev/kvm
    3. reuses or downloads the existing Houdini/Magisk image
    4. pins Ubuntu Docker image to a digest
    5. generates Dockerfile and compose.yml
    6. builds the Android runtime
    7. starts Android 7.1.1

Normal userdata is persistent.


stop
----

Gracefully stop the existing container.

Container remains.

Android userdata remains.


restart
-------

Restart the existing Android container.

Android userdata remains.


down
----

Stop and remove the container and Compose network.

Android userdata remains.

This is stronger than "stop".


reset
-----

Factory-reset Android userdata.

Deletes:

    installed apps
    app data
    Android settings
    accounts/login state

Preserves:

    Docker image
    Android SDK
    Emulator
    Houdini
    Magisk image
    downloaded sources


log
---

Follow Docker + Emulator logs.

Ctrl+C exits log view only.


status
------

Show:

    Docker state
    container health
    ADB state
    boot state
    Android version
    API level
    ABI list
    native bridge
    Houdini ARM32
    Houdini ARM64
    root status


help
----

Show this page.


Architecture
------------

Ubuntu host
    |
    +-- /dev/kvm
    |
    +-- Docker
          |
          +-- Android Emulator
                |
                +-- Android 7.1.1 x86_64
                +-- Houdini ARM32
                +-- Houdini ARM64
                +-- Magisk
                +-- persistent userdata


Important directories
---------------------

Prebuilt patched image:

    ~/android7/patched

Persistent Docker Android data:

    ~/android7/docker-state

Generated Docker runtime:

    ~/android7/docker

Compose file:

    ~/android7/compose.android7.yml

Reproducibility manifest:

    ~/android7/docker-manifest.txt

EOF

    return 0
}


# ============================================================
# Main
# ============================================================

main()
{
    local command="${1:-help}"

    case "${command}" in

        start)

            cmd_start
            ;;

        stop)

            cmd_stop
            ;;

        restart)

            cmd_restart
            ;;

        reset)

            cmd_reset
            ;;

        down)

            cmd_down
            ;;

        log)

            cmd_log
            ;;

        status)

            cmd_status
            ;;

        help|-h|--help)

            cmd_help
            ;;

        *)

            fail "Unknown command: ${command}"

            echo

            cmd_help

            return 2
            ;;

    esac
}


main "$@"
