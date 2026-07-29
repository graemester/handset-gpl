#!/bin/sh
# build-qemu-ios.sh — Stripped build script for QEMU iOS framework with TCTI
# Derived from UTM's build_dependencies.sh, reduced to minimum dependencies.
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ---- Knobs ----
PLATFORM="ios-tci"
ARCH="arm64"
CPU="aarch64"
CHOST="$CPU-apple-darwin"
IOS_SDKMINVER="14.0"
SDKMINVER="$IOS_SDKMINVER"
SDK="iphoneos"
CFLAGS_TARGET="-target $ARCH-apple-ios$SDKMINVER"

command -v realpath >/dev/null 2>&1 || realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

# ---- Paths ----
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
# Default build dirs to /tmp for better I/O on USB-attached project volumes.
# Override with BUILD_DIR=/path SYSROOT_DIR=/path if desired.
BUILD_DIR="${BUILD_DIR:-/tmp/shellphone-build-iOS-TCI-$ARCH}"
SYSROOT_DIR="${SYSROOT_DIR:-/tmp/shellphone-sysroot-iOS-TCI-$ARCH}"
PATCHES_DIR="$BASEDIR/../ShellPhone/patches"
QEMU_DIR="$BASEDIR/qemu-10.0.2-utm"

[ -d "$BUILD_DIR" ] || mkdir -p "$BUILD_DIR"
[ -d "$SYSROOT_DIR" ] || mkdir -p "$SYSROOT_DIR"
PREFIX="$(realpath "$SYSROOT_DIR")"

# ---- SDK ----
SDKVERSION=$(xcrun --sdk $SDK --show-sdk-version)
SDKROOT=$(xcrun --sdk $SDK --show-sdk-path)

# ---- NCPU ----
NCPU="$(sysctl -n hw.ncpu)"

# ---- Toolchain ----
CC="$(xcrun --sdk $SDK --find gcc) $CFLAGS_TARGET"
CPP="$(xcrun --sdk $SDK --find gcc) -E"
CXX="$(xcrun --sdk $SDK --find g++)"
OBJCC="$(xcrun --sdk $SDK --find clang)"
LD="$(xcrun --sdk $SDK --find ld)"
AR="$(xcrun --sdk $SDK --find ar)"
NM="$(xcrun --sdk $SDK --find nm)"
RANLIB="$(xcrun --sdk $SDK --find ranlib)"
STRIP="$(xcrun --sdk $SDK --find strip)"
export CC CPP CXX OBJCC LD AR NM RANLIB STRIP PREFIX CHOST ARCH SDK SDKMINVER NCPU

# ---- Flags ----
CFLAGS="-arch $ARCH -isysroot $SDKROOT -I$PREFIX/include -F$PREFIX/Frameworks"
CPPFLAGS="-arch $ARCH -isysroot $SDKROOT -I$PREFIX/include -F$PREFIX/Frameworks $CFLAGS_TARGET"
CXXFLAGS="-arch $ARCH -isysroot $SDKROOT -I$PREFIX/include -F$PREFIX/Frameworks $CFLAGS_TARGET"
OBJCFLAGS="-arch $ARCH -isysroot $SDKROOT -I$PREFIX/include -F$PREFIX/Frameworks $CFLAGS_TARGET"
LDFLAGS="-arch $ARCH -isysroot $SDKROOT -L$PREFIX/lib -F$PREFIX/Frameworks $CFLAGS_TARGET"
export CFLAGS CPPFLAGS CXXFLAGS OBJCFLAGS LDFLAGS

# ---- Source URLs ----
PKG_CONFIG_SRC="https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
FFI_SRC="https://github.com/libffi/libffi/releases/download/v3.5.0/libffi-3.5.0.tar.gz"
ICONV_SRC="http://ftp.gnu.org/gnu/libiconv/libiconv-1.16.tar.gz"
GETTEXT_SRC="http://ftp.gnu.org/gnu/gettext/gettext-0.22.5.tar.gz"
GLIB_SRC="https://download.gnome.org/sources/glib/2.83/glib-2.83.0.tar.xz"
PIXMAN_SRC="https://www.cairographics.org/releases/pixman-0.38.0.tar.gz"
SLIRP_SRC="https://github.com/utmapp/libslirp/releases/download/v4.9.1-release-mirror/libslirp-v4.9.1.tar.gz"
ZSTD_SRC="https://github.com/facebook/zstd/releases/download/v1.5.2/zstd-1.5.2.tar.gz"
LIBUCONTEXT_REPO="https://github.com/utmapp/libucontext.git"
LIBUCONTEXT_COMMIT="9b1d8f01a6e99166f9808c79966abe10786de8b6"

