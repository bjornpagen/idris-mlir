-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What an upstream op the dialect admits is stated with besides its
||| dialect, its record's name and its guards: whether the frontend writes
||| it, the laws upstream has no trait for, its range function and whether
||| upstream's fold may run. The admitted op itself (`Admitted`) is declared
||| with the op, since its guards are ops of ours. The generator prints one
||| admitted record file per upstream dialect from these; the one C++
||| TableGen backend reads upstream's records for them alone, printing
||| their Idris builders (a guarded op's with its guards) and the C++ table
||| of their classes, so the specification never restates an upstream class
||| or an operand list, and a wrong record name, or a guard's position past
||| the record's operand groups, is that backend's error.
module IdrisMLIR.Spec.Core.Admitted

import IdrisMLIR.Spec.Core.Text

%default total

||| Whether the frontend writes the op: then its Idris builder is printed.
public export
data Writer = FrontendWrites | PassesOnly

||| An upstream op's identity, as a value of the op's own width: an integer,
||| its bits the same pattern at every width (`-1` every bit set); or the
||| least or greatest signed value of the width, which no one integer is
||| (`arith.maxsi`'s and `arith.minsi`'s). A literal is an integer's.
public export
data UpIdentityValue = UpExactly Integer | UpSignedLeast | UpSignedGreatest

namespace UpIdentityValue
  public export
  fromInteger : Integer -> UpIdentityValue
  fromInteger = UpExactly

  ||| A negative integer literal's value, its magnitude an integer.
  public export
  negate : Integer -> UpIdentityValue
  negate i = UpExactly (negate i)

||| A law of an upstream op that upstream has no trait for, so the e-graph
||| and the accumulator read it here: associativity, and the identity an
||| operand of which leaves the other as it is (commutativity and the rest
||| are upstream's traits).
public export
data UpLaw = UpAssociative | UpIdentity UpIdentityValue

||| Whether the e-graph and every other reader of folds may fold an
||| admitted op by upstream's fold: where upstream's fold computes on the
||| compiling machine's C library (libm's transcendental functions, whose
||| results IEEE does not pin), a folded constant could differ from what the
||| target computes, so the op is never folded and runs on the target as
||| written. An op on Doubles whose result IEEE 754 fixes, and whose
||| upstream fold is that operation on `APFloat` (rounded to nearest, ties
||| to even, where it rounds), the e-graph computes on its own Double
||| values too, by the operation that fold applies, so the op's meaning is
||| upstream's documented one and no second meaning is written; a NaN it
||| computes stays applied.
public export
data UpFold = UpstreamFold | ComputedOnDoubles | NeverFolded

||| A function of upstream's common integer range inference
||| (`mlir::intrange`), by its name there: `inferAnd`, `inferSub`,
||| `extSIRange`. It is what an admitted op's node computes its interval
||| with when a rule built it and no op stands for it. The shape of its
||| arguments is upstream's signature, read where the table naming it is
||| compiled, so a wrong name is the compiler's build error and no shape is
||| restated here.
public export
record RangeFunction where
  constructor InIntRange
  name : Ident
