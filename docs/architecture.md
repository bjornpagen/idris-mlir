# Architecture

```mermaid
flowchart LR
  Idris["Pinned Idris frontend"] --> TT["Checked TT + definition context"]
  TT --> Adapter["Our Idris adapter"]
  Adapter --> Typed["Our typed representation"]
  Typed --> Optimize["Specialization and representation selection"]
  Optimize --> Erase["Deliberate runtime erasure"]
  Erase --> MLIR["MLIR lowering"]
  MLIR --> LLVM["LLVM and native code"]
```

The frontend adapter and MLIR driver are scaffolded. The typed representation,
optimization pipeline, and connection between them are not implemented.

Only frontend/ imports upstream compiler types. Keep that adapter small and
version-specific. The compiler owns the representation after the boundary;
changes to Idris's internal records should not leak throughout the optimizer.

Use `mainWithCodegens` for registration and `incCompileFile` for inspecting
fresh modules before TTC serialization. The whole-program callback can later
inspect loaded dependencies and consume our sidecars. Neither callback requires
using CExp. Both run after normal Idris processing, so this does not add an
arbitrary pre-erasure compiler pass.

The initial `.ttsummary` is diagnostic output. It deliberately does not pretend
to preserve all typed information. Before defining the persistent typed IR,
measure which signatures, checked clauses, constructor relationships, and
generated-helper annotations survive fresh versus cached compilation.

The first tests use an isolated, no-Prelude vector fixture. Ordinary Prelude
caches lack our incremental artifacts and can disable the selected incremental
backend. Handling that boundary explicitly comes before broad language support.

Keep constants, erased symbolic indices, and runtime indices distinct. Preserve
evaluation order and typed laziness. Do not infer contiguous storage from Vect,
unique heap ownership from multiplicity one, or machine-sized arithmetic from
Nat. Fail explicitly when the supported subset cannot justify a lowering.

We use a full, unmodified upstream checkout as a build dependency rather than
copying TT datatypes. Git pins Idris independently from the LLVM source pin in
toolchain.lock.json. No remote repository or publishing workflow is configured.
