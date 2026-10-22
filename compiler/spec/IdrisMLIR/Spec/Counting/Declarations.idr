-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Counting's declarations: the memory a constructor is built in, the reuse
||| token, and the ops counting writes, from the cell's source to the one
||| test of sharing left to run.
|||
||| Memory is explicit from counting's first step: a constructor of a cell is
||| the cell's source (`cell.new`, a fresh cell its count frees; a lifetime's
||| sources are the lifetime's) and its initialization (`cell.init`). A value
||| freed by its count holds one reference, which one use on every path
||| consumes or gives up (`count.drop`), a use that consumes it while a later
||| one still needs it taking another (`count.dup`); a view, which its
||| lifetime frees, is never duplicated or dropped. A value of a known
||| constructor is taken apart where it dies (`count.take`, a cell's, giving
||| its token; `count.unpack`, a value in place, giving none); the token is
||| recycled into a construction of its size (`cell.recycle`), carried as a
||| result across a rejoin, or freed (`token.free`). A take of a value whose type proves nothing of its sharing
||| becomes the one run-time test, a match of two regions
||| (`count.match_unique`); where its token is recycled once it fuses with the
||| recycle (`count.take_into`), and where it is given on elsewhere the shared
||| path gives the null token (`token.null`). A rebuild the in-place rule
||| decided before counting is a token its check made, consumed by
||| `token.rebuild`.
|||
||| Where a reference crosses into upstream's buffers it is an op of its
||| own: a fresh buffer taken over by counting (`own.adopt`), a value stored
||| into one handing its reference to the memory (`own.give`).
|||
||| Every effect is declared through the effect system's forms: consuming a
||| value that owns its count is a free of that count, a count is read and
||| written only where the type does not prove the value unshared, and a
||| value typed unique meets no count at all. Each op that exists while the
||| ownership markings read the program states how its values move, and
||| each that can make a scoped value (a share, an unpack, an init) states
||| that value's lifetime, so it is read off the op in one step.
module IdrisMLIR.Spec.Counting.Declarations

import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Core.Vocabulary
import public IdrisMLIR.Spec.Counting.Types
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Lifetimes.Declarations
import IdrisMLIR.Spec.Ops.Bigs

import Data.Fin
import Data.List1
-- `countingOp`'s automatic proof is searched where it is written.
import public Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- What the operands ask
--------------------------------------------------------------------------------

predicate : Ident -> Line -> Predicate
predicate n d = MkPredicate n OnType (brief d)

||| Freed by its count: a value that holds one counted reference of its own,
||| the one operand a dup or a drop takes. A view is freed by its lifetime,
||| which does not tell a view of counted memory from a cell of an arena, so
||| neither may be duplicated or dropped: a view that must outlive its loan
||| is duplicated from the counted value it was lent from, which dominates
||| the loan. Static data has no count to touch.
countedValue : Predicate
countedValue = predicate "isCountedValue" "a value its count frees"

||| Freed by its count and refined to one constructor that has a cell: a
||| value a take takes out of its cell.
takeable : Predicate
takeable = predicate "isTakeable" "a counted value refined to a constructor with a cell"

||| Refined to one constructor held in place: a value an unpack takes apart.
unpackable : Predicate
unpackable = predicate "isUnpackable" "a value refined to a constructor held in place"

||| A reuse token used once.
tokenValue : Predicate
tokenValue = predicate "isTokenValue" "a reuse token, used once"

||| A value that holds references: one whose claim of its sharing a share
||| forgets, or static data a share gives where a value that claims nothing
||| is asked.
heldValue : Predicate
heldValue = predicate "isHeldValue" "a value that holds references"

anyValue : TypeC
anyValue = UpstreamType AnyTypeC

cell : TypeC
cell = OurType (SomeType cellType)

token : TypeC
token = SatisfiesType tokenValue

||| The lifetimes an op states, one per scoped value it makes, in the order
||| of its results: two results of two lifetimes keep each its own span.
outers : Operand
outers = variadic "outers" (OurType (SomeType lifetimeType))

--------------------------------------------------------------------------------
-- The custom directives
--------------------------------------------------------------------------------

