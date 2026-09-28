#!/usr/bin/env bash

# ============================================================
# Android Emulator / ReDroid APK Installer
#
# Default container:
#   yanyu-android7 (image mode)
#   For dev mode, pass: -c yanyu-android7-dev
#
# Container can be specified by:
#
#   ./install-apk.sh -c CONTAINER APK
#
# or:
#
#   REDROID_CONTAINER=CONTAINER ./install-apk.sh APK
#
# Both Docker container names and container IDs are supported.
#
# Multiple APK files can be installed in one invocation.
#
# This script intentionally does NOT use `docker cp`.
# APKs are streamed into /data/local/tmp instead.
# ============================================================

DEFAULT_CONTAINER="yanyu-android7"
CONTAINER="${REDROID_CONTAINER:-$DEFAULT_CONTAINER}"
ANDROID_SHELL=()


# Show installer options and multi-APK examples.
print_usage() {
    cat <<EOF_USAGE
Usage:
  $0 [options] APK [APK ...]

Options:
  -c, --container NAME_OR_ID
      Android Emulator or ReDroid container name or container ID.

      Default:
        $DEFAULT_CONTAINER

      Environment variable is also supported:
        REDROID_CONTAINER=android7-test $0 app.apk

  -h, --help
      Show this help.

Examples:
  $0 ~/app.apk

  $0 -c yanyu-android7-dev ~/app.apk

  $0 -c android7-ndk023-test ~/app.apk

  $0 --container 1eb2c40f9288 ~/app.apk

  REDROID_CONTAINER=android7-houdini-test \
    $0 ~/app.apk

  $0 -c android7 ~/app1.apk ~/app2.apk
EOF_USAGE
}


# Check container state, choose emulator ADB or direct ReDroid shell and verify package-manager readiness.
check_container() {
    echo "Checking container: $CONTAINER"

    if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
        echo
        echo "ERROR: Docker container does not exist:"
        echo "  $CONTAINER"
        return 1
    fi

    local running

    running="$(
        docker inspect \
            -f '{{.State.Running}}' \
            "$CONTAINER" \
            2>/dev/null
    )"

    if [ "$running" != "true" ]; then
        echo
        echo "ERROR: Docker container is not running:"
        echo "  $CONTAINER"
        return 1
    fi

    if docker exec "$CONTAINER" sh -c 'command -v pm' >/dev/null 2>&1; then
        ANDROID_SHELL=(sh -c)
        echo "Android access: direct (ReDroid)"
    elif docker exec "$CONTAINER" sh -c 'command -v adb' >/dev/null 2>&1; then
        local serial
        serial="${ANDROID_SERIAL:-$(
            docker exec "$CONTAINER" sh -c 'printf "%s" "${ANDROID_SERIAL:-emulator-5556}"'
        )}"
        ANDROID_SHELL=(adb -s "$serial" shell -T)
        echo "Android access: ADB ($serial)"
    else
        echo "ERROR: Neither Android pm nor adb is available in the container."
        return 1
    fi

    if ! android_shell 'pm path android' 2>/dev/null | grep -q '^package:'; then
        echo "ERROR: Android package manager is not ready. Wait for Android to boot."
        return 1
    fi

    echo "Container: OK"
    return 0
}


# Execute the supplied Android shell command through the selected transport.
android_shell() {
    docker exec "$CONTAINER" "${ANDROID_SHELL[@]}" "$1"
}


