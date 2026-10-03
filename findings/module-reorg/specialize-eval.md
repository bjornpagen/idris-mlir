# R1 lane: specialization and compile-time evaluation (`idr.specialize`, `idr.eval`)

Read `README.md` beside this file first.

Two modules, two libraries, one lane: they share the shape (a pass whose
logic is a class of several parts) and no code.

## Files

lib/Specialize (idr-specialize, idr-binding-times):

| File | Lines | What it holds |
|---|---|---|
| BindingTimes.h / .cc | 61 / 225 | BindingTime, BindingTimes (the abstract interpreter of binding times: Abstract, Interpreter), `nameOf`; imports idr.graph |
| Clones.h / .cc | 82 / 125 | Clone, CloneTable (parse, lookup, specialization, ownerOf, copy, add), `operandsFor`, `parameterAttrs` |
| Pattern.h / .cc | 111 / 283 | Pattern (Hole, Constant, Con, Closure, Linear), keys, shapes, sizes, `rebuild`, `labels` |
| Specializer.h | 67 | Statistics, Specializer (the run) |
| Run.cc | 45 | Specializer's constructor, `run`, `canonicalize` |
| Specialize.cc | 260 | `Specializer::specialize` and its helpers (Argument, Composed, `specializesOn`, `fill`, `substitute`, ...); imports idr.facts, idr.support |
| Raise.cc | 263 | `Specializer::consumerOf`, `makeRaised`, `raise` and helpers; imports idr.facts, idr.support |
| Pass.cc | 48 | glue of idr-specialize and idr-binding-times |

lib/Eval (idr-eval):

| File | Lines | What it holds |
|---|---|---|
| Eval.cc | 448 | the pass: Meter, Outcome, Call, Phases, `Eval::runOnOperation`, `scratch`, `evaluate`; imports idr.facts, idr.support, idr.layout |
| Child.h / .cc | 66 / 232 | Result, Run, Budget, `runInChild` (fork, pipes, records) |
| Jit.h / .cc | 37 / 216 | Jit (LLJIT, the runtime bound by address); imports idr.target |
| Reify.h / .cc | 77 / 307 | Unread, Reifier, `encodeResults`, `decodeResults`; Reify.h imports idr.layout |

## Proposed map

- `idr.specialize`: `:bindingtimes`, `:clones`, `:pattern`, `:specializer`
  partitions; units one function or one type's members each
  (`Pattern/KeyOf.cc`, `Pattern/Rebuild.cc`, ..., `Clones/CloneTable.cc`,
  `Specializer/Specialize.cc`, `Specializer/Raise.cc`, `Specializer/Run.cc`;
  Interpreter, an anonymous class today, declared in its partition outside
  `export`). Glue `Pass.cc` stays: the two bases, their statistics and
  remarks, and calls into the module.
- `idr.eval`: `:child`, `:jit`, `:reify`, `:evaluate` (what Eval.cc's pass
  does, moved out of the glue: Meter, Outcome, Call, Phases, `evaluate`);
  glue `Pass.cc` with the base and its options.

## Imports and links

idr.specialize: idr.mlir, idr.dialect, idr.facts, idr.support, idr.graph.
idr.eval: idr.mlir, idr.dialect, idr.facts, idr.support, idr.layout,
idr.target. Libraries `idr_specialize`, `idr_eval`, linked from
`idr_dialect`.

## Special

- Jit.cc includes `idr/TargetEntry.h` (CMake-generated X-macros:
  `IDRIS_MLIR_JIT_LIBRARY_CALLS`) and `idris_rt.h` (the runtime's entry
  points the JIT binds by address, and its macros): both in the global
  module fragment of the unit that uses them. ORC's headers
  (`llvm/ExecutionEngine/Orc/...`) go into idr.mlir's global module
  fragment with their names exported.
- Child.cc forks: nothing changes about it, only where it lives.
- `EvalCallAction`, `RaiseAction`, `SpecializeCloneAction` are idr.support's
  (namespace `idr::support`); R0 already switched your users to them.
- Compile-time evaluation runs the JIT on the native runtime linked into
  idris-mlir-cc (runtime/eval.cc now uses `rt::platform::reserve`): the
  tests that evaluate (most of `make test`) are your gate for it.

## Allowed lines that are yours

no-local-headers:

    foreign/idr/lib/Eval/Child.cc: Eval/Child.h
    foreign/idr/lib/Eval/Child.h: Eval/Jit.h
    foreign/idr/lib/Eval/Eval.cc: Eval/Child.h
    foreign/idr/lib/Eval/Eval.cc: Eval/Reify.h
    foreign/idr/lib/Eval/Jit.cc: Eval/Jit.h
    foreign/idr/lib/Eval/Reify.cc: Eval/Reify.h
    foreign/idr/lib/Specialize/BindingTimes.cc: Specialize/BindingTimes.h
    foreign/idr/lib/Specialize/Clones.cc: Specialize/Clones.h
    foreign/idr/lib/Specialize/Pass.cc: Specialize/Specializer.h
    foreign/idr/lib/Specialize/Pattern.cc: Specialize/Pattern.h
    foreign/idr/lib/Specialize/Raise.cc: Specialize/Specializer.h
    foreign/idr/lib/Specialize/Run.cc: Specialize/Specializer.h
    foreign/idr/lib/Specialize/Specialize.cc: Specialize/Specializer.h
    foreign/idr/lib/Specialize/Specializer.h: Specialize/BindingTimes.h
    foreign/idr/lib/Specialize/Specializer.h: Specialize/Clones.h
    foreign/idr/lib/Specialize/Specializer.h: Specialize/Pattern.h

file-size:

    foreign/idr/lib/Eval/Eval.cc

## Do not touch

lib/Layout, lib/Target, lib/Facts, lib/Support (R0's modules), lib/Lower
(Runtime's JIT mode is used through idr-lower's pass, not by you),
runtime/.
