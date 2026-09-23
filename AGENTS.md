# Working on idris-mlir

Read README.md and docs/architecture.md before changing the compiler boundary.

- This project consumes checked Idris TT and its definition context. Do not
  silently replace the input with CExp or erase facts before their consumers.
- Keep upstream Idris API imports inside frontend/. The rest of the compiler
  should consume representations defined by this project.
- third_party/Idris2 is an unmodified, commit-pinned dependency. Do not edit it
  or update its revision as a side effect of ordinary work. An intentional
  upgrade must update toolchain.lock.json and the submodule together.
- Install build dependencies under .toolchain/ when using project tooling.
  Do not modify the user's global compiler installation or shell configuration.
- The current frontend emits an inspection summary, not a complete typed IR.
  Preserve that distinction in documentation and error messages.
- Erased does not mean constant. A linear binder does not imply deep heap
  uniqueness. Indexed vectors do not imply contiguous storage.
- Use `python3 tools/dev.py check` for scaffold validation. For frontend changes,
  build the pinned API and run `python3 tools/dev.py test-frontend`. For C++/MLIR
  changes, build and run `python3 tools/dev.py test-mlir`. Report unavailable
  toolchains explicitly; do not claim skipped tests passed.
- Tests must check exit status and produced artifacts. Do not copy upstream's
  stdout-only golden harness for the new compiler.
