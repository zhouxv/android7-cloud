#!/usr/bin/env bash
# Read-only preflight for one Android 7 cloud phone. No downloads or containers.
# KVM_CREATE_VM creates an empty, temporary VM and closes it immediately.
set -u
export LC_ALL=C

usage() {
    cat <<'EOF'
Usage: ./check-host.sh [--disk-path DIRECTORY] [--port PORT]

  --disk-path DIR     Also check this existing data/project directory (default: script directory).
  --port PORT         Check only this web port (default: check both 8000 and 8001).
  -h, --help          Show help.

Required: Linux x86_64, working local rootful Docker, Compose v2+, working KVM.
Recommended for ONE phone: 4 logical CPUs, 12 GiB total RAM, 8 GiB available RAM,
30 GiB free disk; allow 60 GiB when also downloading sources and building images.
Always checks the complete toolset: Python 3, curl, 7z, sha256sum and Buildx.
Uses cached sudo access when needed, without prompting. For a complete check:
  sudo ./check-host.sh

Exit codes: 0 = required checks passed (review WARN lines), 1 = blocked or
incomplete checks, 2 = invalid arguments. This is not a game performance test.
EOF
}

disk_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1
ports=(8000 8001)
while (($#)); do
    case "$1" in
        --disk-path|--port)
            (($# >= 2)) || { usage >&2; exit 2; }
            case "$1" in --disk-path) disk_path=$2 ;; --port) ports=("$2") ;; esac
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done
[[ -d $disk_path ]] || { usage >&2; exit 2; }
for port in "${ports[@]}"; do
    [[ $port =~ ^[0-9]{1,5}$ ]] && ((10#$port >= 1 && 10#$port <= 65535)) || { usage >&2; exit 2; }
done
failures=0 warnings=0
pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failures=$((failures + 1)); }
printf 'Android 7 host check | complete dependencies | ports=%s\n\n' "${ports[*]}"
if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
    fail 'Requires Linux x86_64 with hardware virtualization.'; exit 1
fi
pass 'Linux x86_64'
for tool in timeout awk df nproc; do
    command -v "$tool" >/dev/null || { fail "Missing $tool; run install-deps.sh."; exit 1; }
done

# Resource recommendations are advisory; current free resources change with load.
cpus=$(nproc)
if ((cpus >= 4)); then pass "$cpus logical CPUs"; else warn "$cpus logical CPUs; recommend at least 4."; fi
mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
if ((mem_total >= 12 * 1024 * 1024)); then pass "RAM: $((mem_total / 1024)) MiB total";
else warn "RAM: $((mem_total / 1024)) MiB total; recommend 12 GiB (guest alone uses 6 GiB)."; fi
if ((mem_available >= 8 * 1024 * 1024)); then pass "RAM: $((mem_available / 1024)) MiB available";
else warn "RAM: $((mem_available / 1024)) MiB available; recommend 8 GiB free before starting another phone."; fi
if command -v systemd-detect-virt >/dev/null; then
    virtualization=$(systemd-detect-virt 2>/dev/null || true)
    printf '[INFO] Virtualization: %s (VM hosts must expose nested KVM)\n' "${virtualization:-unknown}"
fi

check_disk() {
    local path=$1 available required=30
    available=$(df -Pk -- "$path" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ ! $available =~ ^[0-9]+$ ]] && command -v sudo >/dev/null; then
        available=$(sudo -n df -Pk -- "$path" 2>/dev/null | awk 'NR==2 {print $4}')
    fi
    if [[ ! $available =~ ^[0-9]+$ ]]; then
        fail "Cannot measure disk space at $path; rerun with sudo."
    elif ((available >= required * 1024 * 1024)); then
        pass "Disk $path: $((available / 1024 / 1024)) GiB free"
    else
        warn "Disk $path: $((available / 1024 / 1024)) GiB free; recommend $required GiB."
    fi
}
check_disk "$disk_path"
printf '[INFO] Allow 60 GiB free disk when also downloading sources and building images.\n'

# Never start Docker or change contexts. Reject remote/Desktop/rootless daemons:
# local /dev/kvm and bind mounts would not describe those daemon environments.
docker_cmd=(docker)
docker_ready=0
# Resolve contexts from local CLI configuration before contacting any daemon.
docker_endpoint() {
    local context
    context=$(timeout 5 "${docker_cmd[@]}" context show 2>/dev/null) || return 1
    if [[ ${docker_cmd[0]} == docker && -z ${DOCKER_CONTEXT:-} && -n ${DOCKER_HOST:-} ]]; then
        printf '%s\n' "$DOCKER_HOST"
    else
        timeout 5 "${docker_cmd[@]}" context inspect "$context" --format '{{.Endpoints.docker.Host}}' 2>/dev/null
    fi
}
if ! command -v docker >/dev/null; then
    fail 'Docker is missing; run install-deps.sh.'
else
    endpoint=$(docker_endpoint)
    if [[ $endpoint != unix://* ]]; then
        fail "Docker endpoint ${endpoint:-unknown} is not a local Unix socket. Select the local Engine."
    elif timeout 15 docker info >/dev/null 2>&1; then docker_ready=1
    else
        if command -v sudo >/dev/null; then
            docker_cmd=(sudo -n docker)
            endpoint=$(docker_endpoint)
            if [[ $endpoint == unix://* ]] && timeout 15 "${docker_cmd[@]}" info >/dev/null 2>&1; then
                docker_ready=1
                printf '[INFO] Docker requires sudo for this user.\n'
            fi
        fi
        ((docker_ready)) || fail 'Docker is stopped or inaccessible; try sudo ./check-host.sh or start Docker.'
    fi
fi
if ((docker_ready)); then
    if server=$(timeout 15 "${docker_cmd[@]}" info --format '{{.OSType}}|{{.Architecture}}|{{.OperatingSystem}}|{{json .SecurityOptions}}' 2>/dev/null); then
        if [[ $server != linux\|x86_64\|* && $server != linux\|amd64\|* ]] || [[ $server == *rootless* || $server == *'Docker Desktop'* ]]; then
            fail "Requires local rootful Linux x86_64 Docker Engine; found: $server"
        else
            pass 'Local rootful Docker Engine responds'
            docker_root=$(timeout 15 "${docker_cmd[@]}" info --format '{{.DockerRootDir}}' 2>/dev/null)
            if [[ $docker_root == /* ]]; then check_disk "$docker_root"; else fail 'Cannot determine Docker data directory.'; fi
            printf '[INFO] A separate containerd image-store filesystem also needs room for images.\n'
        fi
    else fail 'Unable to inspect Docker server.'; fi
    compose=$(timeout 15 "${docker_cmd[@]}" compose version --short 2>/dev/null)
    if [[ $compose =~ ^v?([0-9]+)\. ]] && ((${BASH_REMATCH[1]} >= 2)); then pass "Compose $compose";
    else fail 'Docker Compose plugin v2+ is missing or unusable.'; fi
    if timeout 15 "${docker_cmd[@]}" buildx version >/dev/null 2>&1; then pass 'Docker Buildx'; else fail 'Docker Buildx is missing.'; fi
fi

# Check the actual KVM ioctl, not just CPU flags or a device-node pathname.
if [[ ! -c /dev/kvm ]]; then
    fail 'No /dev/kvm character device. Enable VT-x/AMD-V in BIOS or nested virtualization at your provider.'
elif ! command -v python3 >/dev/null; then
    fail 'Python 3 is missing; cannot verify KVM. Run install-deps.sh.'
else
    probe=(python3)
    if [[ ! -r /dev/kvm || ! -w /dev/kvm ]] && command -v sudo >/dev/null; then probe=(sudo -n python3); fi
    if kvm_result=$(timeout 10 "${probe[@]}" - <<'PY' 2>&1
import fcntl
import os
import sys
try:
    fd = os.open('/dev/kvm', os.O_RDWR | os.O_CLOEXEC)
    try:
        api = fcntl.ioctl(fd, 0xAE00, 0)  # KVM_GET_API_VERSION
        if api != 12:
            raise RuntimeError(f'Unsupported KVM API {api}')
        vm = fcntl.ioctl(fd, 0xAE01, 0)  # KVM_CREATE_VM; no vCPU or RAM
        os.close(vm)
    finally:
        os.close(fd)
except (OSError, RuntimeError) as exc:
    print(exc)
    sys.exit(1)
PY
    ); then pass 'KVM API 12: temporary VM creation succeeded'
    else fail "KVM probe failed: ${kvm_result:-timeout}. Retry with sudo; check host virtualization permissions/settings."; fi
fi
for tool in curl 7z sha256sum; do
    if command -v "$tool" >/dev/null; then pass "Build tool: $tool"; else fail "Missing build tool: $tool; run install-deps.sh."; fi
done
if command -v ss >/dev/null; then
    for port in "${ports[@]}"; do
        port=$((10#$port))
        if listeners=$(ss -H -ltn "sport = :$port" 2>/dev/null); then
            if [[ -n $listeners ]]; then warn "TCP port $port is in use (possibly this phone). Resolve conflicts before a new deployment.";
            else pass "No TCP listener on port $port"; fi
        else warn "Cannot inspect port $port."; fi
    done
else warn 'ss is missing; port availability was not checked.'; fi
printf '\nResult: %s required checks failed; %s warnings.\n' "$failures" "$warnings"
printf 'No network/download, HTTPS, browser, game compatibility or performance tests were performed.\n'
if ((failures)); then
    printf 'NOT READY: resolve FAIL lines and rerun.\n'; exit 1
fi
printf 'Required checks passed. Review warnings before deployment.\n'
