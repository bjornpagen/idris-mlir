# [lld] ld64.lld refuses a .tbd that names a target it does not know

At `llvmorg-23.1.2`, `ld64.lld` fails to link against any `.tbd` stub whose
`targets` list holds a target the LLVM of that release does not know. The
macOS 27 SDK's stubs name `arm64e.x1-macos` and `arm64e.x1-maccatalyst`,
which LLVM 23.1.2 predates, so every link against `libSystem` in that SDK
fails, and the target is unusable there.

## Reproduce

`min.c` (any object does; the bug is in reading the `.tbd`):

```c
int main(void) { return 0; }
```

`known.tbd` has targets LLVM knows, `unknown.tbd` adds one it does not
(the reproduction is for `x86_64` so the X86-only Linux build of the pinned
LLVM can run it too; the target the macOS 27 SDK actually adds is
`arm64e.x1-macos`, and the same error stops an arm64 link):

```yaml
--- !tapi-tbd
tbd-version:     4
targets:         [ x86_64-macos, arm64-macos, arm64e.x1-macos ]
install-name:    '/usr/lib/libSystem.B.dylib'
current-version: 1.0
exports:
  - targets:         [ x86_64-macos, arm64-macos, arm64e.x1-macos ]
    symbols:         [ _exit ]
...
```

```
$ clang --target=x86_64-apple-macosx14.0 -c min.c -o min.o
$ ld64.lld -arch x86_64 -platform_version macos 14.0 14.0 min.o known.tbd -o a.out
$ ld64.lld -arch x86_64 -platform_version macos 14.0 14.0 min.o unknown.tbd -o a.out
ld64.lld: error: could not load TAPI file at unknown.tbd: malformed file
unknown.tbd:3:47: error: unknown target
targets:         [ x86_64-macos, arm64-macos, arm64e.x1-macos ]
                                              ^~~~~~~~~~~~~~~~
```

`known.tbd` links (exit 0); `unknown.tbd` fails (exit 1). Expected: the
linker ignores a target it does not know, as it ignores a target for
another platform, and links the file for the architectures it does know.

## Cause

`TextAPIReader` takes a `SkipUnknownTriples` option and skips a target it
cannot parse when it is set (`llvm/lib/TextAPI/TextStub.cpp:402-405`, and
`:317` for the target traits). It defaults to false
(`llvm/include/llvm/TextAPI/TextAPIReader.h:41`), and `ld64.lld`'s input
reader never sets it: the one place that reads a `.tbd`
(`lld/MachO/InputFiles.cpp`, `InputFile::create` -> `TextAPIReader::get`)
passes the buffer alone. So a target the pinned LLVM does not know is a
hard error, and the toolchain cannot read a stub from a newer SDK. LLVM's
own tests read such files with the option on
(`llvm/unittests/TextAPI/TextStubV4Tests.cpp:1191`), so the mechanism
exists and is exercised.

## Proposed fix

`ld64.lld` should read a `.tbd` with `SkipUnknownTriples = true` (or expose
a flag for it, defaulting to true when the input is a stub and the target
set is not fully known): a stub names every platform and architecture the
library has, so a target the linker does not recognize is one it is not
linking for, and skipping it changes no link that could have succeeded.
Concretely, in `lld/MachO/InputFiles.cpp`, `TapiFile::create` (and
`TapiUniversal::create`) should pass `/*SkipUnknownTriples=*/true`.

## Our workaround

`PINS.md`: `darwin-ld64-tapi`. Darwin links are made by the host's `ld64`
(`/usr/bin/ld`), which reads its own SDK, not by the pinned `ld64.lld`
(`tools/bootstrap.sh`'s `config_file_darwin` and the Darwin target entry's
`IDRIS_MLIR_EXECUTABLE_FLAGS` in `CMakeLists.txt`). The pinned `ld64.lld`
stays the linker on the target's terms the moment upstream reads newer
stubs; until then the platform's linker is the one that can.
