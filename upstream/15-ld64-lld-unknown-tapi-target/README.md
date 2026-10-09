# [lld] ld64.lld refuses a .tbd that names a target it does not know

At `llvmorg-23.1.2`, `ld64.lld` fails to link against any `.tbd` stub whose
`targets` list holds a target the LLVM of that release does not know. The
macOS 27 SDK's stubs name `arm64e.x1-macos` and `arm64e.x1-maccatalyst`,
which LLVM 23.1.2 predates, so every link against `libSystem` in that SDK
fails, and the target is unusable there. Teaching LLVM each new target
fixes one SDK; the next SDK that names a target the linker's release
predates fails the same way.

## Reproduce

`min.c` (any object does; the bug is in reading the `.tbd`):

```c
int main(void) { return 0; }
```

`known.tbd` has targets LLVM knows, `unknown.tbd` adds `unknown-macos`.
`unknown` is LLVM's own name for an architecture it does not know, so no
release of LLVM will know this target, and the reproducer does not depend
on which targets the linker at hand has learned (the reproduction is for
`x86_64`, as the check's first version was, and every pinned LLVM has both
targets' backends; the
target the macOS 27 SDK actually adds is `arm64e.x1-macos`, and the same
error stops an arm64 link):

```yaml
--- !tapi-tbd
tbd-version:     4
targets:         [ x86_64-macos, arm64-macos, unknown-macos ]
install-name:    '/usr/lib/libSystem.B.dylib'
current-version: 1.0
exports:
  - targets:         [ x86_64-macos, arm64-macos, unknown-macos ]
    symbols:         [ _exit ]
...
```

```
$ clang --target=x86_64-apple-macosx14.0 -c min.c -o min.o
$ ld64.lld -arch x86_64 -platform_version macos 14.0 14.0 min.o known.tbd -o a.out
$ ld64.lld -arch x86_64 -platform_version macos 14.0 14.0 min.o unknown.tbd -o a.out
ld64.lld: error: could not load TAPI file at unknown.tbd: malformed file
unknown.tbd:3:47: error: unknown target
targets:         [ x86_64-macos, arm64-macos, unknown-macos ]
                                              ^~~~~~~~~~~~~~
```

`known.tbd` links (exit 0); `unknown.tbd` fails (exit 1). Expected: the
linker ignores a target it does not know, as it ignores a target for
another platform, and links the file for the architectures it does know.

## Cause

`TextAPIReader` takes a `SkipUnknownTriples` option and skips a target it
cannot parse when it is set (`llvm/lib/TextAPI/TextStub.cpp:402-405`, and
`:317` for the target traits). It defaults to false
(`llvm/include/llvm/TextAPI/TextAPIReader.h:41`), and `ld64.lld` never
sets it: the one place that reads a `.tbd` (`macho::loadDylib`,
`lld/MachO/DriverUtils.cpp:270` at 23.1.2, `:267` on main) passes the
buffer alone. So a target the pinned LLVM does not know is a hard error,
and the toolchain cannot read a stub from a newer SDK. LLVM's own tests
read such files with the option on
(`llvm/unittests/TextAPI/TextStubV4Tests.cpp:1191`), so the mechanism
exists and is exercised.

## Proposed fix

`ld64.lld` should read a `.tbd` with `SkipUnknownTriples = true` (or expose
a flag for it, defaulting to true when the input is a stub and the target
set is not fully known): a stub names every platform and architecture the
library has, so a target the linker does not recognize is one it is not
linking for, and skipping it changes no link that could have succeeded.
Concretely, `macho::loadDylib` in `lld/MachO/DriverUtils.cpp` should call
`TextAPIReader::get(mbref, /*SkipUnknownTriples=*/true)`.

## Status upstream

The macOS 27 symptom is fixed: main teaches LLVM
`arm64e.x1` in b8007a8e4 ("[ld64.lld, llvm-otool] Minimal arm64e.x1
support", [#222721](https://github.com/llvm/llvm-project/pull/222721)),
backported to `release/23.x` as 532fa5afb
([#224185](https://github.com/llvm/llvm-project/pull/224185)) after the
`llvmorg-23.1.2` tag. The pin, main at 7208ba24, has it. The general bug
is not fixed: main still reads a `.tbd` without `SkipUnknownTriples`, in
the same call (`DriverUtils.cpp:267` at 7208ba24), and at ed390ca4
(October 2026) still refused `unknown.tbd`. That skip stays local.

## Our workaround

`PINS.md`: `darwin-ld64-tapi`. None in code: the patch below is carried,
and every Darwin link is the pinned `ld64.lld`'s (`tools/bootstrap.sh`'s
`config_file_darwin`, and the Darwin target entry's
`IDRIS_MLIR_EXECUTABLE_FLAGS`, with `--icf=all`, in `CMakeLists.txt`).
Before the patch, those links were made by the host's `ld64`.

## Patch

`llvm.patch` is the proposed fix alone, against main at 7208ba24, the
pin: `macho::loadDylib` reads a stub with `SkipUnknownTriples = true`.
Test: `lld/test/MachO/tapi-unknown-target.s`, a link against a stub that
lists `unknown-macos`. While the pin was llvmorg-23.1.2, the patch also
carried `release/23.x`'s 532fa5afb (main's b8007a8e4, which the pin now
has), and it was built into that toolchain: its `ld64.lld` linked
`unknown.tbd` (`tests/upstream/ld64-lld-unknown-tapi-target`) and every
Darwin program against the macOS 27 SDK. lld's lit tests have not been
run (the pinned build has no test targets).

## Upstreaming plan

Status: carried, not filed.

The unknown-triple skip is ours and stays local. `macho::loadDylib`
reading a stub with `SkipUnknownTriples` is not sent. The `arm64e.x1`
part is main's b8007a8e4 (#222721), which the pin has, so it left the
patch when the pin moved to main.

- Where: nothing to send. The patch is carried until the pin's
  `ld64.lld` reads a stub with an unknown target.
- Upstream test: `tapi-unknown-target.s`, kept with the local skip.
