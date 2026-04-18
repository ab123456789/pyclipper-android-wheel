#!/usr/bin/env bash
set -euo pipefail
python3 -V
pip3 --version
ROOT="$PWD/.work"
mkdir -p "$ROOT/src" dist
python3 -m pip install -U pip wheel setuptools build packaging Cython
python3 -m pip download --no-binary=:all: --no-deps pyclipper -d "$ROOT/src"
export ANDROID_NDK="${ANDROID_NDK:?}"
TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64"
export TARGET=aarch64-linux-android
export API="${ANDROID_API:-24}"
export CC="$TOOLCHAIN/bin/${TARGET}${API}-clang"
export CXX="$TOOLCHAIN/bin/${TARGET}${API}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export CFLAGS="-fPIC"
export CXXFLAGS="-fPIC"
export PYLIB="$ROOT/python-runtime/libpython3.13.so"
export LDFLAGS="-L$(dirname \"$PYLIB\") -lpython3.13"
cd "$ROOT"
rm -rf pyclipper-src
mkdir -p pyclipper-src "$ROOT/python-runtime"
curl -fsSL "https://github.com/ab123456789/opencv-android-headless/releases/download/python-runtime-py313-android-aarch64/libpython3.13.so" -o "$PYLIB"
test -s "$PYLIB"
file "$PYLIB"
SRC=$(find "$ROOT/src" -maxdepth 1 -type f \( -name 'pyclipper*.tar.gz' -o -name 'pyclipper*.zip' \) | head -n1)
test -n "$SRC"
case "$SRC" in
  *.zip) unzip -q "$SRC" -d pyclipper-src ;;
  *) tar -xzf "$SRC" -C pyclipper-src ;;
esac
cd pyclipper-src/pyclipper-*
export LDSHARED="$CXX -shared $LDFLAGS"
python3 setup.py bdist_wheel --plat-name android_24_arm64_v8a -d "$GITHUB_WORKSPACE/dist-host"
mkdir -p "$GITHUB_WORKSPACE/dist" "$PWD/wheel-fix"
WHL=$(find "$GITHUB_WORKSPACE/dist-host" -maxdepth 1 -type f -name '*android_24_arm64_v8a.whl' -print -quit)
test -n "$WHL"
python3 - <<PY
import pathlib, shutil, zipfile
src = pathlib.Path('$WHL')
root = pathlib.Path('$PWD/wheel-fix')
if root.exists():
    shutil.rmtree(root)
root.mkdir(parents=True)
with zipfile.ZipFile(src) as z:
    z.extractall(root)
for p in root.rglob('*.so'):
    if 'x86_64-linux-gnu' in p.name:
        p.rename(p.with_name(p.name.replace('x86_64-linux-gnu', 'aarch64-linux-android')))
out = pathlib.Path('$GITHUB_WORKSPACE/dist') / src.name
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for p in root.rglob('*'):
        if p.is_file():
            z.write(p, p.relative_to(root))
print(out)
PY
ls -lah "$GITHUB_WORKSPACE/dist"
test -n "$(find "$GITHUB_WORKSPACE/dist" -maxdepth 1 -type f -name '*android_24_arm64_v8a.whl' -print -quit)"