# ---- Helper functions ----
download () {
    URL=$1
    FILE="$(basename $URL)"
    NAME="${FILE%.tar.*}"
    TARGET="$BUILD_DIR/$FILE"
    DIR="$BUILD_DIR/$NAME"
    PATCH="$PATCHES_DIR/${NAME}.patch"
    DATA="$PATCHES_DIR/data/${NAME}"
    if [ -f "$TARGET" ]; then
        echo "${GREEN}$TARGET already downloaded!${NC}"
    else
        echo "${GREEN}Downloading ${URL}${NC}"
        curl -L -O "$URL"
        mv "$FILE" "$TARGET"
    fi
    if [ -d "$DIR" ]; then
        rm -rf "$DIR"
    fi
    echo "${GREEN}Unpacking ${NAME}...${NC}"
    tar -xf "$TARGET" -C "$BUILD_DIR"
    if [ -f "$PATCH" ]; then
        echo "${GREEN}Patching ${NAME}...${NC}"
        patch -d "$DIR" -p1 < "$PATCH"
    fi
    if [ -d "$DATA" ]; then
        echo "${GREEN}Patching data ${NAME}...${NC}"
        cp -r "$DATA/" "$DIR"
    fi
}

clone () {
    REPO="$1"
    COMMIT="$2"
    NAME="$(basename $REPO)"
    DIR="$BUILD_DIR/$NAME"
    if [ -d "$DIR" ]; then
        echo "${GREEN}$DIR already downloaded!${NC}"
    else
        echo "${GREEN}Cloning ${REPO}...${NC}"
        git clone --filter=tree:0 --no-checkout "$REPO" "$DIR"
    fi
    git -C "$DIR" checkout "$COMMIT"
}

build () {
    if [ -d "$1" ]; then
        DIR="$1"
        NAME="$(basename "$DIR")"
    else
        URL=$1
        FILE="$(basename $URL)"
        NAME="${FILE%.tar.*}"
        DIR="$BUILD_DIR/$NAME"
    fi
    shift 1
    pwd="$(pwd)"
    cd "$DIR"
    echo "${GREEN}Configuring ${NAME}...${NC}"
    ./configure --prefix="$PREFIX" --host="$CHOST" "$@"
    echo "${GREEN}Building ${NAME}...${NC}"
    make -j$NCPU
    echo "${GREEN}Installing ${NAME}...${NC}"
    make install
    cd "$pwd"
}

meson_quote() {
    echo "'$(echo $* | sed "s/ /','/g")'"
}

generate_meson_cross() {
    cross="$1"
    system="$2"
    echo "# Automatically generated - do not modify" > $cross
    echo "[properties]" >> $cross
    echo "needs_exe_wrapper = true" >> $cross
    echo "[built-in options]" >> $cross
    echo "c_args = [${CFLAGS:+$(meson_quote $CFLAGS)}]" >> $cross
    echo "cpp_args = [${CXXFLAGS:+$(meson_quote $CXXFLAGS)}]" >> $cross
    echo "objc_args = [${OBJCFLAGS:+$(meson_quote $OBJCFLAGS)}]" >> $cross
    echo "c_link_args = [${LDFLAGS:+$(meson_quote $LDFLAGS)}]" >> $cross
    echo "cpp_link_args = [${LDFLAGS:+$(meson_quote $LDFLAGS)}]" >> $cross
    echo "objc_link_args = [${LDFLAGS:+$(meson_quote $LDFLAGS)}]" >> $cross
    echo "[binaries]" >> $cross
    echo "c = [$(meson_quote $CC)]" >> $cross
    echo "cpp = [$(meson_quote $CXX)]" >> $cross
    echo "objc = [$(meson_quote $OBJCC)]" >> $cross
    echo "ar = [$(meson_quote $AR)]" >> $cross
    echo "nm = [$(meson_quote $NM)]" >> $cross
    echo "pkgconfig = ['$PREFIX/host/bin/pkg-config']" >> $cross
    echo "ranlib = [$(meson_quote $RANLIB)]" >> $cross
    echo "strip = [$(meson_quote $STRIP), '-x']" >> $cross
    echo "python = ['$(which python3)']" >> $cross
    echo "glib-mkenums = ['$(which glib-mkenums)']" >> $cross
    echo "glib-compile-resources = ['$(which glib-compile-resources)']" >> $cross
    echo "[host_machine]" >> $cross
    if [ "$system" == "auto" ]; then
        echo "system = 'ios'" >> $cross
    else
        echo "system = '$system'" >> $cross
    fi
    echo "cpu_family = 'aarch64'" >> $cross
    echo "cpu = 'arm64'" >> $cross
    echo "endian = 'little'" >> $cross
}

