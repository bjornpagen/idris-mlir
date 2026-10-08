## Common obligations

- **The packet is the contract.**
  - Read the sections of `proposals/0002-representation-cutover/contracts.md`
    that your lane names before writing anything. Op, type, attribute,
    pass, option, trait, function, runtime-symbol and rule names are
    fixed there. Consume them by name. Never redeclare one under another
    spelling.
  - Your `Read first` list names the findings in
    `proposals/0002-representation-cutover/findings.md` that carry your
    evidence. Read them; they hold the `path:line` anchors.
  - Path roots: `IDR` is `foreign/idr/lib`, `INC` is
    `foreign/idr/include/idr`, `RT` is `runtime`, `CS` is
    `compiler/src/IdrisMLIR`, and `T` is `tests`.
- **No coding until dispatched.** This file is a dispatch for a swarm
  the owner has not launched yet. Do not act on it unless the
  coordinator hands it to you as your assignment.
- **The tree is red by design.** Other lanes write the declarations you
  use at the same time, and the coordinator writes the hubs (C1).
  - Do not run `make check`, `make build`, `make test`,
    `make test-idr`, `make test-mlir-tools`, cmake, ninja, the Idris
    compiler, or any suite. `make check` builds the test runner, and it
    is red mid-swarm by design (C13); do not fix what it shows.
  - You may run the one spec test your acceptance names, and only it:
    `cd tests/spec/<name> && IDRIS_MLIR_ROOT=<repository root> sh run | diff - expected`.
  - Write against the packet text.
  - Report `Verification: NotRun (swarm policy)` for what you did not
    run.
- **The hubs are the coordinator's.** Never edit these:
  - `INC/IdrOps.td`, `INC/IdrPlatformOps.td`, `INC/Passes.td` and
    `INC/Idr.h`;
  - `foreign/idr/CMakeLists.txt`, `IDR/Dialect/CMakeLists.txt`,
    `IDR/Dialect/Dialect.cppm` and `IDR/Mlir.cppm`;
  - `IDR/Dialect/Registration/`;
  - `RT/idris_rt.h`, `CS/Rule.idr` and `CS/Dialect/` (generated);
  - `compiler/idris-mlir.ipkg`, `PINS.md`, `README.md`, `AGENTS.md`,
    `findings/` and `T/spec/`.

  If you need a change there that `contracts.md` C1 does not already
  give, report the exact text in your handoff. Use the declaration as
  if it had landed. An MLIR name that `IDR/Mlir.cppm` does not export
  goes in your handoff's list of exports to add.
- **Repository rules prevail.** `AGENTS.md` is binding. In particular:
  - Comments say why, in the surrounding code's density and voice. They
    never cite documents, findings, contracts or rule numbers.
  - Nothing assumes x86, Linux, ELF, musl or a page size. OS calls go
    through `RT/Platform/`.
  - What the compiler cannot compile is rejected with
    `unsupported (<rule>)`. Never miscompile silently.
  - No pass drops a quantity, erasure or linearity.
  - Every `.cc` or `.cppm` stays at 400 lines or fewer unless
    `T/spec/file-size/allowed` already lists it; split a unit in your
    lane rather than grow it.
  - C++ follows the existing module structure: modules, partitions, and
    each area's `CMakeLists.txt`.
  - No new dependency, and no Python.
- **No new numbers.** Do not add a limit, budget, threshold or retry
  count. Existing ones keep their values and their comments.
- **No tests outside U22, U23 and U01's `tests/upstream` dirs.** Your
  lane describes the evidence its change needs in the handoff, and U22
  or U23 writes it from C12.
- **Concurrent work.** Twenty-two other lanes and the coordinator write
  other files at the same time.
  - Never revert, reformat or "fix" a file you do not own; report the
    seam.
  - Stage nothing and commit nothing; the coordinator commits.
  - `third_party/Idris2` is never edited.
- **Handoff shape.** Return only:
  - the changed paths, mapped to obligations;
  - the contract names you supplied;
  - the consumer adaptations you made;
  - the exports or hub text you need;
  - the verification you ran, or `NotRun`;
  - the unresolved seams.
