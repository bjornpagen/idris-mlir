-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The upstream ops the dialect admits: each by its dialect and the name
||| of upstream's own record, with the stages it may stand at. The
||| generator prints one admitted record file per upstream dialect from
||| these; the one C++ TableGen backend reads upstream's records for them
||| alone, printing their Idris builders and the C++ table of their classes,
||| so the specification never restates an upstream class or an operand
||| list, and a wrong record name is TableGen's own error.
module IdrisMLIR.Spec.Core.Admitted

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Dialect
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

public export
record Admitted where
  constructor MkAdmitted
  dialect : Dialect
  upstreamRecord : Ident
  legal : Legal
  writer : Writer
  laws : List UpLaw

||| The admitted op's name in the C++ table the backend prints:
||| `::idr::admitted::Arith_AddIOp`, an alias of upstream's class.
public export
admittedAlias : Admitted -> String
admittedAlias a = "::idr::admitted::" ++ identText a.upstreamRecord
