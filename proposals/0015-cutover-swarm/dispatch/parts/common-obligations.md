## Common obligations

- **The packet is the contract.**
  - Read the sections of `proposals/0015-cutover-swarm/contracts.md`
    that your lane names before writing anything. Op, type, attribute,
    pass, analysis, library, file, option and rule names are fixed
    there. Consume them by name. Never redeclare one under another
    spelling.
  - Your `Read first` list names the findings in
    `proposals/0015-cutover-swarm/findings.md` that carry your evidence.
    Read them; they hold the `path:line` anchors.
  - Path roots: `FI` is `foreign/idr`, `INC` is `foreign/idr/include/idr`,
    `IDR` is `foreign/idr/lib`, `CS` is `compiler/src/IdrisMLIR`, `RT` is
    `runtime`, and `T` is `tests`.
- **No coding until dispatched.** This file is a dispatch for a swarm
  the owner has not launched yet. Do not act on it unless the
  coordinator hands it to you as your assignment.
- **The tree is red by design.** Every `.cppm` of the C++ side is being
  deleted and every `.cpp` written at the same time, by 22 other lanes,
  and the coordinator writes the hubs (C1) and every `CMakeLists.txt`.
  - Do not run `make build`, `make test`, `make test-idr`,
    `make test-mlir-tools`, cmake, ninja, the Idris compiler, or any
    test.
  - `make check` builds nothing but needs the pinned Idris for its
    runner; run it only where `make doctor` shows that Idris.
  - Write against the packet text.
  - Report `Verification: NotRun (swarm policy)` for what you did not
    run.
- **The hubs are the coordinator's.** Never edit these:
  - `INC/IR/IdrOps.td`, `INC/IR/IdrPlatformOps.td`,
    `INC/Transforms/Passes.td`;
  - every `CMakeLists.txt`, `CMakePresets.json`, `.gitmodules`,
    `toolchain.lock.json`, `Makefile`, `tools/{bootstrap,host,toolchain,verify-pins}.sh`;
  - `CS/Ids.idr`, `CS/Rule.idr`, `CS/Dialect/`, `CS/Syntax/` (generated),
    `compiler/*.ipkg`;
  - `T/spec`, `T/README.md`, `PINS.md`, `README.md`, `AGENTS.md`,
    `HANDOFF.md`, `proposals/`, `upstream/`, `bugs/`.

  If you need a change there that `contracts.md` C1 does not already
  give, report the exact text in your handoff. Use the declaration as
  if it had landed. Report the list of `.cpp` files of your library in
  your handoff; the coordinator writes it into the `CMakeLists.txt`.
- **Repository rules prevail.** `AGENTS.md` is binding. In particular:
  - Comments say why, in the surrounding code's density and voice. They
    never cite documents, findings, contracts or rule numbers.
  - Nothing assumes x86, Linux, ELF, musl or a page size.
  - What the compiler cannot compile is rejected with
    `unsupported (<rule>)`. Never miscompile silently.
  - No pass drops a quantity of one or an ownership grade.
  - Every `.cpp` and `.h` stays at 400 lines or fewer unless
    `T/spec/file-size/allowed` already lists it; split a unit in your
    lane rather than grow it.
  - C++ is plain headers and `.cpp` in the layout of `contracts.md`
    C1.1: no module, no partition, no `import`, no `thread_local`, no
    `std::atomic`, no `static` mutable object, no state on a pass
    instance across runs.
  - No new dependency, and no Python.
- **No new numbers.** Do not add a limit, budget, threshold or retry
  count. Existing ones keep their values and their comments.
- **No tests outside U21, U22 and the coordinator's `T/spec`.** Your
  lane describes the evidence its change needs in the handoff, and U21
  or U22 writes it from C9.
- **Concurrent work.** Twenty-two other lanes and the coordinator write
  other files at the same time.
  - Never revert, reformat or "fix" a file you do not own; report the
    seam.
  - Stage nothing and commit nothing; the coordinator commits.
  - `third_party/` is never edited by a lane.
- **Handoff shape.** Return only:
  - the changed paths, mapped to obligations;
  - the `.cpp` files of your library, for its `CMakeLists.txt`;
  - the contract names you supplied;
  - the consumer adaptations you made;
  - the hub text you need;
  - the verification you ran, or `NotRun`;
  - the unresolved seams.
