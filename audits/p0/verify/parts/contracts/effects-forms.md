<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Contract: the effect forms every op declares (L01, 2026-10-21)

On disk in `compiler/spec/IdrisMLIR/Spec/Effects/Declaration.idr`, which
publicly imports `Effects.Resource` and `Effects.Atom`. Write against
these names exactly; there are no aliases.

## The declaration

`Declaration i o` is one of two forms:
- **`Definition`**;
- **`Executes effects rules bodies memory`**, with an auto-0 law: whatever
  writes `exit` writes `io`.

Also exported:
- **`noEffects`**: no effect at all.
- **`unknownCode`**: the call effects of every ordering atom (`force`,
  `apply`).
- **`ods : Declaration i o -> OdsEffects i o`**.
- **`resources : List ResourceDef`**.

## Static effects

- **`OnState k r`**: Read or Write only, on any state.
- **`OnValues k r (Operands g | Results g)`**: on addressable state only.
  `Allocate` only on a result; `Free` only on an operand.

The kinds are `Read`, `Write`, `Allocate` and `Free`.

The states are `Root`, `Frame`, `Heap`, `Contents`, `Count`,
`MemoState`, `Identity`, `IO`, `RuntimeState`, `Exit`, `Crash` and
`Divergence`. No op of ours may name `Root`.

## Typed rules (`TypedRule i o`)

`g` is a `Fin`.
- `Consumes g`: consumption is a `Free` on `count` alone (C69, P0 §5.1).
- `NewIdentity g`
- `Acquires g`
- `ReadsMemo g`
- `CountsIfShared (Operands g | Results g)`
- `Recycles token`: lands on each result.
- `ReleasesForeign g`
- `ReadsBuffers g` and `WritesBuffers g`: L12's generating ops.
- `Summarized`

## The rest of a declaration

- **Bodies:** `Covered` or `Recursive`.
- **Runtime memory:** `Untouched` or `Touched`.
- **`Stops d`** (`StopsByExit` or `StopsByCrash`): the evidence a
  terminator with no successor needs.

## Rulings

- `idr.yield` and `idr.jump` declare `noEffects` (C93): passing a value
  out moves ownership; it is neither a consumption nor a free.

## Names L09 guessed, and what they map to

| guessed | real |
| --- | --- |
| `pure` | `noEffects` |
| `typed rs` | `Executes [] rs Covered Untouched` |
| `recursive x` | `Recursive`, as the bodies argument |
| `readsMemo (OperandGroup 0)` | `ReadsMemo 0` |
| `consumes (OperandGroup 0)` | `Consumes 0` |
| `OperandGroup n` | `Operands n` |
