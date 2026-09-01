#!/usr/bin/env bash
set -euo pipefail

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOGFILE="$CURDIR/.tiktok_build.log"
WGET_HEADER="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:102.0) Gecko/20100101 Firefox/102.0"
MODULETEMPLATEPATH=$CURDIR/RevancedModule
MODULEBUILDROOT=$CURDIR/.module-build-tiktok
DATE=$(date +%y%m%d)
MODE=${1:-build}
IS_TEST=false
if [ "$MODE" = "test" ]; then
    IS_TEST=true
fi
DRAFT=false
PRERELEASE=$IS_TEST
RELEASE_SERIES="tiktok_${DATE}"
RELEASE_TITLE_BASE="Revanced TikTok"
if [ "$IS_TEST" = "true" ]; then
    RELEASE_SERIES="tiktok_test_${DATE}"
    RELEASE_TITLE_BASE="Revanced TikTok Test"
fi
SKIP_UPLOAD=${SKIP_UPLOAD:-false}
RELEASE_REPO=${RELEASE_REPO:-${GITHUB_REPOSITORY:-dopaemon/RevancedYT}}
EXTRA_PATCHES_REPO=${EXTRA_PATCHES_REPO:-dopaemon/Patches}
FAST_BUILD=${FAST_BUILD:-false}
APKMIRROR_BASE_URL=${APKMIRROR_BASE_URL:-https://www.apkmirror.com}
SANITIZE_PNGS=true
PREFER_BUNDLE=true
# ReVanced's own TikTok patches no longer apply to the versions APKMirror
# lists, so TikTok is patched the way mentalblank/Tiktok-Revanced does it:
# a dedicated TikTok patch set (.mpp) driven by the Morphe CLI, both taken from their
# latest release instead of being built from source.
# De-Vanced dropped its TikTok patches in v1.2.0, so the bundle comes from a
# dedicated TikTok patch set instead - always its latest release.
PATCHES_RELEASE_REPO=${PATCHES_RELEASE_REPO:-icysymmetra/tiktok-patches-for-morphe}
PATCHES_RELEASE_TAG=${PATCHES_RELEASE_TAG:-latest}
CLI_RELEASE_REPO=${CLI_RELEASE_REPO:-MorpheApp/morphe-cli}
CLI_RELEASE_TAG=${CLI_RELEASE_TAG:-latest}
# The private bundle is a ReVanced .rvp, which Morphe cannot read, so it is
# applied in a second pass with the stock ReVanced CLI.
RVCLI_RELEASE_REPO=${RVCLI_RELEASE_REPO:-ReVanced/revanced-cli}
RVCLI_RELEASE_TAG=${RVCLI_RELEASE_TAG:-latest}
# "SIM spoof" ships disabled; the reference build enables it.
PATCH_ARGS=(-e "SIM spoof")

# ---------------------------------------------------------------------------
# Per-target arrays – populated by add_target() below.
T_PACKAGE=() T_APK_DIR=() T_MODULE_ID=() T_MODULE_NAME=()
T_MODULE_DESC=() T_UPDATE_JSON=() T_UPDATE_FILE=() T_UNINSTALL_FIRST=()
T_LABEL=() T_DISPLAY_NAME=() T_FALLBACK_VERSION=()
T_RESOLVED_VERSION=() T_FALLBACK_PREFERRED=()
T_VERSION=() T_VERSIONCODE=() T_NAME=() T_MODULE_PATH=()
T_CHANNEL=() T_PATCHES=() T_APKM_NAME=() T_APKM_SLUG=()

# Release/announcement identity for this pipeline.
RELEASE_TAG_RE='^tiktok_'
APK_SUFFIX=""
POST_BANNER="$CURDIR/tiktok-banner.png"
POST_TITLE="ReVanced | TikTok"
POST_TAGS="#DoraCore #ReVanced #TikTok #NoRoot #Magisk"
POST_CAUTION="• APK — uninstall the Play Store TikTok first, no MicroG needed.
• ZIP (root) — flash in Magisk, no reboot needed.
• Disable TikTok auto-updates in Play Store."

# add_target DISPLAY PACKAGE APK_DIR UNINSTALL_FIRST [FALLBACK_VERSION] [APKM_NAME] [APKM_SLUG]
#   DISPLAY         - human-readable app name   (e.g. "YouTube", "YouTubeMusic")
#   PACKAGE         - Android package name
#   APK_DIR         - base-APK subdirectory     (e.g. "youtube", "youtube-music")
#   UNINSTALL_FIRST - "true" if old install must be removed first
#   FALLBACK_VERSION- preferred fallback version (used if higher than resolved)
add_target() {
    local display=$1 pkg=$2 apk_dir=$3 uninstall=$4 fallback=${5:-}
    local apkm_name=${6:-} apkm_slug=${7:-}
    local i=${#T_PACKAGE[@]}
    local label="Revanced${display/YouTube/YT}"    # e.g. "YouTubeMusic" → "RevancedYTMusic"
    T_PACKAGE[$i]="$pkg"
    T_APK_DIR[$i]="$apk_dir"
    T_MODULE_ID[$i]="revanced-${apk_dir}"
    T_DISPLAY_NAME[$i]="$display"
    T_MODULE_NAME[$i]="${display} Revanced"
    T_LABEL[$i]="$label"
    T_MODULE_DESC[$i]="${label} Module by @Shekhawat2"
    T_UPDATE_FILE[$i]="${apk_dir}update.json"
    T_UPDATE_JSON[$i]="https://github.com/shekhawat2/RevancedYT/releases/latest/download/${apk_dir}update.json"
    T_UNINSTALL_FIRST[$i]="$uninstall"
    T_FALLBACK_VERSION[$i]="$fallback"
    T_APKM_NAME[$i]="$apkm_name"
    T_APKM_SLUG[$i]="$apkm_slug"
    T_RESOLVED_VERSION[$i]=""
    T_FALLBACK_PREFERRED[$i]="false"
    T_MODULE_PATH[$i]="$MODULEBUILDROOT/${apk_dir}"
    T_VERSION[$i]="" T_VERSIONCODE[$i]="" T_NAME[$i]=""
}

# ---------------------------------------------------------------------------
# Target definitions – add a new add_target line here to support another app.
# ---------------------------------------------------------------------------
# APKMirror lists TikTok under "tiktok", not under the package name, and the
# search also returns TikTok Lite - pin the app slug.
# Fallback only: the version is normally resolved from the patch bundle, which
# follows TikTok as the patch set is updated.
add_target "TikTok" "com.zhiliaoapp.musically" "tiktok" "true" "46.2.3" "tiktok" "/tik-tok-including-musical-ly/"

# Patch channels - every app is built once per channel.
# ---------------------------------------------------------------------------

source "$CURDIR/revanced-common.sh"

add_channel de-vanced ""
expand_targets_for_channels

# The patch bundle and the CLI are released artifacts, so there is nothing to
# clone, patch or compile - just fetch them.
clone_tools() { :; }
patch_tools() { :; }

# dl_release_asset REPO TAG EXTENSION OUT -> prints the release tag
# TAG is either "latest" or a tag name.
dl_release_asset() {
    local repo=$1 rel=$2 ext=$3 out=$4 meta url tag
    [ "$rel" = "latest" ] || rel="tags/${rel}"
    meta=$(curl -fsSL -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${repo}/releases/${rel}") \
        || { error "Failed to query release ${rel} of ${repo}"; exit 1; }
    url=$(jq -r --arg ext "$ext" 'first(.assets[] | select(.name | endswith($ext)) | .browser_download_url) // empty' <<<"$meta")
    tag=$(jq -r '.tag_name // empty' <<<"$meta")
    [ -n "$url" ] || { error "No ${ext} asset in release ${rel} of ${repo}"; exit 1; }
    curl -fsSL "$url" -o "$out" || { error "Failed to download ${url}"; exit 1; }
    printf '%s' "${tag#v}"
}

build_tools() {
    status "Fetching TikTok patches and the Morphe CLI..."
    CH_PATCHES[0]="$CURDIR/patches.mpp"
    CH_PATCHESVER[0]=$(dl_release_asset "$PATCHES_RELEASE_REPO" "$PATCHES_RELEASE_TAG" ".mpp" "${CH_PATCHES[0]}")
    CLI="$CURDIR/morphe-cli.jar"
    CLIVER=$(dl_release_asset "$CLI_RELEASE_REPO" "$CLI_RELEASE_TAG" "-all.jar" "$CLI")
    success "TikTok patches (${PATCHES_RELEASE_REPO}): ${CH_PATCHESVER[0]}"
    RVCLI="$CURDIR/revanced-cli.jar"
    RVCLIVER=$(dl_release_asset "$RVCLI_RELEASE_REPO" "$RVCLI_RELEASE_TAG" "-all.jar" "$RVCLI")
    success "Morphe CLI: ${CLIVER}"
    success "ReVanced CLI: ${RVCLIVER}"
    sync_target_patches
}

list_compatible_versions() {
    local i=$1 pkg=$2
    java -jar "$CLI" list-patches \
        --patches "${T_PATCHES[$i]}" \
        --filter-package-name="$pkg" \
        --with-packages \
        --with-versions 2>>"$LOGFILE"
}

# Morphe is a ReVanced CLI fork with its own flags: no --purge, no -b
# (it never verifies the stock signature), and failing patches are skipped
# instead of aborting the run.
patch_apk_with_args() {
    local output_apk=$1 input_apk=$2
    shift 2
    local patch_output
    patch_output=$(mktemp)

    java -jar "$CLI" patch "$input_apk" \
        -o "$output_apk" \
        -p "$PATCHES" \
        --keystore="$KEYSTORE" \
        --keystore-password="$KEYSTORE_PASSWORD" \
        --keystore-entry-alias="$KEYSTORE_ALIAS" \
        --keystore-entry-password="$KEYSTORE_ENTRY_PASSWORD" \
        --force \
        --continue-on-error \
        "$@" 2>&1 | tee "$patch_output" >>"$LOGFILE"

    local applied
    applied=$(grep -cE 'Applied: ' "$patch_output" || true)
    if [ "${PIPESTATUS[0]}" -eq 0 ] && [ -f "$output_apk" ] && [ "$applied" -gt 0 ]; then
        grep -E '^(SEVERE|WARNING): ' "$patch_output" | tee -a "$LOGFILE" || true
        success "Applied ${applied} patch(es) to $(basename "$input_apk")"
        rm -f "$patch_output"
        return 0
    fi

    # A run that applies nothing still produces a signed APK - that is stock
    # TikTok, not a patched build, so treat it as a failure.
    if [ "$applied" -eq 0 ] && [ -f "$output_apk" ]; then
        error "No patch applied to $(basename "$input_apk"); the bundle has none for this app/version"
        rm -f "$output_apk"
    fi

    error "Patching failed for $(basename "$input_apk"). Showing relevant patch errors:"
    tail -n 60 "$patch_output" | tee -a "$LOGFILE"
    rm -f "$patch_output"
    return 1
}

patch_main_apks() {
    status "Patching apps..."
    for i in "${!T_PACKAGE[@]}"; do
        local PATCHES="${T_PATCHES[$i]}"
        local output_apk="${T_MODULE_PATH[$i]}/${T_MODULE_ID[$i]}.apk"
        local input_apk="${T_MODULE_PATH[$i]}/${T_APK_DIR[$i]}/base.apk"

        # TikTok has no GmsCore patch, so root and non-root share one build.
        if patch_apk_with_args "$output_apk" "$input_apk" "${PATCH_ARGS[@]}"; then
            success "${T_MODULE_NAME[$i]} patched successfully"
            continue
        fi

        if [ "${T_FALLBACK_PREFERRED[$i]:-false}" = "true" ] && [ -n "${T_RESOLVED_VERSION[$i]:-}" ] && [ "${T_VERSION[$i]}" != "${T_RESOLVED_VERSION[$i]}" ]; then
            warn "${T_MODULE_NAME[$i]} failed with preferred fallback ${T_VERSION[$i]}; retrying with resolved ${T_RESOLVED_VERSION[$i]}"
            T_VERSION[$i]="${T_RESOLVED_VERSION[$i]}"
            download_target_base_apk "$i" "${T_VERSION[$i]}"
            rm -f "$output_apk"
            if patch_apk_with_args "$output_apk" "$input_apk" "${PATCH_ARGS[@]}"; then
                success "${T_MODULE_NAME[$i]} patched successfully with resolved version ${T_VERSION[$i]}"
                continue
            fi
        fi

        error "Failed to patch ${T_MODULE_NAME[$i]}"
        exit 1
    done
}

# Second pass: the private .rvp bundle, applied to the Morphe output with the
# stock ReVanced CLI. -b because the APK now carries our signature.
apply_extra_patches() {
    [ -n "${EXTRA_PATCHES:-}" ] || return 0
    status "Applying the private patch bundle..."
    for i in "${!T_PACKAGE[@]}"; do
        local apk="${T_MODULE_PATH[$i]}/${T_MODULE_ID[$i]}.apk"
        local out="${apk%.apk}-extra.apk"
        if java -jar "$RVCLI" patch --purge \
            -o "$out" \
            -p "$EXTRA_PATCHES" -b \
            --keystore="$KEYSTORE" \
            --keystore-password="$KEYSTORE_PASSWORD" \
            --keystore-entry-alias="$KEYSTORE_ALIAS" \
            --keystore-entry-password="$KEYSTORE_ENTRY_PASSWORD" \
            --force \
            "$apk" >>"$LOGFILE" 2>&1 && [ -f "$out" ]; then
            mv "$out" "$apk"
            success "Private patches applied to ${T_MODULE_NAME[$i]}"
        else
            rm -f "$out"
            error "Failed to apply the private patches to ${T_MODULE_NAME[$i]}"
            tail -n 40 "$LOGFILE"
            exit 1
        fi
    done
}

# The patched APK is installable as-is; publish it next to the Magisk module.
create_noroot_apks() {
    status "Publishing standalone APKs..."
    for i in "${!T_PACKAGE[@]}"; do
        cp "${T_MODULE_PATH[$i]}/${T_MODULE_ID[$i]}.apk" "$CURDIR/${T_NAME[$i]}${APK_SUFFIX}.apk"
        success "Created ${T_NAME[$i]}${APK_SUFFIX}.apk"
    done
}

trap cleanup_on_exit EXIT

# Initialize logging
rm -f "$LOGFILE"
echo "========================================" > "$LOGFILE"
echo "ReVanced Build Script - $(date)" >> "$LOGFILE"
echo "========================================" >> "$LOGFILE"
success "Build log: $LOGFILE"

if [ "$MODE" = "cleanup-old-releases" ]; then
    init_runtime_deps
    init_auth_env
    prune_old_releases_and_tags
    exit 0
fi

# Get latest version
init_runtime_deps
init_auth_env
init_java_env
init_keystore_env

# Clone Tools
clone_tools

# Patch Tools
patch_tools

# Build Tools
build_tools
download_extra_patches
ensure_bks_keystore

# Cleanup
prepare_workspace

resolve_supported_versions
download_base_apks
patch_main_apks
apply_extra_patches
prepare_release_meta
create_release_if_needed
create_module_zips
create_noroot_apks
generate_update_json_files
upload_release_assets_if_needed
notify_telegram
