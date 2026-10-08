#!/bin/sh
set -eu

if [ "${1-}" = --driver ]; then
  mode=$2
  shift 2
  skip_target=0
  for arg; do
    shift
    if [ "$skip_target" = 1 ]; then
      skip_target=0
      continue
    fi
    case "$arg" in
      # Zig's target already includes the ABI and minimum OS version.
      -target | --target) skip_target=1; continue ;;
      --target=* | -mmacosx-version-min=*) continue ;;
      # Cargo also links an unused cdylib; Zig's Darwin linker needs these adjustments.
      -liconv) continue ;;
      -Wl,*-compatibility_version,*) arg=$(printf '%s' "$arg" | sed -E 's/(-compatibility_version,[0-9]+)$/\1.0.0/') ;;
    esac
    set -- "$@" "$arg"
  done
  exec "$QUICHE_ZIG" "$mode" -target "$QUICHE_ZIG_TARGET" "$@"
fi

QUICHE_ZIG=$1
QUICHE_ZIG_TARGET=$2
rust_target=$3
cargo_target=$4
shift 4
QUICHE_ZIG_DRIVER=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
export QUICHE_ZIG QUICHE_ZIG_TARGET QUICHE_ZIG_DRIVER

toolchain="$cargo_target/toolchain"
mkdir -p "$toolchain"
for mode in cc c++; do
  printf '#!/bin/sh\nexec sh "$QUICHE_ZIG_DRIVER" --driver %s "$@"\n' "$mode" > "$toolchain/$rust_target-$mode"
  chmod +x "$toolchain/$rust_target-$mode"
done
for mode in ar ranlib; do
  printf '#!/bin/sh\nexec "$QUICHE_ZIG" %s "$@"\n' "$mode" > "$toolchain/$rust_target-$mode"
  chmod +x "$toolchain/$rust_target-$mode"
done
case "$rust_target" in
  *-apple-darwin)
    printf '#!/bin/sh\necho "install_name_tool is unavailable when cross-building" >&2\nexit 1\n' > "$toolchain/$rust_target-install_name_tool"
    chmod +x "$toolchain/$rust_target-install_name_tool"
    ;;
esac
target_var=$(printf '%s' "$rust_target" | tr '-' '_')
linker_var=$(printf '%s' "$target_var" | tr '[:lower:]' '[:upper:]')
export "CC_$target_var=$toolchain/$rust_target-cc" "CXX_$target_var=$toolchain/$rust_target-c++"
export "AR_$target_var=$toolchain/$rust_target-ar" "RANLIB_$target_var=$toolchain/$rust_target-ranlib"
export "CARGO_TARGET_${linker_var}_LINKER=$toolchain/$rust_target-cc"
# Keep Cargo's BoringSSL linkage consistent with Zig's C++ runtime.
export BORING_BSSL_RUST_CPPLIB=c++
# Bindgen runs on the host, but must parse the target's libc headers too.
"$QUICHE_ZIG" cc -target "$QUICHE_ZIG_TARGET" -E -x c -v /dev/null > /dev/null 2> "$toolchain/includes.txt"
includes=$(awk '/^#include <\.\.\.> search starts here:/ { active=1; next } /^End of search list\./ { active=0 } active { sub(/^ /, ""); printf " -isystem \"%s\"", $0 }' "$toolchain/includes.txt")
export "BINDGEN_EXTRA_CLANG_ARGS_$target_var=-nostdinc$includes"
export PATH="$toolchain:$PATH"
exec cargo "$@" --target-dir "$cargo_target"