meson_cross_build () {
    CROSS="$1"
    SRCDIR="$2"
    shift 2
    FILE="$(basename $SRCDIR)"
    NAME="${FILE%.tar.*}"
    case $SRCDIR in
    http* | ftp* )
        SRCDIR="$BUILD_DIR/$NAME"
        ;;
    esac
    MESON_CROSS="$(realpath "$BUILD_DIR")/meson-$CROSS.cross"
    if [ ! -f "$MESON_CROSS" ]; then
        generate_meson_cross "$MESON_CROSS" "$CROSS"
    fi
    pwd="$(pwd)"
    cd "$SRCDIR"
    rm -rf utm_build
    echo "${GREEN}Configuring ${NAME}...${NC}"
    meson setup utm_build --prefix="$PREFIX" --buildtype=release --cross-file "$MESON_CROSS" "$@"
    echo "${GREEN}Building ${NAME}...${NC}"
    meson compile -C utm_build -j $NCPU
    echo "${GREEN}Installing ${NAME}...${NC}"
    meson install -C utm_build
    cd "$pwd"
}

meson_build () {
    meson_cross_build auto "$@"
}

meson_darwin_build () {
    meson_cross_build darwin "$@"
}

# Build pkg-config as a HOST tool (runs on the Mac during the build).
# Must use native macOS compiler, NOT the iOS cross-compilation toolchain.
# Uses env -i to strip iOS vars, preserving only essential env vars.
build_pkg_config() {
    FILE="$(basename $PKG_CONFIG_SRC)"
    NAME="${FILE%.tar.*}"
    DIR="$BUILD_DIR/$NAME"
    pwd="$(pwd)"

    # Save iOS cross-compilation vars
    SAVE_CC="$CC"; SAVE_CPP="$CPP"; SAVE_CXX="$CXX"
    SAVE_CFLAGS="$CFLAGS"; SAVE_CPPFLAGS="$CPPFLAGS"
    SAVE_CXXFLAGS="$CXXFLAGS"; SAVE_OBJCFLAGS="$OBJCFLAGS"
    SAVE_LDFLAGS="$LDFLAGS"; SAVE_LD="$LD"

    # Use native macOS compiler for host tool
    unset CC CPP CXX LD OBJCFLAGS
    export CFLAGS="-Wno-error=int-conversion"
    export CPPFLAGS=""
    export CXXFLAGS=""
    export LDFLAGS=""

    cd "$DIR"
    echo "${GREEN}Configuring ${NAME} (host tool, native compiler)...${NC}"
    ./configure --prefix="$PREFIX" --bindir="$PREFIX/host/bin" --with-internal-glib
    echo "${GREEN}Building ${NAME}...${NC}"
    make -j$NCPU
    echo "${GREEN}Installing ${NAME}...${NC}"
    make install
    cd "$pwd"

    # Restore iOS cross-compilation vars
    export CC="$SAVE_CC"; export CPP="$SAVE_CPP"; export CXX="$SAVE_CXX"
    export CFLAGS="$SAVE_CFLAGS"; export CPPFLAGS="$SAVE_CPPFLAGS"
    export CXXFLAGS="$SAVE_CXXFLAGS"; export OBJCFLAGS="$SAVE_OBJCFLAGS"
    export LDFLAGS="$SAVE_LDFLAGS"; export LD="$SAVE_LD"

    export PATH="$PREFIX/host/bin:$PATH"
    export PKG_CONFIG="$PREFIX/host/bin/pkg-config"
}