# Stream a completed APK, detect source changes, verify byte count and install it.
install_one_apk() {
    local apk="$1"
    local apk_abs
    local host_size
    local host_state
    local host_state_after
    local container_size
    local tmp_apk
    local cat_rc
    local docker_rc
    local transfer_status=()
    local install_output
    local install_rc

    if [ ! -f "$apk" ]; then
        echo
        echo "ERROR: APK does not exist:"
        echo "  $apk"
        return 1
    fi

    apk_abs="$(
        readlink -f "$apk" 2>/dev/null
    )"

    if [ -z "$apk_abs" ]; then
        apk_abs="$apk"
    fi

    # Record identity, size and nanosecond timestamps to detect ongoing downloads
    # or replacement of the source while the APK is being streamed.
    host_state="$(
        stat -L -c '%s:%d:%i:%y:%z' -- "$apk" 2>/dev/null
    )"
    host_size="${host_state%%:*}"

    if [ -z "$host_size" ]; then
        echo
        echo "ERROR: Cannot determine APK size:"
        echo "  $apk_abs"
        return 1
    fi

    #
    # Unique temporary file for this invocation.
    #
    tmp_apk="/data/local/tmp/__install_apk_${$}_$(basename "$apk").apk"

    #
    # Avoid problematic characters in Android temporary filename.
    #
    tmp_apk="$(
        printf '%s' "$tmp_apk" |
        sed 's/[^A-Za-z0-9._\/-]/_/g'
    )"

    echo
    echo "============================================================"
    echo "INSTALL APK"
    echo "============================================================"
    echo "Host file : $apk_abs"
    echo "Container : $CONTAINER"
    echo "Temp file : $tmp_apk"
    echo
    echo "APK size:"
    echo "  $host_size bytes"

    echo
    echo "Preparing Android temporary directory..."

    if ! android_shell 'mkdir -p /data/local/tmp && test -w /data/local/tmp'
    then
        echo
        echo "ERROR: Cannot prepare /data/local/tmp"
        return 1
    fi

    #
    # Remove a stale temporary file if one somehow exists.
    #
    android_shell "rm -f '$tmp_apk'" \
        >/dev/null 2>&1 || true

    echo
    echo "Transferring APK..."

    cat "$apk" |
        docker exec -i "$CONTAINER" \
            "${ANDROID_SHELL[@]}" "cat > '$tmp_apk'"

    # Capture both statuses before any assignment overwrites PIPESTATUS.
    transfer_status=("${PIPESTATUS[@]}")
    cat_rc=${transfer_status[0]}
    docker_rc=${transfer_status[1]}

    if [ "$cat_rc" -ne 0 ] || [ "$docker_rc" -ne 0 ]; then
        echo
        echo "ERROR: APK transfer failed."
        echo "  cat rc    : $cat_rc"
        echo "  docker rc : $docker_rc"

        android_shell "rm -f '$tmp_apk'" \
            >/dev/null 2>&1 || true

        return 1
    fi

    host_state_after="$(stat -L -c '%s:%d:%i:%y:%z' -- "$apk" 2>/dev/null)"
    if [ "$host_state" != "$host_state_after" ]; then
        echo
        echo "ERROR: Source APK changed or became unavailable during transfer."
        echo "  size before: $host_size"
        echo "  size after : ${host_state_after%%:*}"
        echo "Wait for the download or file copy to finish, then run this command again."

        android_shell "rm -f '$tmp_apk'" \
            >/dev/null 2>&1 || true
        return 1
    fi

    android_shell "chmod 0644 '$tmp_apk'" \
        >/dev/null 2>&1 || true

    container_size="$(
        android_shell "stat -c '%s' '$tmp_apk'" \
            2>/dev/null |
        tr -d '\r'
    )"

    echo
    echo "Size verification:"
    echo "  host      : $host_size"
    echo "  container : ${container_size:-UNKNOWN}"

    if [ "$host_size" != "$container_size" ]; then
        echo
        echo "ERROR: APK size mismatch."

        android_shell "rm -f '$tmp_apk'" \
            >/dev/null 2>&1 || true

        return 1
    fi

    echo "Transfer verification: OK"

    echo
    echo "Installing..."

    install_output="$(
        android_shell "pm install -r '$tmp_apk'" \
            2>&1
    )"

    install_rc=$?

    printf '%s\n' "$install_output"

    echo
    echo "Cleaning temporary APK..."

    android_shell "rm -f '$tmp_apk'" \
        >/dev/null 2>&1 || true

    if [ "$install_rc" -ne 0 ]; then
        echo
        echo "INSTALL FAILED:"
        echo "  $apk_abs"
        return 1
    fi

    if ! printf '%s\n' "$install_output" |
        grep -q '^Success'
    then
        echo
        echo "INSTALL FAILED:"
        echo "  pm install did not return Success"
        return 1
    fi

    echo
    echo "INSTALL SUCCESS:"
    echo "  $apk_abs"

    return 0
}


# Parse container/APK arguments, install each package and aggregate failures.
main() {
    local failed=0
    local apk

    while [ "$#" -gt 0 ]; do
        case "$1" in

            -c|--container)
                if [ "$#" -lt 2 ]; then
                    echo "ERROR: $1 requires a container name or ID."
                    echo
                    print_usage
                    return 1
                fi

                CONTAINER="$2"
                shift 2
                ;;

            -h|--help)
                print_usage
                return 0
                ;;

            --)
                shift
                break
                ;;

            -*)
                echo "ERROR: Unknown option:"
                echo "  $1"
                echo
                print_usage
                return 1
                ;;

            *)
                break
                ;;
        esac
    done

    if [ "$#" -eq 0 ]; then
        echo "ERROR: No APK specified."
        echo
        print_usage
        return 1
    fi

    echo "============================================================"
    echo "ANDROID APK INSTALLER"
    echo "============================================================"
    echo "Container: $CONTAINER"

    if ! check_container; then
        return 1
    fi

    for apk in "$@"; do
        if ! install_one_apk "$apk"; then
            failed=1
        fi
    done

    echo
    echo "============================================================"

    if [ "$failed" -eq 0 ]; then
        echo "ALL APK INSTALLS COMPLETED"
        echo "============================================================"
        return 0
    else
        echo "ONE OR MORE APK INSTALLS FAILED"
        echo "============================================================"
        return 1
    fi
}


main "$@"
