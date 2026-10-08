# quiche-zig

Zig bindings to [quiche](https://github.com/cloudflare/quiche) — Cloudflare's
QUIC + HTTP/3 implementation. A single `quiche` module exposes both quiche's C
API and the bundled BoringSSL headers (`SSL_*`, `EVP_*`, ...). The static library
contains BoringSSL inlined, so no separate ssl/crypto link step is needed.

Currently builds quiche `0.30.0` from the upstream crate, using its locked
`boring-sys` `5.2.0` dependency for BoringSSL. The Zig dependency on `boring-sys`
supplies matching C headers and must track quiche's `Cargo.lock`.

## Requirements

- Zig 0.16+
- Rust 1.88+ (`cargo`) on `PATH`, CMake 3.22+, and libclang for
  BoringSSL's Rust bindings. For cross-compiling, install the
  matching `rustup target`.

The build uses Zig's C/C++ compiler and linker for BoringSSL and Cargo, including
cross-compilation, so they share the same C++ runtime as the consuming Zig code.

## Use

In your `build.zig`:

```zig
const dep = b.dependency("quiche", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("quiche", dep.module("quiche"));
```

In Zig source:

```zig
const std = @import("std");
const quiche = @import("quiche");

pub fn main() void {
    std.debug.print("quiche {s}\n", .{quiche.quiche_version()});
}
```