copy_private_headers() {
    MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
    IOKIT_HEADERS_PATH="$MACOS_SDK_PATH/System/Library/Frameworks/IOKit.framework/Headers"
    OSTYPES_HEADERS_PATH="$MACOS_SDK_PATH/usr/include/libkern"
    OUTPUT_INCLUDES="$PREFIX/include"
    mkdir -p "$OUTPUT_INCLUDES"
    cp -r "$IOKIT_HEADERS_PATH" "$OUTPUT_INCLUDES/IOKit"
    rm -f "$OUTPUT_INCLUDES/IOKit/storage/IOMedia.h"
    LC_ALL=C sed -i '' -e 's/#if KERNEL_USER32/#if 0/g' $(find "$OUTPUT_INCLUDES/IOKit" -type f)
    LC_ALL=C sed -i '' -e 's/#if !KERNEL_USER32/#if 1/g' $(find "$OUTPUT_INCLUDES/IOKit" -type f)
    LC_ALL=C sed -i '' -e 's/#if KERNEL/#if 0/g' $(find "$OUTPUT_INCLUDES/IOKit" -type f)
    LC_ALL=C sed -i '' -e 's/#if !KERNEL/#if 1/g' $(find "$OUTPUT_INCLUDES/IOKit" -type f)
    LC_ALL=C sed -i '' -e 's/__UNAVAILABLE_PUBLIC_IOS;/;/g' $(find "$OUTPUT_INCLUDES/IOKit" -type f)
    mkdir -p "$OUTPUT_INCLUDES/libkern"
    cp -r "$OSTYPES_HEADERS_PATH/OSTypes.h" "$OUTPUT_INCLUDES/libkern/OSTypes.h"
}

