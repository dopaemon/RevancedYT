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
T_CHANNEL=() T_PATCHES=() T_APKM_NAME=() T_APKM_SLUG=()

add_target() {
    local display=$1 pkg=$2 apk_dir=$3 uninstall=$4 fallback=${5:-}
    local apkm_name=${6:-} apkm_slug=${7:-}
    local i=${#T_PACKAGE[@]}
    T_PACKAGE[$i]="$pkg"; T_APK_DIR[$i]="$apk_dir"; T_DISPLAY_NAME[$i]="$display"
    T_UNINSTALL_FIRST[$i]="$uninstall"; T_FALLBACK_VERSION[$i]="$fallback"
    T_APKM_NAME[$i]="$apkm_name"; T_APKM_SLUG[$i]="$apkm_slug"
}
add_target "YouTube"      "com.google.android.youtube"            "youtube"       "false" "20.40.45"
add_target "YouTubeMusic" "com.google.android.apps.youtube.music" "youtube-music" "true"  "8.46.53"
add_target "TikTok"       "com.zhiliaoapp.musically"              "tiktok"        "true"  ""        "tiktok" "/tik-tok-including-musical-ly/"

source "$CURDIR/revanced-common.sh"
add_channel dev    dev
add_channel stable main
expand_targets_for_channels

fail=0
chk() { [ "$1" = "$2" ] || { echo "FAIL: expected '$2' got '$1'"; fail=1; }; }

chk "${#T_PACKAGE[@]}" 6
chk "${T_CHANNEL[0]}" dev
chk "${T_CHANNEL[3]}" stable
chk "${T_LABEL[0]}" RevancedYT-dev
chk "${T_LABEL[4]}" RevancedYTMusic-stable
chk "${T_MODULE_ID[1]}" revanced-youtube-music-dev
chk "${T_UPDATE_FILE[3]}" youtube-stableupdate.json
chk "${T_MODULE_PATH[3]}" "$MODULEBUILDROOT/youtube-stable"
chk "${T_MODULE_NAME[3]}" "YouTube Revanced (stable)"
# APKMirror lookup hints survive the expansion
chk "${T_APKM_NAME[2]}" tiktok
chk "${T_APKM_SLUG[5]}" /tik-tok-including-musical-ly/
chk "${T_APKM_NAME[0]}" ""
chk "${T_LABEL[5]}" RevancedTikTok-stable

# module paths and release asset names must be unique across channels
uniq_paths=$(printf '%s\n' "${T_MODULE_PATH[@]}" | sort -u | wc -l | tr -d ' ')
chk "$uniq_paths" 6
uniq_ids=$(printf '%s\n' "${T_MODULE_ID[@]}" | sort -u | wc -l | tr -d ' ')
chk "$uniq_ids" 6

# bundles are attached only after the tools are built
CH_PATCHES[0]=/tmp/patches-dev.rvp; CH_PATCHES[1]=/tmp/patches-stable.rvp
sync_target_patches
chk "${T_PATCHES[0]}" /tmp/patches-dev.rvp
chk "${T_PATCHES[3]}" /tmp/patches-stable.rvp

rm -f "$LOGFILE"
[ "$fail" -eq 0 ] && echo "channel expansion OK"

# --- bundle detection --------------------------------------------------------
tmp=$(mktemp -d)
mkdir -p "$tmp/assets"
echo x >"$tmp/AndroidManifest.xml"; echo x >"$tmp/assets/nested.apk"
(cd "$tmp" && zip -qr plain.zip AndroidManifest.xml assets)
mkdir -p "$tmp/b"; echo x >"$tmp/b/base.apk"; echo x >"$tmp/b/split_config.arm64_v8a.apk"
(cd "$tmp/b" && zip -qr ../bundle.zip .)
is_apk_bundle "$tmp/plain.zip"  && { echo "FAIL: plain APK detected as bundle"; fail=1; }
is_apk_bundle "$tmp/bundle.zip" || { echo "FAIL: bundle not detected"; fail=1; }
rm -rf "$tmp"

[ "$fail" -eq 0 ] && echo "bundle detection OK" || exit 1
