#!/usr/bin/env bash
# Install host dependencies only; never create cloud-phone containers or data.
# Docker packages come from its signed official APT repository. Other host tools
# use the distribution's configured signed repositories, outside the image lock.
set -euo pipefail
export LC_ALL=C

usage() {
    cat <<'EOF'
Usage: sudo ./install-deps.sh [--dry-run]

  --dry-run   Print the plan without sudo, downloads or system changes.
  -h, --help  Show help.

Supported: Ubuntu 22.04/24.04/26.04, Debian 12/13, x86_64, systemd.
Installs missing Docker Engine, Compose and Buildx plus Python 3/KVM check tools.
Always includes curl, 7z and SHA256 tools for both deployment and image builds.
Installs missing packages; APT may update dependencies to satisfy them. Never
automatically removes conflicting packages. Enables/starts the local Docker
service; the script does not explicitly restart an active service.
Tries to load the CPU's KVM module if /dev/kvm is missing. BIOS and provider-side
nested virtualization must be enabled separately. No user/group, firewall,
tunnel, Docker daemon configuration or cloud-phone data changes are made.
EOF
}
dry_run=0
while (($#)); do
    case "$1" in
        --dry-run) dry_run=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || die 'Requires Linux x86_64.'
[[ -r /etc/os-release ]] || die 'Cannot identify this distribution.'
# This is the OS-provided release file, not project/user configuration.
. /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
    ubuntu:22.04|ubuntu:24.04|ubuntu:26.04|debian:12|debian:13) ;;
    *) die "Unsupported distribution: ${PRETTY_NAME:-unknown}. Install Docker using its official distribution instructions." ;;
esac
[[ ${VERSION_CODENAME:-} =~ ^[a-z]+$ ]] || die 'Missing/invalid distribution codename.'
[[ -d /run/systemd/system ]] && command -v systemctl >/dev/null || die 'Requires a host running systemd.'

# Always administer the host Engine; inherited remote contexts must not redirect
# dependency checks or final verification to a different machine.
docker_local() { docker --host unix:///var/run/docker.sock "$@"; }
unset DOCKER_HOST DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
packages=(ca-certificates curl gnupg python3 coreutils util-linux iproute2 kmod p7zip-full)
docker_needed=0
compose_version=$(docker_local compose version --short 2>/dev/null || true)
if ! command -v dockerd >/dev/null || ! command -v docker >/dev/null ||
   [[ ! $compose_version =~ ^v?([0-9]+)\. ]] || ((${BASH_REMATCH[1]:-0} < 2)) ||
   ! docker_local buildx version >/dev/null 2>&1; then
    docker_needed=1
fi
installed() { [[ $(dpkg-query -W -f='${Status}' "$1" 2>/dev/null) == 'install ok installed' ]]; }
if ((docker_needed)); then
    for package in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
        if installed "$package"; then
            die "Conflicting package: $package. Complete your existing Docker installation or review migration to Docker CE manually; nothing was removed."
        fi
    done
    if command -v docker >/dev/null && ! installed docker-ce-cli; then
        die 'Existing Docker CLI is not managed by Docker CE packages. Review it manually before installing another Engine.'
    fi
    packages+=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
fi
printf '[INFO] Target: %s (amd64)\n' "$PRETTY_NAME"
printf '[INFO] Install missing packages (APT may update dependencies): %s\n' "${packages[*]}"
if ((docker_needed)); then printf '[INFO] Use signed repository: https://download.docker.com/linux/%s %s stable\n' "$ID" "$VERSION_CODENAME";
else printf '[INFO] Existing Docker, Compose and Buildx found; keep their installation.\n'; fi
printf '[INFO] Enable/start Docker; probe/load KVM if needed. No phone will be started.\n'
if ((dry_run)); then printf '[INFO] Preview only; no changes made.\n'; exit 0; fi
((EUID == 0)) || die 'Run with sudo, or use --dry-run to preview without changes.'

# Install only missing packages; --no-remove rejects dependency resolutions that
# would remove existing software. No full-system upgrade or autoremove is used.
install_missing() {
    local package
    local missing=()
    for package in "$@"; do installed "$package" || missing+=("$package"); done
    if ((${#missing[@]})); then apt-get install -y --no-remove --no-install-recommends "${missing[@]}"; fi
}
apt-get update
install_missing ca-certificates curl gnupg
if ((docker_needed)); then
    # Reuse an administrator's existing official repository without overwriting
    # its signed-by key or adding a duplicate entry for the same suite.
    if grep -qsE '^[^#]*https://download\.docker\.com/linux/' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; then
        printf '[INFO] Reusing existing Docker APT repository configuration.\n'
    else
        task_tmp=$(mktemp -d)
        trap 'rm -rf -- "$task_tmp"' EXIT
        curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
            --connect-timeout 20 --max-time 120 --retry 3 \
            "https://download.docker.com/linux/$ID/gpg" -o "$task_tmp/docker.asc"
        mkdir -m 700 "$task_tmp/gnupg"
        fingerprint=$(gpg --homedir "$task_tmp/gnupg" --batch --show-keys --with-colons "$task_tmp/docker.asc" | awk -F: '$1=="fpr" && !seen++ {print $10}')
        [[ $fingerprint == 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 ]] || die 'Docker signing-key fingerprint mismatch; review an official key rotation before proceeding.'
        key_file=/etc/apt/keyrings/android7-docker.asc
        source_file=/etc/apt/sources.list.d/android7-docker.sources
        [[ ! -e $key_file && ! -L $key_file && ! -e $source_file && ! -L $source_file ]] || die 'Existing android7-docker APT files need manual review; refusing to overwrite.'
        install -d -m 0755 /etc/apt/keyrings
        install -m 0644 "$task_tmp/docker.asc" "$key_file"
        cat > "$source_file" <<EOF
Types: deb
URIs: https://download.docker.com/linux/$ID
Suites: $VERSION_CODENAME
Components: stable
Architectures: amd64
Signed-By: $key_file
EOF
        chmod 0644 "$source_file"
    fi
    apt-get update
fi
install_missing "${packages[@]}"
systemctl enable docker
systemctl start docker
# timeout cannot invoke a Bash function; explicitly target the host socket.
timeout 30 docker --host unix:///var/run/docker.sock info >/dev/null || die 'Docker installed but the local daemon is not ready. Inspect: journalctl -u docker'
docker_local compose version
docker_local buildx version
if [[ ! -c /dev/kvm ]]; then
    if grep -qw GenuineIntel /proc/cpuinfo; then kvm_module=kvm_intel
    elif grep -qw AuthenticAMD /proc/cpuinfo; then kvm_module=kvm_amd
    else kvm_module=kvm; fi
    if ! modprobe "$kvm_module"; then printf '[WARN] Could not load %s; check kernel support and virtualization settings.\n' "$kvm_module"; fi
fi
if [[ ! -c /dev/kvm ]]; then
    die 'Dependencies installed, but /dev/kvm is still missing. Enable BIOS/nested virtualization, then rerun check-host.sh.'
fi
printf '\n[OK] Dependencies installed. Run: sudo ./check-host.sh\n'
printf '[INFO] Docker group membership was not changed; android7.sh can use sudo when needed.\n'