fixup () {
    FILE=$1
    BASE=$(basename "$FILE")
    BASEFILENAME=${BASE%.*}
    LIBNAME=${BASEFILENAME#lib*}
    BUNDLE_ID="com.shellphone.${LIBNAME//_/-}"
    FRAMEWORKNAME="$LIBNAME.framework"
    FRAMEWORKPATH="$PREFIX/Frameworks/$FRAMEWORKNAME"
    NEWFILE="$FRAMEWORKPATH/$LIBNAME"
    LIST=$(otool -L "$FILE" | tail -n +2 | cut -d ' ' -f 1 | awk '{$1=$1};1')
    OLDIFS=$IFS
    IFS=$'\n'
    echo "${GREEN}Fixing up $FILE...${NC}"
    mkdir -p "$FRAMEWORKPATH"
    cp -a "$FILE" "$NEWFILE"
    /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $LIBNAME" "$FRAMEWORKPATH/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$FRAMEWORKPATH/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $SDKMINVER" "$FRAMEWORKPATH/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$FRAMEWORKPATH/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$FRAMEWORKPATH/Info.plist"
    newname="@rpath/$FRAMEWORKNAME/$LIBNAME"
    install_name_tool -id "$newname" "$NEWFILE"
    for g in $LIST
    do
        base=$(basename "$g")
        basefilename=${base%.*}
        libname=${basefilename#lib*}
        dir=$(dirname "$g")
        if [ "$dir" == "$PREFIX/lib" ] || [ "$dir" == "/private$PREFIX/lib" ] || [ "$dir" == "@rpath" ]; then
            newname="@rpath/$libname.framework/$libname"
            install_name_tool -change "$g" "$newname" "$NEWFILE"
        fi
    done
    IFS=$OLDIFS
}

fixup_all () {
    OLDIFS=$IFS
    IFS=$'\n'
    FILES=$(find "$SYSROOT_DIR/lib" -type f -maxdepth 1 -name "*.dylib")
    for f in $FILES
    do
        fixup $f
    done
    IFS=$OLDIFS
}

# ==== MAIN BUILD ====

echo "${GREEN}Starting ShellPhone QEMU iOS build [${NCPU} jobs]${NC}"
echo "  SDK: $SDKROOT"
echo "  PREFIX: $PREFIX"
echo "  BUILD_DIR: $BUILD_DIR"
echo "  QEMU: $QEMU_DIR"

# Clean sysroot (skip if RESUME=1 to avoid rebuilding completed steps)
if [ "${RESUME:-0}" != "1" ]; then
    rm -rf "$PREFIX/"*
fi
mkdir -p "$PREFIX/Frameworks"

# Step 0: Private headers (needed by QEMU)
echo ""
echo "=== Step 0: Private headers ==="
copy_private_headers

# Step 1: pkg-config (host tool, native compiler)
echo ""
echo "=== Step 1: pkg-config ==="
download $PKG_CONFIG_SRC
build_pkg_config

# Step 2: libffi
echo ""
echo "=== Step 2: libffi ==="
download $FFI_SRC
build $FFI_SRC

# Step 3: libiconv
echo ""
echo "=== Step 3: libiconv ==="
download $ICONV_SRC
build $ICONV_SRC

# Step 4: gettext
echo ""
echo "=== Step 4: gettext ==="
download $GETTEXT_SRC
gl_cv_onwards_func_strchrnul=future build $GETTEXT_SRC --disable-java

# Step 5: glib (meson)
echo ""
echo "=== Step 5: glib ==="
download $GLIB_SRC
meson_build $GLIB_SRC -Dtests=false -Ddtrace=disabled

# Step 6: pixman
echo ""
echo "=== Step 6: pixman ==="
download $PIXMAN_SRC
build $PIXMAN_SRC

# Step 7: libslirp (meson, needs glib)
echo ""
echo "=== Step 7: libslirp ==="
download $SLIRP_SRC
meson_darwin_build $SLIRP_SRC

# Step 8: libucontext (meson)
echo ""
echo "=== Step 8: libucontext ==="
clone $LIBUCONTEXT_REPO $LIBUCONTEXT_COMMIT
meson_build $LIBUCONTEXT_REPO -Ddefault_library=static -Dfreestanding=true

# Step 9: zstd (meson)
echo ""
echo "=== Step 9: zstd ==="
download $ZSTD_SRC
ZSTD_BASENAME="$(basename $ZSTD_SRC)"
meson_build "$BUILD_DIR/${ZSTD_BASENAME%.tar.*}/build/meson"

# Step 10: QEMU
echo ""
echo "=== Step 10: QEMU ==="
QEMU_DIR="$(realpath "$QEMU_DIR")"
build "$QEMU_DIR" \
    --cross-prefix="" \
    --enable-shared-lib \
    --disable-cocoa \
    --disable-coreaudio \
    --disable-sdl \
    --disable-slirp-smbd \
    --enable-ucontext \
    --with-coroutine=libucontext \
    --disable-hvf \
    --enable-tcg-threaded-interpreter \
    --enable-virtfs \
    --target-list=aarch64-softmmu \
    --disable-install-blobs \
    --extra-cflags=-Wno-unused-command-line-argument \
    "--extra-ldflags=-Wl,-no_deduplicate" \
    "--extra-ldflags=-Wl,-random_uuid" \
    "--extra-ldflags=-Wl,-no_compact_unwind" \
    --disable-debug-info

# Step 11: fixup dylibs → frameworks
echo ""
echo "=== Step 11: Framework fixup ==="
fixup_all

# Step 12: Copy frameworks back to project directory
echo ""
echo "=== Step 12: Copy frameworks to project ==="
PROJECT_FW_DIR="$BASEDIR/sysroot-iOS-TCI-$ARCH/Frameworks"
mkdir -p "$PROJECT_FW_DIR"
cp -R "$PREFIX/Frameworks/"* "$PROJECT_FW_DIR/" 2>/dev/null && \
    echo "  ✅ Copied to $PROJECT_FW_DIR" || \
    echo "  ⚠️  Copy failed — frameworks remain at $PREFIX/Frameworks/"

echo ""
echo "${GREEN}=== BUILD COMPLETE ===${NC}"
echo "Frameworks in: $PREFIX/Frameworks/"
echo "Also copied to: $PROJECT_FW_DIR"
ls -la "$PREFIX/Frameworks/"