||| A share's result: the value with its claim forgotten, unless another
||| type it fits is written, `-> T`.
sharedDirective : Directive
sharedDirective = MkDirective "Shared" [TypeArg, RefTypeArg]
  (brief "a share's result, the value with its claim forgotten unless written")

||| A cell's init's result: what the init infers from the cell, the fields
||| and the holes, unless another grade is written, `-> T`.
cellResultDirective : Directive
cellResultDirective = MkDirective "CellResult"
  [TypeArg, RefTypeArg, RefVariadicTypeArg, RefAttrArg "::mlir::DenseI32ArrayAttr"]
  (brief "an init's result, what it infers unless written")

||| A cell's init's destinations, one per hole, written as nothing: their
||| types follow from the cell's and the holes.
cellDestsDirective : Directive
cellDestsDirective = MkDirective "CellDests"
  [VariadicTypeArg, RefTypeArg, RefAttrArg "::mlir::DenseI32ArrayAttr"]
  (brief "an init's destinations, written as nothing")

--------------------------------------------------------------------------------
-- The ops
--------------------------------------------------------------------------------

||| An op of counting: no meaning to fold, no guard, law or specialization.
public export
countingOp : Mnemonic -> (ins : Vect i Operand) -> (outs : Vect o Result) -> (attrs : Vect a Attr)
  -> (regions : Vect r Region) -> List (Trait i o) -> List InterfaceUse -> Declaration i o -> Legal -> Verify
  -> Format i o a r -> List Builder -> DefaultBuilders -> List Member -> Doc
  -> {auto 0 named : So (distinct (groupNames ins outs attrs regions))} -> Op i o a r
countingOp m ins outs attrs regions traits interfaces effects stages verify format builders defaults members doc =
  MkOp
    { home = InIdr, mnemonic = m, ins, outs, attrs, regions, traits, interfaces, effects
    , speculation = NotSpeculatable, stages, meaning = NoFold, verify, format, builders
    , defaultBuilders = defaults, members, guards = [], specializations = [], laws = [], doc }

||| From placement, which runs once lifetimes and borrows decided every
||| hold, to the lowering.
counted : Legal
counted = between Graded Owned

||| From counting's first step, which makes memory explicit, to the
||| lowering; a take, a rebuild and a share the in-place check writes right
||| after defunctionalization, before counting.
explicit : Legal
explicit = between First Owned

||| `count.dup %v : T`, C++ `CountDupOp`: one more reference to a counted
||| value; the result holds it, counted claiming nothing unless written. A
||| fresh identity, never merged with another dup.
public export
dup : Op 1 1 0 0
dup = countingOp "count.dup" [single "value" (SatisfiesType countedValue)] [result "result" anyValue] [] []
  [] [Implements flowInterface ["getFlowEdges"]]
  (Executes [OnValues Read Count (Operands 0), OnValues Write Count (Operands 0)] [NewIdentity 0] Covered Untouched)
  counted VerifiesOp
  (Declared [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
            , Custom countedResultDirective [TypeOfGroup (ResultRef 0), TypeAgain (OperandRef 0)] ])
  [] WithDefaults []
  (brief "one more reference to a counted value")

||| `count.drop %v : T`, C++ `CountDropOp`: gives up a counted reference,
||| freeing the value with its last. A value typed unique frees with no
||| count read.
public export
drop : Op 1 0 0 0
drop = countingOp "count.drop" [single "value" (SatisfiesType countedValue)] [] [] []
  [] [Implements flowInterface ["getFlowEdges"]]
  (Executes [OnValues Free Heap (Operands 0)] [Consumes 0, CountsIfShared (Operands 0)] Covered Untouched)
  counted DeclarationOnly
  (Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))])
  [] WithDefaults []
  (brief "gives up a counted reference, freeing the value with its last")

