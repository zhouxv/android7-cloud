#!/usr/bin/env bash
# Standalone manager for the published Android + web image pair.
# No source builds, publishing, migrations, or dependency on android7.sh.
# Critical operations propagate errors explicitly; passwords travel via stdin.
set -u

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1
IMAGE_ENV_FILE="$BASE_DIR/.android7-image.env"
IMAGE_COMPOSE_FILE="$BASE_DIR/compose.image.yml"
IMAGE_PROJECT=android7-image
RELEASE_IMAGE=blueobsidian/android7-magisk-yanyujianghu:1.1-android
RELEASE_WEB_IMAGE=blueobsidian/android7-magisk-yanyujianghu:1.1-web
RELEASE_CONTAINER=yanyu-android7
RELEASE_WEB_CONTAINER=yanyu-ws-scrcpy-web
RELEASE_VOLUME=yanyu-android7-data
RELEASE_WEB_VOLUME=yanyu-ws-scrcpy-data
DEFAULT_WEB_PORT=8000
DOCKER_CMD=()
WEB_ACCESS_REQUEST=''
WEB_PORT_REQUEST=''

info() { printf '\n[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[FAIL] %s\n' "$*" >&2; }
docker_cmd() { "${DOCKER_CMD[@]}" "$@"; }
idc() {
    docker_cmd compose --project-name "$IMAGE_PROJECT" --env-file "$IMAGE_ENV_FILE" \
        --file "$IMAGE_COMPOSE_FILE" "$@"
}

# Match the main script's Docker privilege selection without changing groups.
ensure_docker() {
    command -v docker >/dev/null || { fail 'Docker is missing. Run install-deps.sh first.'; return 1; }
    if docker info >/dev/null 2>&1; then DOCKER_CMD=(docker)
    elif command -v sudo >/dev/null && sudo docker info >/dev/null 2>&1; then DOCKER_CMD=(sudo docker)
    else fail 'Cannot access Docker. Check the daemon, context and permissions.'; return 1; fi
    if [[ ${1:-} != --engine-only ]] && ! docker_cmd compose version >/dev/null 2>&1; then
        fail 'Docker Compose is required. Run install-deps.sh first.'; return 1
    fi
}

check_kvm() {
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { fail 'Requires Linux x86_64.'; return 1; }
    [[ -c /dev/kvm ]] || { fail 'KVM is missing. Run check-host.sh and enable hardware/nested virtualization.'; return 1; }
}

# Accept one decimal TCP port; reject ambiguous or out-of-range input before Docker runs.
valid_web_port() { [[ $1 =~ ^[1-9][0-9]{0,4}$ ]] && (( $1 <= 65535 )); }

valid_image() {
    [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9._/:-]*$ && $1 != sha256:* ]]
}
valid_volume() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; }

