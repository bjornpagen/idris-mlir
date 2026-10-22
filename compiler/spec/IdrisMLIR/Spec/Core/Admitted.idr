-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The upstream ops the dialect admits: each by its dialect and the name
||| of upstream's own record, with the stages it may stand at, the guards
||| its meaning needs and the range function upstream computes its interval
||| with. The generator prints one admitted record file per upstream dialect
||| from these; the one C++ TableGen backend reads upstream's records for
||| them alone, printing their Idris builders (a guarded op's with its
||| guards) and the C++ table of their classes, so the specification never
||| restates an upstream class or an operand list, and a wrong record name,
||| or a guard's position past the record's operand groups, is that
||| backend's error.
module IdrisMLIR.Spec.Core.Admitted

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Dialect
import public IdrisMLIR.Spec.Core.Guard
import IdrisMLIR.Spec.Pipeline.Stage

%default total

||| Whether the frontend writes the op: then its Idris builder is printed.
public export
data Writer = FrontendWrites | PassesOnly

||| A law of an upstream op that upstream has no trait for, so the e-graph
||| and the accumulator read it here: associativity, and the identity an
||| operand of which leaves the other as it is (commutativity and the rest
||| are upstream's traits).
public export
data UpLaw = UpAssociative | UpIdentity Integer

||| Whether the e-graph and every other reader of folds may fold an
||| admitted op by upstream's fold: where upstream's fold computes on the
||| compiling machine's C library (libm's transcendental functions, whose
||| results IEEE does not pin), a folded constant could differ from what the
||| target computes, so the op is never folded and runs on the target as
||| written.
public export
data UpFold = UpstreamFold | NeverFolded

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

||| An admitted op. Its alias names it among every admitted op of every
||| dialect, where upstream's record names it only among its own dialect's
||| (`scf.yield`'s record and `transform.yield`'s are both `YieldOp`): the
||| C++ class, the per-op tables' key and the e-graph's kind read it, so it
||| carries its dialect where the record does not (`SCF_YieldOp`, and
||| `Arith_AddIOp` as the record already is). Its guards are what upstream
||| leaves undefined and Idris crashes on (`arith.divui`'s zero divisor), as
||| an op of ours states its own: each position is among upstream's operand
||| groups. Its range is absent where upstream has no range function for it
||| (`arith.cmpi` reads its predicate, `arith.select` is arith's own). Its
||| folding says whether upstream's fold may run at compile time.
public export
record Admitted where
  constructor MkAdmitted
  dialect : Dialect
  upstreamRecord : Ident
  alias : Ident
  legal : Legal
  writer : Writer
  guards : List (Guard Nat)
  laws : List UpLaw
  range : Maybe RangeFunction
  folding : UpFold

||| The admitted op's name in the C++ table the backend prints:
||| `::idr::admitted::SCF_YieldOp`, an alias of upstream's class.
public export
admittedAlias : Admitted -> String
admittedAlias a = "::idr::admitted::" ++ identText a.alias