||| `count.share %v : T in %l : L -> U`, C++ `CountShareOp`: the value given
||| on with what its grade claimed of its sharing forgotten, where a slot
||| claims less; static data given where a value that claims nothing is
||| asked; or a token given where one that may hold more constructors' cells
||| is asked, as a rejoin's paths give theirs. Nothing at run time; its
||| result carries its operand, moved where the operand owns a count, so it
||| is no identity of its operand's, and a value it follows is never proved
||| unique through it. A scoped result lives in the lifetime it states
||| (`in %l`), its operand's or one that lifetime encloses, so its lifetime
||| is read off the share in one step; the builder that takes no lifetime
||| states the operand's.
public export
share : Op 2 1 0 0
share = countingOp "count.share"
  [single "value" (SatisfiesType heldValue), outers] [result "result" anyValue] [] []
  [OurTrait resultCarriesOperand]
  [Implements flowInterface ["getFlowEdges"], Implements statesLifetime statedMethods]
  (Executes [] [Consumes 0, NewIdentity 0] Covered Untouched)
  explicit VerifiesOp
  (Declared [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
            , OptionalGroup [Lit "in"] (ValueOf (OperandRef 1)) [Lit ":", TypeOf (OfGroup (OperandRef 1))]
            , Custom sharedDirective [TypeOfGroup (ResultRef 0), TypeAgain (OperandRef 0)] ])
  [MkBuilder [param "::mlir::Type" "result", param "::mlir::Value" "value"]] WithDefaults []
  (brief "gives a value on with its claim of sharing forgotten")

||| `count.take %v : T`, C++ `CountTakeOp`: a value refined to a constructor
||| with a cell taken out of it, its token then its fields, inferred from
||| the value. Where the value held the only reference to its cell the
||| fields move out with no count changed and the token is the cell, never
||| null when the type proves it; otherwise each field takes a reference,
||| the value gives up its own and the token is null. Expanded into the
||| match on uniqueness before the lowering wherever the type proves nothing.
public export
take : Op 1 2 0 0
take = countingOp "count.take" [single "value" (SatisfiesType takeable)]
  [result "token" token, results "fields" anyValue] [] []
  [] [InfersTypes InferredOnly, Implements flowInterface ["getFlowEdges"]]
  (Executes [] [Consumes 0, CountsIfShared (Operands 0), NewIdentity 0, NewIdentity 1] Covered Untouched)
  explicit DeclarationOnly
  (Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))])
  [] WithDefaults
  [ MkMember OnObject "::idr::DataType" "getDataType" []
  , MkMember OnObject "::idr::Tag" "getTag" [] ]
  (brief "takes a value out of its cell, giving its token and its fields")

||| `count.unpack %v : T in %l, … : L, …`, C++ `CountUnpackOp`: a value
||| refined to a constructor held in place taken apart, its fields inferred
||| from it: it is its fields already, so no memory is read and no count
||| changed. Each scoped field lives in the lifetime its own entry of
||| `outers` states, in field order: the value's, or one that lifetime
||| encloses, for a field read at the value's hold; whatever lifetime a
||| frame kept a field in, for a frame's field at its whole grade. The
||| builder that takes no lifetimes states the value's for each.
public export
unpack : Op 2 1 0 0
unpack = countingOp "count.unpack" [single "value" (SatisfiesType unpackable), outers]
  [results "fields" anyValue] [] []
  []
  [ InfersTypes InferredOnly, Implements flowInterface ["getFlowEdges"]
  , Implements statesLifetime statedMethods ]
  (Executes [] [Consumes 0, NewIdentity 0] Covered Untouched)
  explicit VerifiesOp
  (Declared [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
            , OptionalGroup [Lit "in"] (ValueOf (OperandRef 1)) [Lit ":", TypeOf (OfGroup (OperandRef 1))] ])
  [MkBuilder [param "::mlir::Value" "value"]] WithDefaults
  [ MkMember OnObject "::idr::DataType" "getDataType" []
  , MkMember OnObject "::idr::Tag" "getTag" [] ]
  (brief "takes apart a value held in place, giving its fields")

||| `count.take_into %v : T -> (!idr.cell<U>, F...)`, C++ `CountTakeIntoOp`:
||| a take whose token one construction recycles on every path, fused with
||| that recycle: the cell for `U`, the value's own where it held the only
||| reference, a new one where it was shared, and the fields.
public export
takeInto : Op 1 2 0 0
takeInto = countingOp "count.take_into" [single "value" (SatisfiesType takeable)]
  [result "cell" cell, results "fields" anyValue] [] []
  [] []
  (Executes [OnValues Allocate Heap (Results 0)] [Consumes 0, CountsIfShared (Operands 0), NewIdentity 1] Covered Untouched)
  counted DeclarationOnly
  (Declared [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
            , Lit "->", Lit "(", QualifiedTypeOf (OfGroup (ResultRef 0)), Lit ","
            , TypeOf (OfGroup (ResultRef 1)), Lit ")" ])
  [MkBuilder [param "::idr::CellType" "cell", param "::mlir::Value" "value"]] DeclaredOnly
  [ MkMember OnObject "::idr::DataType" "getDataType" []
  , MkMember OnObject "::idr::Tag" "getTag" [] ]
  (brief "takes a value apart into the cell one construction recycles")

