-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A function's record of what it does through each parameter, beside its
||| row: whether it writes in place through a parameter whose memory its
||| holder alone reaches, and how much it puts into a lifetime parameter
||| something may be put into. Each part exists only where the parameter's
||| type admits it, so no part can describe a parameter it does not fit:
||| the record is indexed by what each parameter admits.
|||
||| The write part makes a write the caller's own business where the caller
||| owns the memory it passes: a caller that passes memory it acquired
||| itself loses the effect, so building an array or rebuilding a value in
||| place stays movable, mergeable and deletable at that call, and LLVM is
||| told the write is argument memory only. The amount sizes a caller's
||| block and bounds what a frame holds; it is no effect.
|||
||| How the IR holds it, sparse, every parameter not listed at the top of
||| its part, as a row nothing has derived holds every atom: `untouched`,
||| the positions, among the parameters that admit a write part, of those
||| the function never writes through; `bounded`, the positions, among the
||| put parameters, of those with a bound, with the bound. A call keeps a
||| copy of `untouched` beside its copy of the row, since the call declares
||| the write on its own operand; no call holds an amount.
module IdrisMLIR.Spec.Functions.Parameters

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Spec.Lifetimes.Kind

import Data.Fin
import Data.List.Quantifiers
import Data.Vect

%default total

||| A hold whose holder alone reaches the memory a write in place touches:
||| freed by its count, and its own family's cells, or everything it
||| reaches, known unshared. Rebuilding a value in place writes only its
||| family's cells, which the spine's claim covers; a write to anything
||| else needs the deep claim.
public export
data Writable : Hold -> Type where
  SpineUnique : Writable (Counted Self)
  DeepUnique : Writable (Counted Deep)

||| What of the record a parameter's type admits: a write part, for a value
||| at a writable hold; an amount, for a lifetime something may be put
||| into; or nothing, for every other parameter.
public export
data Admits : Type where
  WritePart : (hold : Hold) -> (0 writable : Writable hold) -> Admits
  AmountPart : (kind : LifetimeKind) -> (0 putsInto : Puts kind) -> Admits
  NoPart : Admits

||| Whether a function writes through a parameter.
public export
data Write = NotWritten | Written

||| How much a function puts into a lifetime parameter: a bound in bytes,
||| or none. A room is a block of static size, so a room takes a bound and
||| nothing else.
public export
data Amount : LifetimeKind -> Type where
  Finite : (bytes : Nat) -> Amount kind
  Unbounded : (0 grows : Not (kind = Room)) -> Amount kind

||| The part a parameter that admits `a` has.
public export
Part : Admits -> Type
Part (WritePart _ _) = Write
Part (AmountPart kind _) = Amount kind
Part NoPart = ()

||| A function's record: one part per parameter, each of the kind the
||| parameter admits.
public export
Record : List Admits -> Type
Record = All Part

------------------------------------------------------------------------------
-- The bounded amounts, as the IR holds them
------------------------------------------------------------------------------

||| One bound of `#idr.put_bounds`, read and written by a hand directive:
||| `2: 64`, the third put parameter's bound of 64 bytes.
export
boundDirective : Directive
boundDirective = MkDirective
  { name = "PutBound"
  , args = []
  , doc = brief "a put parameter's position among them and its bound in bytes"
  }

||| `#idr.put_bounds<[0: 64, 2: 128]>`, C++ `PutBoundsAttr`: the put
||| parameters with a bound, in increasing position, each a hand
||| `::idr::PutBound`; its verifier holds the order.
export
putBoundsAttr : AttrDef 1
putBoundsAttr = MkAttrDef
  { mnemonic = "put_bounds"
  , params =
      [ MkParameter "bounds" (ListOf (HandValue "::idr::PutBound" boundDirective))
          AlwaysWritten "each bounded put parameter's position among them and its bound" ]
  , syntax = Declarative [Keyword "<", ParamAt FZ, Keyword ">"]
  , typed = Untyped
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members = []
  , doc = MkDoc "the lifetime parameters a function puts a bounded amount into"
      """
      Positions count the parameters something may be put into, in order; a
      parameter not listed is put into without a bound, and a room is
      always listed.
      """
  }
