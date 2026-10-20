#!/bin/bash
set -euo pipefail
shopt -s nullglob

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

THEOS="${THEOS:-/opt/theos}"
export THEOS
export PATH="$THEOS/bin:$PATH"

# Theos 不支持含空格的路径: 在无空格副本中构建(同步源文件,不带宿主元数据)
work_root="${TMPDIR:-/tmp}/DMKJNoSplash-work"
rm -rf "$work_root"
mkdir -p "$work_root"
cp "$repo_root/Makefile" "$repo_root/control" "$repo_root/Tweak.xm" \
    "$repo_root/DMKJNoSplash.plist" "$work_root/"
cd "$work_root"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$work_root/.theos/module-cache}"

display_name="DMKJNoSplash"
version="$(awk -F': ' '$1 == "Version" { print $2; exit }' control)"
out_dir="$repo_root/out"
lock_dir="${TMPDIR:-/tmp}/$(basename "$repo_root").build.lock"

while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 2
done
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

clean_host_metadata() {
    local target_path
    for target_path in "$@"; do
        [ -e "$target_path" ] || continue
        find "$target_path" -type f \( -name '.DS_Store' -o -name '._*' \) -exec rm -f {} +
        find "$target_path" -name '__MACOSX' -type d -prune -exec rm -rf {} +
    done
}

sanitize_deb() {
    local deb="$1"
    local unpack_dir
    unpack_dir="$(mktemp -d)"
    dpkg-deb -R "$deb" "$unpack_dir"
    clean_host_metadata "$unpack_dir"
    # 权限位修正(规范 §10.6): plist/控制 644, dylib/可执行 755, 目录 755;归属由 --root-owner-group 统一 root
    find "$unpack_dir" -type f -name '*.plist' -exec chmod 644 {} +
    find "$unpack_dir" -type f -name '*.dylib' -exec chmod 755 {} +
    find "$unpack_dir/DEBIAN" -type f -exec chmod 644 {} + 2>/dev/null || true
    find "$unpack_dir" -type d -exec chmod 755 {} +
    dpkg-deb -b --root-owner-group "$unpack_dir" "$deb" >/dev/null
    rm -rf "$unpack_dir"
}

assert_no_host_metadata() {
    local deb="$1"
    local unpack_dir
    unpack_dir="$(mktemp -d)"
    dpkg-deb -R "$deb" "$unpack_dir"
    if find "$unpack_dir" -name '.DS_Store' -o -name '._*' -o -name '__MACOSX' | grep -q .; then
        echo "Host metadata found in $deb" >&2
        find "$unpack_dir" -name '.DS_Store' -o -name '._*' -o -name '__MACOSX' >&2
        rm -rf "$unpack_dir"
        exit 1
    fi
    rm -rf "$unpack_dir"
}

copy_single_deb() {
    local package_dir="$1"
    local scheme="$2"
    local short_arch="$3"
    local expected_arch="$4"
    local dest="$out_dir/${display_name}_${version}_${scheme}_${short_arch}.deb"
    local debs=("$package_dir"/*.deb)

    if [ "${#debs[@]}" -ne 1 ]; then
        echo "Expected exactly one deb in $package_dir, got ${#debs[@]}" >&2
        printf '%s\n' "${debs[@]}" >&2
        exit 1
    fi

    cp "${debs[0]}" "$dest"
    sanitize_deb "$dest"

    local actual_version actual_arch
    actual_version="$(dpkg-deb -f "$dest" Version)"
    actual_arch="$(dpkg-deb -f "$dest" Architecture)"

    if [ "$actual_version" != "$version" ] || [ "$actual_arch" != "$expected_arch" ]; then
        echo "Package header mismatch for $dest" >&2
        dpkg-deb -f "$dest" Package Version Architecture >&2
        exit 1
    fi

    assert_no_host_metadata "$dest"
    dpkg-deb -f "$dest" Package Version Architecture
}

verify_roots() {
    local deb="$1"
    local scheme="$2"
    local listing
    listing="$(dpkg-deb -c "$deb")"

    case "$scheme" in
        rootful)
            if printf '%s\n' "$listing" | grep -q 'var/jb/'; then
                echo "rootful package unexpectedly contains var/jb" >&2
                exit 1
            fi
            ;;
        rootless)
            if ! printf '%s\n' "$listing" | grep -q 'var/jb/Library/MobileSubstrate/DynamicLibraries/'; then
                echo "rootless package does not contain expected var/jb install root" >&2
                exit 1
            fi
            ;;
        roothide)
            if printf '%s\n' "$listing" | grep -q 'var/jb/'; then
                echo "roothide package unexpectedly exposes var/jb install root" >&2
                exit 1
            fi
            ;;
    esac
}

build_scheme() {
    local scheme="$1"
    local package_scheme="$2"
    local short_arch="$3"
    local expected_arch="$4"
    local archs="$5"
    local package_dir="$work_root/packages/$scheme"
    local dest="$out_dir/${display_name}_${version}_${scheme}_${short_arch}.deb"

    rm -rf "$package_dir"
    mkdir -p "$package_dir" "$out_dir" "$CLANG_MODULE_CACHE_PATH"
    clean_host_metadata "$work_root"

    make clean FINALPACKAGE=1 THEOS_PACKAGE_SCHEME="$package_scheme" THEOS_PACKAGE_DIR="$package_dir" ARCHS="$archs"
    make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME="$package_scheme" THEOS_PACKAGE_DIR="$package_dir" ARCHS="$archs"

    copy_single_deb "$package_dir" "$scheme" "$short_arch" "$expected_arch"
    verify_roots "$dest" "$scheme"
}

rm -rf "$out_dir"
mkdir -p "$out_dir"

build_scheme rootful "" arm iphoneos-arm "arm64 arm64e"
build_scheme rootless rootless arm64 iphoneos-arm64 "arm64 arm64e"
build_scheme roothide roothide arm64e iphoneos-arm64e "arm64e"

echo "Built packages:"
ls -1 "$out_dir"
