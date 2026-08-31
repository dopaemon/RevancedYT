#!/usr/bin/env bash
# Self-check for the dev/stable channel expansion. Run: ./test_channels.sh
set -euo pipefail
CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOGFILE=$(mktemp); MODULEBUILDROOT=/tmp/.module-build; RELEASE_REPO=dopaemon/RevancedYT
MODULETEMPLATEPATH=$CURDIR/RevancedModule

T_PACKAGE=() T_APK_DIR=() T_MODULE_ID=() T_MODULE_NAME=()
T_MODULE_DESC=() T_UPDATE_JSON=() T_UPDATE_FILE=() T_UNINSTALL_FIRST=()
T_LABEL=() T_DISPLAY_NAME=() T_FALLBACK_VERSION=()
T_RESOLVED_VERSION=() T_FALLBACK_PREFERRED=()
T_VERSION=() T_VERSIONCODE=() T_NAME=() T_MODULE_PATH=()
T_CHANNEL=() T_PATCHES=()

add_target() {
    local display=$1 pkg=$2 apk_dir=$3 uninstall=$4 fallback=${5:-}
    local i=${#T_PACKAGE[@]}
    T_PACKAGE[$i]="$pkg"; T_APK_DIR[$i]="$apk_dir"; T_DISPLAY_NAME[$i]="$display"
    T_UNINSTALL_FIRST[$i]="$uninstall"; T_FALLBACK_VERSION[$i]="$fallback"
}
add_target "YouTube"      "com.google.android.youtube"            "youtube"       "false" "20.40.45"
add_target "YouTubeMusic" "com.google.android.apps.youtube.music" "youtube-music" "true"  "8.46.53"

source "$CURDIR/revanced-common.sh"
add_channel dev    dev
add_channel stable main
expand_targets_for_channels

fail=0
chk() { [ "$1" = "$2" ] || { echo "FAIL: expected '$2' got '$1'"; fail=1; }; }

chk "${#T_PACKAGE[@]}" 4
chk "${T_CHANNEL[0]}" dev
chk "${T_CHANNEL[3]}" stable
chk "${T_LABEL[0]}" RevancedYT-dev
chk "${T_LABEL[3]}" RevancedYTMusic-stable
chk "${T_MODULE_ID[1]}" revanced-youtube-music-dev
chk "${T_UPDATE_FILE[2]}" youtube-stableupdate.json
chk "${T_MODULE_PATH[2]}" "$MODULEBUILDROOT/youtube-stable"
chk "${T_MODULE_NAME[2]}" "YouTube Revanced (stable)"

# module paths and release asset names must be unique across channels
uniq_paths=$(printf '%s\n' "${T_MODULE_PATH[@]}" | sort -u | wc -l | tr -d ' ')
chk "$uniq_paths" 4
uniq_ids=$(printf '%s\n' "${T_MODULE_ID[@]}" | sort -u | wc -l | tr -d ' ')
chk "$uniq_ids" 4

# bundles are attached only after the tools are built
CH_PATCHES[0]=/tmp/patches-dev.rvp; CH_PATCHES[1]=/tmp/patches-stable.rvp
sync_target_patches
chk "${T_PATCHES[0]}" /tmp/patches-dev.rvp
chk "${T_PATCHES[2]}" /tmp/patches-stable.rvp

rm -f "$LOGFILE"
[ "$fail" -eq 0 ] && echo "channel expansion OK" || exit 1