||| What the match on uniqueness declares of upstream's control-flow
||| interface: both regions entered from the op, each giving the op's
||| results; the value forwarded into the shared region; the unique region's
||| arguments the op's own, made from the value.
uniqueMethods : List Ident
uniqueMethods =
  [ "getSuccessorRegions", "getEntrySuccessorOperands", "getSuccessorInputs"
  , "getRegionInvocationBounds" ]

||| `count.match_unique %v : T -> (R...) unique {...} shared {...}`, C++
||| `CountMatchUniqueOp`: the one run-time test of sharing, for a value whose
||| type proves nothing of it, of which exactly one region runs. The unique
||| region receives the value's token, unique and never null, and its
||| fields, moved out; the shared region receives the value itself, reads
||| the fields it needs, takes a reference to each from it, and drops it.
||| Never built for a value its type answers.
public export
matchUnique : Op 1 1 0 2
matchUnique = countingOp "count.match_unique" [single "value" (SatisfiesType takeable)]
  [results "results" anyValue] [] [sized "unique" 1, sized "shared" 1]
  [SingleBlock] [Declares RegionBranch uniqueMethods]
  (Executes [OnValues Read Count (Operands 0)] [Consumes 0] Recursive Untouched)
  counted VerifiesRegions
  (Declared [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
            , OptionalGroup [Lit "->", Lit "("] (TypeOf (OfGroup (ResultRef 0))) [Lit ")"]
            , Lit "unique", ValueOf (RegionRef 0), Lit "shared", ValueOf (RegionRef 1) ])
  [] WithDefaults []
  (brief "branches on whether a value holds the only reference to its cell")

||| `cell.new : !idr.cell<T>`, C++ `CellNewOp`: a fresh cell its count frees,
||| its header written: where memory enters the heap.
public export
cellNew : Op 0 1 0 0
cellNew = countingOp "cell.new" [] [result "cell" cell] [] []
  [] [Implements flowInterface ["getFlowEdges"]]
  (Executes [OnValues Allocate Heap (Results 0)] [] Covered Untouched)
  explicit DeclarationOnly
  (Declared [AttrDict, Lit ":", QualifiedTypeOf (OfGroup (ResultRef 0))])
  [] WithDefaults []
  (brief "a fresh cell its count frees, its header written")