# Read only known scalar settings, never source/eval configuration as shell code.
# Keep the same filenames, names and volumes as android7.sh image deployments.
load_config() {
    ANDROID_IMAGE=$RELEASE_IMAGE WEB_IMAGE=$RELEASE_WEB_IMAGE
    WEB_ACCESS_MODE=public WEB_PORT=$DEFAULT_WEB_PORT
    [[ -f $IMAGE_ENV_FILE ]] || return 0
    local key value tag
    local -A seen=()
    while IFS='=' read -r key value || [[ -n $key ]]; do
        [[ -n $key && $key != \#* ]] || continue
        if [[ -n ${seen[$key]:-} ]]; then fail "Duplicate configuration key: $key"; return 1; fi
        seen[$key]=1
        case "$key" in
            ANDROID_IMAGE) ANDROID_IMAGE=$value ;;
            WEB_IMAGE) WEB_IMAGE=$value ;;
            ANDROID_VOLUME) valid_volume "$value" || return 1; RELEASE_VOLUME=$value ;;
            WEB_VOLUME) valid_volume "$value" || return 1; RELEASE_WEB_VOLUME=$value ;;
            WEB_ACCESS_MODE) WEB_ACCESS_MODE=$value ;;
            ANDROID_CONTAINER) [[ $value == "$RELEASE_CONTAINER" ]] || { fail 'Unexpected Android container name in configuration.'; return 1; } ;;
            WEB_CONTAINER) [[ $value == "$RELEASE_WEB_CONTAINER" ]] || { fail 'Unexpected web container name in configuration.'; return 1; } ;;
            ANDROID_DATA) [[ $value == android-data ]] || return 1 ;;
            WEB_DATA) [[ $value == web-data ]] || return 1 ;;
            WEB_BIND_IP) [[ $value == 0.0.0.0 || $value == 127.0.0.1 ]] || return 1 ;;
            WEB_PORT) valid_web_port "$value" || { fail 'Invalid saved web port (use 1-65535).'; return 1; }; WEB_PORT=$value ;;
            *) fail "Unknown configuration key: $key"; return 1 ;;
        esac
    done < "$IMAGE_ENV_FILE"
    for key in ANDROID_IMAGE WEB_IMAGE ANDROID_VOLUME WEB_VOLUME; do
        [[ -n ${seen[$key]:-} ]] || { fail "Missing configuration key: $key"; return 1; }
    done
    for key in ANDROID_IMAGE WEB_IMAGE; do
        value=${!key}
        if [[ $value == *@* ]]; then
            tag=${value%%@*}
            [[ ${tag##*/} == *:* ]] || { fail 'Saved digest has no tag. Restore both IMAGE:TAG settings.'; return 1; }
            printf -v "$key" '%s' "$tag"
            warn "Using saved tag without its old digest: $tag"
        fi
        valid_image "${!key}" || { fail "Invalid saved image tag: ${!key}"; return 1; }
    done
    [[ $RELEASE_VOLUME != "$RELEASE_WEB_VOLUME" ]] || { fail 'Android and web volumes must be different.'; return 1; }
    [[ $WEB_ACCESS_MODE == public || $WEB_ACCESS_MODE == safe ]] || { fail 'Invalid saved access mode.'; return 1; }
}

require_config() {
    [[ -f $IMAGE_ENV_FILE && -f $IMAGE_COMPOSE_FILE ]] || {
        fail 'No saved deployment. Run ./android7-image.sh start first.'; return 1;
    }
}
check_pending() {
    if [[ -e $BASE_DIR/.android7-migration-image.pending ]]; then
        fail 'An incomplete copy from another tool blocks startup/reset. Inspect the data before continuing.'
        return 1
    fi
}

# Refuse to adopt manual, legacy or unrelated containers. The original image
# deployment is recognized when this script is placed in the same directory.
check_containers() {
    local target project config volume expected
    for target in "$RELEASE_CONTAINER" "$RELEASE_WEB_CONTAINER"; do
        if docker_cmd container inspect "$target" >/dev/null 2>&1; then
            project=$(docker_cmd container inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$target") || return 1
            config=$(docker_cmd container inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$target") || return 1
            expected=$RELEASE_VOLUME
            [[ $target != "$RELEASE_WEB_CONTAINER" ]] || expected=$RELEASE_WEB_VOLUME
            volume=$(docker_cmd container inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$target") || return 1
            if [[ $project != "$IMAGE_PROJECT" || $config != "$IMAGE_COMPOSE_FILE" || $volume != "$expected" ]]; then
                fail "$target belongs to a different/manual deployment or uses different data."
                echo 'Use its original manager, or stop/remove its containers while retaining its volumes before adopting it. See README.'
                return 1
            fi
        fi
    done
}

# Check all external references before destructive operations, including stopped
# containers; Docker also refuses volume deletion if a concurrent user appears.
check_volume_users() {
    local volume users target
    for volume in "$@"; do
        users=$(docker_cmd ps -a --filter "volume=$volume" --format '{{.Names}}') || return 1
        while IFS= read -r target; do
            [[ -z $target || $target == "$RELEASE_CONTAINER" || $target == "$RELEASE_WEB_CONTAINER" ]] && continue
            fail "Another container references $volume: $target. Data was not deleted."
            return 1
        done <<< "$users"
    done
}

# Same two-service topology, default public access and storage as the main script.
# Generate deployment configuration only; there are no build directives.
write_config() {
    WEB_ACCESS_MODE=${WEB_ACCESS_REQUEST:-$WEB_ACCESS_MODE}
    WEB_PORT=${WEB_PORT_REQUEST:-$WEB_PORT}
    WEB_BIND_IP=0.0.0.0
    [[ $WEB_ACCESS_MODE != safe ]] || WEB_BIND_IP=127.0.0.1
    local temporary
    temporary=$(mktemp "$BASE_DIR/.image-env.XXXXXX") || return 1
    if ! cat > "$temporary" <<EOF
ANDROID_IMAGE=$ANDROID_IMAGE
WEB_IMAGE=$WEB_IMAGE
ANDROID_CONTAINER=$RELEASE_CONTAINER
WEB_CONTAINER=$RELEASE_WEB_CONTAINER
ANDROID_DATA=android-data
WEB_DATA=web-data
ANDROID_VOLUME=$RELEASE_VOLUME
WEB_VOLUME=$RELEASE_WEB_VOLUME
WEB_ACCESS_MODE=$WEB_ACCESS_MODE
WEB_BIND_IP=$WEB_BIND_IP
WEB_PORT=$WEB_PORT
EOF
    then rm -f "$temporary"; return 1; fi
    mv -f "$temporary" "$IMAGE_ENV_FILE" || { rm -f "$temporary"; return 1; }
    temporary=$(mktemp "$BASE_DIR/.image-compose.XXXXXX") || return 1
    if ! cat > "$temporary" <<'EOF'
services:
  android7:
    image: "${ANDROID_IMAGE}"
    container_name: "${ANDROID_CONTAINER}"
    devices:
      - /dev/kvm:/dev/kvm
    user: "0:0"
    ports:
      - "${WEB_BIND_IP}:${WEB_PORT}:8000"
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
volumes:
  android-data:
    name: "${ANDROID_VOLUME}"
  web-data:
    name: "${WEB_VOLUME}"
EOF
    then rm -f "$temporary"; return 1; fi
    mv -f "$temporary" "$IMAGE_COMPOSE_FILE" || { rm -f "$temporary"; return 1; }
}

# Password implementation is embedded so existing releases work without a new
# image build. Keep its scrypt/SQLite format aligned with the main script.
web_password_script()
{
    cat <<'EOF'
const fs = require('node:fs');
const crypto = require('node:crypto');
const secretFile = '/data/.android7-initial-password';
function generatePassword() {
    let password;
    do { password = crypto.randomBytes(24).toString('base64url'); }
    while (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password) || !/[-_]/.test(password));
    return password;
}
function hashPassword(password) {
    const salt = crypto.randomBytes(16);
    const hash = crypto.scryptSync(password, salt, 64, {N:16384,r:8,p:1});
    return `scrypt$16384$8$1$${salt.toString('base64')}$${hash.toString('base64')}`;
}
function matches(password, encoded) {
    if (!encoded) return false;
    const parts = encoded.split('$');
    if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
    const expected = Buffer.from(parts[5], 'base64');
    const actual = crypto.scryptSync(password, Buffer.from(parts[4], 'base64'), expected.length,
        {N:Number(parts[1]),r:Number(parts[2]),p:Number(parts[3])});
    return crypto.timingSafeEqual(actual, expected);
}
function setSetting(db, key, value) {
    db.prepare('INSERT INTO app_settings (key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value')
        .run(key, JSON.stringify(value));
}
function initializeDatabase(db) {
    db.exec('BEGIN IMMEDIATE');
    try {
        const users = db.prepare('SELECT * FROM users').all();
        const user = users[0];
        const fresh = users.length === 1 && user.id === 1 && user.username === 'admin'
            && user.role === 'admin' && !user.disabled && user.password_hash === null;
        if (fresh) {
            // Save before committing the hash so interrupted startup can recover the same password.
            let password;
            try {
                password = generatePassword();
                fs.writeFileSync(secretFile, password, {mode:0o600,flag:'wx'});
            } catch (error) {
                if (error.code !== 'EEXIST') throw error;
                password = fs.readFileSync(secretFile, 'utf8');
                if (password.length < 8 || password.length > 128) throw new Error('Invalid initial password file');
            }
            db.prepare('UPDATE users SET password_hash=? WHERE id=1').run(hashPassword(password));
            db.prepare('DELETE FROM sessions WHERE user_id=1').run();
            setSetting(db, 'authEnabled', true);
            setSetting(db, 'android7PasswordSetupRequired', false);
            setSetting(db, 'android7AuthInitialized', true);
        } else if (db.prepare('SELECT value FROM app_settings WHERE key=?').get('android7AuthInitialized')?.value !== 'true') {
            setSetting(db, 'authEnabled', true);
            setSetting(db, 'android7PasswordSetupRequired', false);
            setSetting(db, 'android7AuthInitialized', true);
        }
        db.exec('COMMIT');
    } catch (error) { db.exec('ROLLBACK'); throw error; }
}
function main(action) {
    if (!['init','show','change'].includes(action)) throw new Error('Unknown password operation');
    if (!fs.existsSync('/data/wsscrcpy.db')) { process.exitCode=75; return; }
    const {DatabaseSync} = require('node:sqlite');
    const db = new DatabaseSync('/data/wsscrcpy.db');
    try {
        db.exec('PRAGMA busy_timeout=5000');
        const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(row=>row.name);
        if (!['users','sessions','app_settings'].every(name=>tables.includes(name))) { process.exitCode=75; return; }
        if (action === 'init') { initializeDatabase(db); return; }
        if (action === 'show' && !fs.existsSync(secretFile)) return;
        const user = db.prepare("SELECT * FROM users WHERE username='admin'").get();
        if (!user || user.role !== 'admin' || user.disabled) throw new Error('Enabled admin account not found');
        if (action === 'show') {
            if (!fs.existsSync(secretFile)) return;
            const password = fs.readFileSync(secretFile, 'utf8');
            if (matches(password,user.password_hash)) {
                console.log('Web username: admin');
                console.log(`Initial web password: ${password}`);
                console.log('Save this password. It is displayed once; use the password command to reset it.');
            }
            fs.unlinkSync(secretFile);
            return;
        }
        const password = fs.readFileSync(0,'utf8');
        if (password.length < 8 || password.length > 128) throw new Error('Use 8-128 characters');
        const hash = hashPassword(password);
        db.exec('BEGIN IMMEDIATE');
        try {
            db.prepare('UPDATE users SET password_hash=?,failed_attempts=0,lockout_window_start=NULL,locked_until=NULL WHERE id=?').run(hash,user.id);
            db.prepare('DELETE FROM sessions WHERE user_id=?').run(user.id);
            setSetting(db,'authEnabled',true);
            setSetting(db,'android7PasswordSetupRequired',false);
            setSetting(db,'android7AuthInitialized',true);
            db.exec('COMMIT');
        } catch (error) { db.exec('ROLLBACK'); throw error; }
        fs.rmSync(secretFile,{force:true});
        console.log('Admin password changed. Previous sessions were signed out.');
    } finally { db.close(); }
}
module.exports = {initializeDatabase};
if (require.main === module) main(process.argv[2]);
EOF
}

# Initialize credentials before publishing the web port. An older image can
# create its native database in an isolated temporary container, without a port.
prepare_web_password() (
    local js rc bootstrap='' created=0 attempt
    js="$(web_password_script)
main(process.argv[1]);"
    docker_cmd volume create "$RELEASE_WEB_VOLUME" >/dev/null || return 1
    docker_cmd run --rm --pull never --network none --user 1000:1000 -e NODE_NO_WARNINGS=1 \
        --entrypoint node --mount "type=volume,src=$RELEASE_WEB_VOLUME,dst=/data" \
        "$WEB_IMAGE" -e "$js" init
    rc=$?
    [[ $rc != 0 ]] || return 0
    [[ $rc == 75 ]] || return "$rc"
    bootstrap="android7-password-bootstrap-$$"
    trap 'if [[ $created == 1 ]]; then docker_cmd stop -t 15 "$bootstrap" >/dev/null 2>&1; docker_cmd rm "$bootstrap" >/dev/null 2>&1; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    info 'Preparing initial web credentials before allowing network access'
    docker_cmd run -d --pull never --name "$bootstrap" --network none \
        --mount "type=volume,src=$RELEASE_WEB_VOLUME,dst=/data" "$WEB_IMAGE" >/dev/null || return 1
    created=1
    for attempt in {1..60}; do
        docker_cmd exec --user 1000:1000 -e NODE_NO_WARNINGS=1 "$bootstrap" node -e "$js" init
        rc=$?
        [[ $rc != 0 ]] || return 0
        [[ $rc == 75 ]] || { fail 'Cannot initialize web credentials.'; return "$rc"; }
        sleep 1
    done
    fail 'Timed out initializing the web database. Check the web image and retry start.'
    return 1
)

show_password() {
    local js
    js="$(web_password_script)
main(process.argv[1]);"
    docker_cmd exec --user 1000:1000 -e NODE_NO_WARNINGS=1 "$RELEASE_WEB_CONTAINER" node -e "$js" show
}
cmd_password() {
    local password='' confirmation='' js
    require_config && check_containers || return 1
    [[ $(docker_cmd inspect --format '{{.State.Running}}' "$RELEASE_WEB_CONTAINER" 2>/dev/null) == true ]] || {
        fail 'Start the deployment before changing its password.'; return 1;
    }
    echo 'Change/reset the web admin password (8-128 characters).'
    IFS= read -r -s -p 'New password: ' password || { echo; return 1; }; echo
    IFS= read -r -s -p 'Confirm password: ' confirmation || { echo; return 1; }; echo
    if [[ $password != "$confirmation" || ${#password} -lt 8 || ${#password} -gt 128 ]]; then
        fail 'Use matching passwords of 8-128 characters.'; return 2
    fi
    js="$(web_password_script)
main(process.argv[1]);"
    printf '%s' "$password" | docker_cmd exec -i --user 1000:1000 -e NODE_NO_WARNINGS=1 \
        "$RELEASE_WEB_CONTAINER" node -e "$js" change
}

# download always checks the registry; start/pull preserve the main script's
# behavior of reusing local tags and downloading missing components only.
fetch_images() {
    local force=${1:-0} reference expected actual platform
    for expected in android web; do
        reference=$ANDROID_IMAGE; [[ $expected != web ]] || reference=$WEB_IMAGE
        if [[ $force == 1 ]] || ! docker_cmd image inspect "$reference" >/dev/null 2>&1; then
            info "Pulling remote image: $reference"
            docker_cmd pull --platform linux/amd64 "$reference" || { fail "Could not pull $reference. Check the tag, network and registry credentials."; return 1; }
        else ok "Using local image: $reference"; fi
        actual=$(docker_cmd image inspect --format '{{index .Config.Labels "cloudphone.component"}}' "$reference") || return 1
        platform=$(docker_cmd image inspect --format '{{.Os}}/{{.Architecture}}' "$reference") || return 1
        if [[ $actual != "$expected" || $platform != linux/amd64 ]]; then
            fail "$reference must be a two-container $expected image for linux/amd64."; return 1
        fi
    done
}
show_access() {
    echo "Web (local): http://127.0.0.1:$WEB_PORT"
    if [[ $WEB_ACCESS_MODE == public ]]; then
        echo "Web (remote): http://<server-ip>:$WEB_PORT (sign-in required)"
        echo 'Remote screen streaming may require an HTTPS reverse proxy; this script creates no proxy or tunnel.'
    else echo 'Safe mode: only localhost can connect.'; fi
}
cmd_start() {
    check_pending && check_kvm && check_containers || return 1
    fetch_images || return 1
    write_config || return 1
    prepare_web_password || return 1
    idc up -d --no-build --pull never || return 1
    ok 'Android and web containers started.'
    show_access
    show_password
}
cmd_reset() {
    local answer='' helper users
    require_config && check_pending && check_kvm && check_containers || return 1
    check_volume_users "$RELEASE_VOLUME" "$RELEASE_WEB_VOLUME" || return 1
    echo 'ANDROID FACTORY RESET'
    echo 'Deletes Android apps, accounts, settings and app data. Keeps web accounts/passwords.'
    echo "Target: $RELEASE_VOLUME (avd/ and android.ready only). Both services restart afterwards."
    if ! read -r -p 'Type YES to reset Android: ' answer || [[ $answer != YES ]]; then echo 'Reset cancelled.'; return 0; fi
    docker_cmd volume inspect "$RELEASE_VOLUME" "$RELEASE_WEB_VOLUME" >/dev/null || return 1
    helper=$(docker_cmd image inspect --format '{{.Id}}' "$ANDROID_IMAGE") || return 1
    docker_cmd image inspect "$WEB_IMAGE" >/dev/null || return 1
    idc down || return 1
    users=$(docker_cmd ps -aq --filter "volume=$RELEASE_VOLUME") || return 1
    [[ -z $users ]] || { fail 'Another container references Android data; reset cancelled.'; return 1; }
    docker_cmd run --rm --pull never --network none --user 0:0 --entrypoint /bin/sh \
        --mount "type=volume,src=$RELEASE_VOLUME,dst=/reset-data" "$helper" \
        -ec 'rm -rf -- /reset-data/avd /reset-data/android.ready' || return 1
    if ! idc up -d --no-build --pull never; then
        fail 'Android was reset, but startup failed. Check log, then retry start.'; return 1
    fi
    ok 'Android reset; web accounts and passwords retained.'
}
cmd_purge() {
    local answer='' target
    check_containers && check_volume_users "$RELEASE_VOLUME" "$RELEASE_WEB_VOLUME" || return 1
    echo 'PERMANENTLY DELETE ALL CLOUD PHONE DATA'
    echo "Containers: $RELEASE_CONTAINER + $RELEASE_WEB_CONTAINER"
    echo "Volumes: $RELEASE_VOLUME + $RELEASE_WEB_VOLUME"
    echo 'Deletes apps, files, accounts, settings AND web passwords. Keeps images. Does not restart.'
    if ! read -r -p 'Type YES to permanently delete this data: ' answer || [[ $answer != YES ]]; then echo 'Purge cancelled.'; return 0; fi
    for target in "$RELEASE_WEB_CONTAINER" "$RELEASE_CONTAINER"; do
        if docker_cmd container inspect "$target" >/dev/null 2>&1; then
            docker_cmd stop "$target" && docker_cmd rm "$target" || return 1
        fi
    done
    # Both checks precede either removal; never partially delete due to a known reference.
    check_volume_users "$RELEASE_VOLUME" "$RELEASE_WEB_VOLUME" || return 1
    for target in "$RELEASE_WEB_VOLUME" "$RELEASE_VOLUME"; do
        if docker_cmd volume inspect "$target" >/dev/null 2>&1; then docker_cmd volume rm "$target" || return 1; fi
    done
    rm -f "$BASE_DIR/.android7-migration-image.pending" || return 1
    ok 'Containers and all runtime data removed. Images retained; phone remains stopped.'
    echo 'The next start creates a new phone and prints a new random admin password.'
}

usage() {
    cat <<EOF
Yan Yu Jiang Hu - standalone Android 7 image deployment

Usage: ./android7-image.sh COMMAND [options]
       ./android7-image.sh start [--safe|--public] [--port PORT] [ANDROID_IMAGE WEB_IMAGE]

Start and download:
  start / pull      Reuse local tags or pull missing images, then START both services
  download          Pull both remote tags ONLY; do not create/start containers
  --safe            Localhost access only (start/pull); choice is saved
  --public          Access via server IP (start/pull); default, sign-in still required
  --port PORT       Set host web port (1-65535, start/pull); saved for later starts
  Both image tags are optional; provide both or neither. Tags only, no digest pins.

Manage:
  status            Show both services and health
  log               Follow the latest 100 log lines; Ctrl+C leaves the phone running
  stop              Stop both services, retaining containers and data
  restart           Restart existing services, retaining data and current bindings
  down              Remove both containers/network, retaining data volumes
  password          Change/reset admin password through hidden input; requires running web

Reset and remove (require typing YES):
  reset             Clear Android apps/accounts/data and restart; KEEP web passwords
  purge             Remove containers and ALL Android/web data; keep images; do not restart
  help              Show this page (also the default when no command is given)

Defaults:
  Android: $RELEASE_IMAGE
  Web:     $RELEASE_WEB_IMAGE
  Names:   $RELEASE_CONTAINER + $RELEASE_WEB_CONTAINER
  Volumes: $RELEASE_VOLUME + $RELEASE_WEB_VOLUME
  Port:    $DEFAULT_WEB_PORT; Android: 6 GiB; timezone: Asia/Shanghai
  First start prints a unique 32-character admin password once; existing passwords stay.

Examples:
  ./android7-image.sh start
  ./android7-image.sh start --safe --port 18000
  ./android7-image.sh download
  ./android7-image.sh start myrepo/phone:android myrepo/phone:web
  ./android7-image.sh password

Requires Linux x86_64, KVM, Docker and Compose (download needs only Docker).
No builds, pushes or migrations. This file works without android7.sh.
Uses the same .android7-image.env / compose.image.yml as the main script in this folder.
Keep those files with the script; do not run two managers concurrently.
Use start --port PORT to change a binding; restart retains the existing port.
Changing a port briefly recreates containers but preserves data and passwords.
Download does not change saved configuration. To select downloaded custom tags,
pass both tags to start. Existing manual Docker containers are not silently adopted.
EOF
}

main() (
    local action=${1:-help} arg
    local -a refs=()
    WEB_ACCESS_REQUEST=''
    WEB_PORT_REQUEST=''
    (($# == 0)) || shift
    case "$action" in help|-h|--help) usage; return 0 ;; esac
    if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; return 0; fi
    case "$action" in
        start|pull|download)
            while (($#)); do
                arg=$1; shift
                case "$arg" in
                    --safe|--public)
                        if [[ $action == download || -n $WEB_ACCESS_REQUEST ]]; then fail 'Access options apply once to start/pull only.'; return 2; fi
                        WEB_ACCESS_REQUEST=${arg#--} ;;
                    --port|--port=*)
                        if [[ $action == download || -n $WEB_PORT_REQUEST ]]; then fail 'Specify --port once, for start/pull only.'; return 2; fi
                        if [[ $arg == --port ]]; then
                            (($#)) || { fail '--port requires a value (1-65535).'; return 2; }
                            WEB_PORT_REQUEST=$1; shift
                        else WEB_PORT_REQUEST=${arg#--port=}; fi
                        valid_web_port "$WEB_PORT_REQUEST" || { fail 'Use a decimal port from 1 to 65535.'; return 2; }
                        ;;
                    -*) fail "Unknown option: $arg"; return 2 ;;
                    *) refs+=("$arg") ;;
                esac
            done
            if ((${#refs[@]} != 0 && ${#refs[@]} != 2)); then fail 'Provide both image tags or neither.'; return 2; fi
            ;;
        stop|restart|down|status|log|password|reset|purge)
            (($# == 0)) || { fail "$action takes no additional arguments."; return 2; } ;;
        *) fail "Unknown command: $action. Use help; build and migration are not included."; return 2 ;;
    esac
    # One mutating invocation at a time in this directory; log/status remain read-only.
    if [[ $action != status && $action != log ]]; then
        command -v flock >/dev/null || { fail 'flock is missing; install util-linux.'; return 1; }
        exec 9> "$BASE_DIR/.android7-image.lock" || return 1
        flock -n 9 || { fail 'Another image operation is running in this directory.'; return 1; }
    fi
    load_config || { fail 'Invalid saved deployment configuration; nothing was changed.'; return 1; }
    if ((${#refs[@]})); then ANDROID_IMAGE=${refs[0]}; WEB_IMAGE=${refs[1]}; fi
    valid_image "$ANDROID_IMAGE" && valid_image "$WEB_IMAGE" && [[ $ANDROID_IMAGE != "$WEB_IMAGE" ]] || {
        fail 'Use two distinct valid image tags, not digests.'; return 2;
    }
    if [[ $action == download || $action == password || $action == purge ]]; then ensure_docker --engine-only || return 1
    else ensure_docker || return 1; fi
    case "$action" in
        start|pull) cmd_start ;;
        download) fetch_images 1 && ok 'Both remote images downloaded. Containers and saved settings unchanged.' ;;
        password) cmd_password ;;
        reset) cmd_reset ;;
        purge) cmd_purge ;;
        *)
            require_config && check_containers || return 1
            case "$action" in
                status) idc ps -a ;;
                log) echo 'Ctrl+C exits log view only.'; idc logs --tail 100 -f ;;
                stop) idc stop ;;
                restart) check_pending && idc restart ;;
                down) idc down ;;
            esac ;;
    esac
)

# Sourcing exposes functions for isolated validation without executing actions.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
