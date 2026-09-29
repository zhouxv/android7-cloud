#!/usr/bin/env bash
# Download the published Android/web image pair. No builds or container actions.
# Keep this standalone: do not source android7.sh or its saved configuration.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./android7-image.sh [ANDROID_IMAGE WEB_IMAGE]

Pull both remote images for linux/amd64, even when the tags exist locally.
Docker reuses unchanged layers. No containers are created, started or restarted.
No builds, pushes, volumes, Compose files or project settings are created.

Defaults:
  blueobsidian/android7-magisk-yanyujianghu:1.1-android
  blueobsidian/android7-magisk-yanyujianghu:1.1-web

Examples:
  ./android7-image.sh
  sudo ./android7-image.sh
  ./android7-image.sh myrepo/phone:1.2-android myrepo/phone:1.2-web

Requires access to Docker Engine and the remote registry. No KVM or Compose
required for downloading. For private images, run docker login first using
the same user as this script. A failed pull returns a nonzero exit code;
images already downloaded are retained. Running containers are not updated.
EOF
}

case $# in
    0)
        images=(
            blueobsidian/android7-magisk-yanyujianghu:1.1-android
            blueobsidian/android7-magisk-yanyujianghu:1.1-web
        ) ;;
    1)
        case "$1" in -h|--help) usage; exit 0 ;; esac
        usage >&2; exit 2 ;;
    2) images=("$1" "$2") ;;
    *) usage >&2; exit 2 ;;
esac

# Reject options and whitespace; Docker validates the full image-reference syntax.
for ref in "${images[@]}"; do
    if [[ -z $ref || $ref == -* || $ref =~ [[:space:]] ]]; then
        printf '[FAIL] Invalid image reference: %s\n' "$ref" >&2
        exit 2
    fi
done
command -v docker >/dev/null || { printf '[FAIL] Docker is not installed.\n' >&2; exit 1; }
if ! docker info >/dev/null 2>&1; then
    printf '[FAIL] Cannot access Docker. Check the daemon/context or rerun with sudo if permissions require it.\n' >&2
    exit 1
fi

for ref in "${images[@]}"; do
    printf '\n[INFO] Pulling remote image: %s\n' "$ref"
    if ! docker pull --platform linux/amd64 "$ref"; then
        printf '[FAIL] Pull failed: %s. Check the tag, network and registry login. Already downloaded images are retained.\n' "$ref" >&2
        exit 1
    fi
done
printf '\n[OK] Both images pulled. No containers were created or started.\n'