||| `cell.init %c : !idr.cell<T> (%x : A, dest) in %l : L -> T`, C++
||| `CellInitOp`: the fields of the cell's constructor written into it,
||| which it consumes, giving the value; a field given owned moves its
||| reference into the cell, and a hole is a field written later, once,
||| through its destination (idr-trmc makes them), of the field's declared
||| type at its grade. Its results follow from the cell's type, the fields
||| and the holes. The cell is fresh, new or recycled, so nothing but its
||| fields shares what the value reaches: the value is inferred as it is
||| made, used once and counted, claiming what a constructor of those
||| fields claims (`unique deep` where each leaves everything it reaches
||| unshared), a hole at what its destination's write must meet, so a cell
||| whose holes are written later keeps what they will hold. It is held at
||| the grade it has, which may be written, or scoped in the lifetime the
||| cell's source allocated it into, which its one entry of `outers` states
||| (`in %l`) exactly when the value is scoped; the builder given a scoped
||| grade states the cell's. A counted cell takes no scoped field.
public export
cellInit : Op 3 2 1 0
cellInit = countingOp "cell.init"
  [single "cell" cell, variadic "fields" anyValue, outers]
  [result "result" anyValue, results "dests" anyValue]
  [MkAttr "holes" (AnAttribute (UpstreamAttr DenseI32ArrayAttrC) (DefaultValued "{}"))] []
  []
  [ InfersTypes AlsoCompatible
  , Implements statesLifetime statedMethods
  , Implements flowInterface ["getFlowEdges"] ]
  (Executes [OnValues Write Contents (Operands 0)] [Consumes 1, NewIdentity 0] Covered Untouched)
  explicit VerifiesOp
  (Declared [ ValueOf (OperandRef 0), Lit ":", QualifiedTypeOf (OfGroup (OperandRef 0))
            , Custom fieldsWithHolesDirective [Group (OperandRef 1), TypeOfGroup (OperandRef 1), Group (AttrRef 0)]
            , OptionalGroup [Lit "in"] (ValueOf (OperandRef 2)) [Lit ":", TypeOf (OfGroup (OperandRef 2))]
            , AttrDict
            , Custom cellResultDirective
                [TypeOfGroup (ResultRef 0), TypeAgain (OperandRef 0), TypeAgain (OperandRef 1), Again (AttrRef 0)]
            , Custom cellDestsDirective [TypeOfGroup (ResultRef 1), TypeAgain (OperandRef 0), Again (AttrRef 0)] ])
  [ MkBuilder [ param "::mlir::Value" "cell", param "::mlir::ValueRange" "fields"
              , param "::llvm::ArrayRef<int32_t>" "holes" ]
  , MkBuilder [ param "::mlir::Type" "result", param "::mlir::Value" "cell"
              , param "::mlir::ValueRange" "fields", param "::llvm::ArrayRef<int32_t>" "holes" ] ]
  DeclaredOnly
  [ MkMember OnObject "::idr::DataType" "getDataType" []
  , MkMember OnObject "::idr::Tag" "getTag" []
  , MkMember OnObject "::mlir::Value" "getField" [param "unsigned" "index"]
  , MkMember OnObject "::mlir::Value" "getDest" [param "unsigned" "index"] ]
  (brief "writes the fields of a cell's constructor into it, giving the value")

||| `cell.recycle %t : !idr.token<…> -> !idr.cell<T>`, C++ `CellRecycleOp`:
||| the token's cell given up and a cell for `T` given, its header written:
||| the same memory where the token holds its cell, new memory where it is
||| null. The token, used once, is consumed here. Of one size, which the
||| program's verifier reads off the two types and the target's layout, the
||| one place that layout is at hand.
public export
cellRecycle : Op 1 1 0 0
cellRecycle = countingOp "cell.recycle" [single "token" token] [result "cell" cell] [] []
  [] [Implements flowInterface ["getFlowEdges"]]
  (Executes [] [Consumes 0, Recycles 0] Covered Untouched)
  explicit DeclarationOnly
  (Declared [ ValueOf (OperandRef 0), Lit ":", TypeOf (OfGroup (OperandRef 0)), AttrDict
            , Lit "->", QualifiedTypeOf (OfGroup (ResultRef 0)) ])
  [] WithDefaults []
  (brief "the cell of a token, or a fresh cell where it is null")

||| `token.free %t : !idr.token<…>`, C++ `TokenFreeOp`: frees the emptied
||| cell a token holds: with no test where the type proves it holds one, a
||| test for null where it may not.
public export
tokenFree : Op 1 0 0 0
tokenFree = countingOp "token.free" [single "token" token] [] [] []
  [] []
  (Executes [OnValues Free Heap (Operands 0)] [Consumes 0] Covered Untouched)
  counted DeclarationOnly
  (Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))])
  [] WithDefaults []
  (brief "frees the emptied cell a token holds")

||| `token.null : !idr.token<…>`, C++ `TokenNullOp`: the one source of a
||| null token, which the shared region of a match on uniqueness gives where
||| its token goes on to a recycle or a free that tests it. Never unique.
public export
tokenNull : Op 0 1 0 0
tokenNull = countingOp "token.null" [] [result "token" token] [] []
  [] []
  (Executes [] [NewIdentity 0] Covered Untouched)
  counted VerifiesOp
  (Declared [AttrDict, Lit ":", TypeOf (OfGroup (ResultRef 0))])
  [] WithDefaults []
  (brief "the null token, the one a shared path gives")

||| `token.rebuild %t (%x : A, ...) : !idr.token<…> -> T`, C++
||| `TokenRebuildOp`: a value of an in-place type rebuilt in the cell its
||| token holds, which the in-place check decided on the program as written
||| and counting lowers into the recycle of the cell and the init of the
||| fields. Its token holds its cell, and is consumed here as the fields
||| are: the promise binds where the program rebuilds, never where an
||| optimization did.
public export
tokenRebuild : Op 2 1 0 0
tokenRebuild = countingOp "token.rebuild" [single "token" token, variadic "fields" anyValue]
  [result "result" anyValue] [] []
  [] [Implements flowInterface ["getFlowEdges"]]
  (Executes [] [Consumes 0, Recycles 0, Consumes 1] Covered Untouched)
  explicit VerifiesOp
  (Declared [ ValueOf (OperandRef 0)
            , Custom fieldsDirective [Group (OperandRef 1), TypeOfGroup (OperandRef 1)]
            , AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ])
  [] WithDefaults []
  (brief "rebuilds an in-place value in the cell its token holds")

||| `own.adopt %b : T -> U`, C++ `OwnAdoptOp`: the bare buffer an op of
||| upstream's made, taken over right after it, entering the grades: from
||| here on its reference is a counted value's, freed by its count. Nothing
||| at run time: the result is the buffer's own words. It is fresh and
||| nothing moves into it, so it is inferred counted and `unique deep`, at
||| many uses; it may be written at any grade that only forgets that claim,
||| the bare buffer among them where upstream's ops, which take the bare
||| carrier, read it. Bufferization writes it at each allocation it makes of
||| a buffer whose elements hold references, the one place a buffer is known
||| to be an allocation, and nothing else writes it: a buffer met anywhere
||| else (a slice, a parameter's, one read out of a cell) may be counted
||| already, and taking it over there would count its memory twice. So it
||| is legal from the stage bufferization runs at, and a program at the
||| frontend's stage cannot hold one, nor has the frontend a builder for it.
public export
adopt : Op 1 1 0 0
adopt = countingOp "own.adopt" [single "value" (UpstreamType AnyRankedOrUnrankedMemRefC)]
  [result "result" anyValue] [] []
  [OurTrait noRuntimeForm]
  [ InfersTypes AlsoCompatible
  , Implements flowInterface ["getFlowEdges"] ]
  (Executes [] [NewIdentity 0] Covered Untouched)
  (between First Owned) DeclarationOnly
  (Declared [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
            , Lit "->", TypeOf (OfGroup (ResultRef 0)) ])
  [] WithDefaults []
  (brief "a buffer upstream made, taken over by counting")

||| `own.give %v : T -> C`, C++ `OwnGiveOp`: a value an op of upstream's
||| stores into a buffer hands its reference to the memory, which holds it
||| from then on; the result is the value at its plain carrier, which the
||| store takes, and nothing at run time: the value's own words. A value
||| used once is never given, so the store never loses its quantity.
public export
give : Op 1 1 0 0
give = countingOp "own.give" [single "value" (SatisfiesType countedValue)] [result "result" anyValue] [] []
  [OurTrait noRuntimeForm] [Implements flowInterface ["getFlowEdges"]]
  (Executes [] [Consumes 0] Covered Untouched)
  explicit VerifiesOp
  (Declared [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
            , Lit "->", TypeOf (OfGroup (ResultRef 0)) ])
  [] WithDefaults []
  (brief "hands a stored value's reference to the memory that holds it")

--------------------------------------------------------------------------------
-- The area
--------------------------------------------------------------------------------

public export
declarations : Declarations
declarations =
  { ops := [ SomeOp dup, SomeOp drop, SomeOp share, SomeOp take, SomeOp Counting.Declarations.unpack, SomeOp takeInto
           , SomeOp matchUnique, SomeOp cellNew, SomeOp cellInit, SomeOp cellRecycle
           , SomeOp tokenFree, SomeOp tokenNull, SomeOp tokenRebuild, SomeOp adopt, SomeOp give ]
  , types := [SomeType cellType, SomeType tokenType]
  , directives := [sharedDirective, cellResultDirective, cellDestsDirective]
  , predicates := [countedValue, takeable, unpackable, tokenValue, heldValue]
  } nothing
