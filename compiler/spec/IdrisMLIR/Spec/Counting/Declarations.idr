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
||| consumes or gives up. A value used any number of times is given up by
||| `count.drop`, a use that consumes it while a later one still needs it
||| taking another (`count.dup`); a value used once has one owner, which
||| neither duplicates nor drops it: it is taken apart. A view, which its
||| lifetime frees, is never duplicated or dropped. A value of a known
||| constructor is taken apart where it dies (`count.take`, a cell's, giving
||| its token; `count.unpack`, a value in place, giving none); the token is
||| recycled into a construction of its size (`cell.recycle`), carried as a
||| result across a rejoin, or freed (`token.free`). A take of a value whose type proves nothing of its sharing
||| becomes the one run-time test, a match of two regions
||| (`count.match_unique`); where its token is recycled on every path into one
||| constructor's cell it fuses with those recycles (`count.take_into`), and
||| where the paths after it part the shared path gives the null token
||| (`token.null`). The ops that end their value's
||| owner (the drop, the take, the unpack, the fused take, the test) carry one
||| trait, which the linearity rule and counting's rule of what an op does
||| with a reference read. A rebuild the in-place rule
||| decided before counting is a token its check made, consumed by
||| `token.rebuild`: the check takes the cell apart before bufferization,
||| so where the cell holds arrays its take opens them (`count.take_open`),
||| which bufferization makes a take.
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

||| Used any number of times, as Idris proved it: a value a dup may give one
||| more reference to and a drop may give one up. A value used once has one
||| owner: a second reference to it would make two, and its one owner ends
||| by a take, which moves its fields out, never by a drop.
usedMany : Predicate
usedMany = predicate "isUsedMany" "a value used any number of times"

||| What a dup and a drop take: a value its count frees, used any number of
||| times.
countedMany : TypeC
countedMany = AllOfTypes (SatisfiesType countedValue ::: [SatisfiesType usedMany])
  "a value its count frees, used any number of times"

||| Freed by its count and refined to one constructor that has a cell: a
||| value a take takes out of its cell.
takeable : Predicate
takeable = predicate "isTakeable" "a counted value refined to a constructor with a cell"

||| Takeable, and holding an array as the buffer of one of its fields: a
||| value the take before bufferization takes apart, opening each such
||| array. A cell that holds none is taken by a take.
takeableWithArrays : Predicate
takeableWithArrays = predicate "isTakeableWithArrays"
  "a counted value refined to a constructor with a cell that holds an array"

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

||| An op that ends the owner its first operand is: it gives up the value's
||| reference (a drop), or moves its cell into a token and its fields out,
||| each a value of its own (a take, the fused take, the test of sharing),
||| or its fields out of a value in place (an unpack). It reads none of the
||| value's fields, so a field read before it is no second use of that
||| field, which the linearity rule reads off this trait, naming no op; and
||| it moves the value's reference on, which counting's one rule of what an
||| op does with a reference reads off it too, the fused take's among them,
||| which states no flow.
endsOwner : TraitDef
endsOwner = MkTraitDef "EndsOwner"
  (brief "ends the owner its first operand is: gives up its reference, or moves its fields out")

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
||| lowering; a rebuild and a share the in-place check writes right after
||| defunctionalization, before counting, and the take bufferization makes
||| of the check's.
explicit : Legal
explicit = between First Owned

||| `count.dup %v : T`, C++ `CountDupOp`: one more reference to a counted
||| value used any number of times, never one used once, whose one owner a
||| second reference would make two; the result holds it, counted claiming
||| nothing unless written. A fresh identity, never merged with another
||| dup. Given a bare carrier it makes a reference of its own, so a loan's
||| alias never enters one.
public export
dup : Op 1 1 0 0
dup = countingOp "count.dup" [single "value" countedMany] [result "result" anyValue] [] []
  [OurTrait adoptsCarrier] [Implements flowInterface ["getFlowEdges"]]
  (Executes [OnValues Read Count (Operands 0), OnValues Write Count (Operands 0)] [NewIdentity 0] Covered Untouched)
  counted VerifiesOp
  (Declared [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
            , Custom countedResultDirective [TypeOfGroup (ResultRef 0), TypeAgain (OperandRef 0)] ])
  [] WithDefaults []
  (brief "one more reference to a counted value")

||| `count.drop %v : T`, C++ `CountDropOp`: gives up a counted reference of
||| a value used any number of times, freeing the value with its last; never
||| one used once, whose one owner a take ends. A value typed unique frees
||| with no count read.
public export
drop : Op 1 0 0 0
drop = countingOp "count.drop" [single "value" countedMany] [] [] []
  [OurTrait endsOwner]
  [Implements flowInterface ["getFlowEdges"], Implements reuseSourceInterface ["getFreedCellType", "takeFreedToken"]]
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
||| unique through it. Its result is its operand's value, so it has the
||| operand's range: a small idr-narrow gives where a value its count frees
||| is asked keeps the bound it was proved by. A scoped result lives in the
||| lifetime it states (`in %l`), its operand's or one that lifetime
||| encloses, so its lifetime is read off the share in one step; the
||| builder that takes no lifetime states the operand's.
public export
share : Op 2 1 0 0
share = countingOp "count.share"
  [single "value" (SatisfiesType heldValue), outers] [result "result" anyValue] [] []
  [OurTrait resultCarriesOperand]
  [ Implements flowInterface ["getFlowEdges"], Implements statesLifetime statedMethods
  , Declares InferIntRange ["inferResultRangesFromOptional"] ]
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
  [OurTrait endsOwner] [ InfersTypes InferredOnly, Implements flowInterface ["getFlowEdges"]
     , Implements reuseSourceInterface ["getFreedCellType", "takeFreedToken"] ]
  (Executes [] [Consumes 0, CountsIfShared (Operands 0), NewIdentity 0, NewIdentity 1] Covered Untouched)
  explicit DeclarationOnly
  (Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))])
  [] WithDefaults
  [ MkMember OnObject "::idr::DataType" "getDataType" []
  , MkMember OnObject "::idr::Tag" "getTag" [] ]
  (brief "takes a value out of its cell, giving its token and its fields")

||| `count.take_open %v : T`, C++ `CountTakeOpenOp`: a take before
||| bufferization of a cell that holds an array, which the in-place check
||| writes where it rebuilds one: its token, then its fields, as a take
||| gives them, but a field that holds an array as its buffer, which comes
||| out as the array it is, the only array of that buffer while it lives,
||| of the buffer's shape and element.
||| The array may be written in place where the value claims its own cells
||| unshared, a claim that covers the storage of a buffer one of them holds,
||| never the elements in it: bufferization reads it off the operand's
||| grade, as it reads an array's opener's (`array.open`), so the claim
||| reaches the op that opens the array though the take ends the value, and
||| no fact beside the grade says it. Bufferization makes it a take, each
||| array the buffer the take moves out.
public export
takeOpen : Op 1 2 0 0
takeOpen = countingOp "count.take_open" [single "value" (SatisfiesType takeableWithArrays)]
  [result "token" token, results "fields" anyValue] [] []
  [OurTrait endsOwner] [InfersTypes InferredOnly, Implements flowInterface ["getFlowEdges"]]
  (Executes [] [Consumes 0, CountsIfShared (Operands 0), NewIdentity 0, NewIdentity 1] Covered Untouched)
  (between First First) DeclarationOnly
  (Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))])
  [] WithDefaults
  [ MkMember OnObject "::idr::DataType" "getDataType" []
  , MkMember OnObject "::idr::Tag" "getTag" [] ]
  (brief "takes a value out of its cell before bufferization, its arrays opened")

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
  [OurTrait endsOwner]
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
||| a take of a value whose type proves nothing of its sharing, whose token
||| every path recycles into a cell for `U`, fused with those recycles: the
||| cell for `U`, the value's own where it held the only reference, a new one
||| where it was shared, and the fields. Counting's expansion makes it the
||| match on uniqueness, so it never reaches the lowering.
public export
takeInto : Op 1 2 0 0
takeInto = countingOp "count.take_into" [single "value" (SatisfiesType takeable)]
  [result "cell" cell, results "fields" anyValue] [] []
  [OurTrait endsOwner] []
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
||| results; the value forwarded into the shared region at many uses, the
||| one edge that widens uses, and each field the shared region reads given
||| where the op's result is used once, as the unique region's field moved
||| out is (`areTypesCompatible`); the unique region's arguments the op's
||| own, made from the value.
uniqueMethods : List Ident
uniqueMethods =
  [ "getSuccessorRegions", "getEntrySuccessorOperands", "getSuccessorInputs"
  , "getRegionInvocationBounds", "areTypesCompatible" ]

||| `count.match_unique %v : T -> (R...) unique {...} shared {...}`, C++
||| `CountMatchUniqueOp`: the one run-time test of sharing, for a value whose
||| type proves nothing of it, of which exactly one region runs. The unique
||| region receives the value's token, unique and never null, and its
||| fields, moved out, at the uses the value gives them. The shared region
||| receives the value at many uses: the runtime found its cell shared, so
||| each field it reads is reached by others too, and takes its reference
||| from the value by a dup, which only a value used many admits; the
||| region then drops the value. The program's quantity is kept: the test
||| ends the owner it is given, once, and the shared region's value is a
||| new one whose sharing the test established. Never built for a value its
||| type answers.
public export
matchUnique : Op 1 1 0 2
matchUnique = countingOp "count.match_unique" [single "value" (SatisfiesType takeable)]
  [results "results" anyValue] [] [sized "unique" 1, sized "shared" 1]
  [SingleBlock, OurTrait endsOwner] [Declares RegionBranch uniqueMethods]
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
  [] [Implements flowInterface ["getFlowEdges"], Implements reuseSinkInterface ["getFilledCellType"]]
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
||| and the holes. The cell is fresh, new or recycled, so its fields are
||| written while it is filled, which nothing else reaches, and nothing but
||| its fields shares what the value reaches: the value is inferred as it is
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
  , Implements flowInterface ["getFlowEdges"]
  , Implements lifetimeUseInterface ["verifyLifetimeUse"] ]
  (Executes [OnValues Write Filling (Operands 0)] [Consumes 1, NewIdentity 0] Covered Untouched)
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

||| `cell.recycle %t : !idr.reuse_token<…> -> !idr.cell<T>`, C++
||| `CellRecycleOp`: the token's cell given up and a cell for `T` given, its
||| header written: the same memory where the token holds its cell, new
||| memory where it is null. The token, used once, is consumed here. Of one
||| size, which the program's verifier reads off the two types and the
||| target's layout, the one place that layout is at hand.
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

||| `token.free %t : !idr.reuse_token<…>`, C++ `TokenFreeOp`: frees the
||| emptied cell a token holds: with no test where the type proves it holds
||| one, a test for null where it may not. The token gives its reference up
||| here, which its flow states, as placement's takes free their tokens
||| while the markings still read the program.
public export
tokenFree : Op 1 0 0 0
tokenFree = countingOp "token.free" [single "token" token] [] [] []
  [] [Implements flowInterface ["getFlowEdges"]]
  (Executes [OnValues Free Heap (Operands 0)] [Consumes 0] Covered Untouched)
  counted DeclarationOnly
  (Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))])
  [] WithDefaults []
  (brief "frees the emptied cell a token holds")

||| `token.null : !idr.reuse_token<…>`, C++ `TokenNullOp`: the one source
||| of a null token, which the shared region of a match on uniqueness gives
||| where its token goes on to a recycle or a free that tests it. Never
||| unique.
public export
tokenNull : Op 0 1 0 0
tokenNull = countingOp "token.null" [] [result "token" token] [] []
  [] []
  (Executes [] [NewIdentity 0] Covered Untouched)
  counted VerifiesOp
  (Declared [AttrDict, Lit ":", TypeOf (OfGroup (ResultRef 0))])
  [] WithDefaults []
  (brief "the null token, the one a shared path gives")

||| `token.rebuild %t (%x : A, ...) : !idr.reuse_token<…> -> T`, C++
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
||| It makes a reference of its own of a bare carrier, so a loan's alias
||| never enters one.
public export
adopt : Op 1 1 0 0
adopt = countingOp "own.adopt" [single "value" (UpstreamType AnyRankedOrUnrankedMemRefC)]
  [result "result" anyValue] [] []
  [OurTrait noRuntimeForm, OurTrait adoptsCarrier]
  [ InfersTypes AlsoCompatible
  , Implements flowInterface ["getFlowEdges"] ]
  (Executes [] [NewIdentity 0] Covered Untouched)
  (between First Owned) DeclarationOnly
  (Declared [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
            , Lit "->", TypeOf (OfGroup (ResultRef 0)) ])
  [] WithDefaults []
  (brief "a buffer upstream made, taken over by counting")

||| `own.give %v : T`, C++ `OwnGiveOp`: a value an op of upstream's stores
||| into a buffer hands its reference to the memory, which holds it from
||| then on; the result is the value at its plain carrier, which the store
||| takes, and nothing at run time: the value's own words. The carrier is
||| the value's type with its grade forgotten, so it is inferred, never
||| written. A value used once is never given, so the store never loses its
||| quantity.
public export
give : Op 1 1 0 0
give = countingOp "own.give" [single "value" (SatisfiesType countedValue)] [result "result" anyValue] [] []
  [OurTrait noRuntimeForm] [InfersTypes InferredOnly, Implements flowInterface ["getFlowEdges"]]
  (Executes [] [Consumes 0] Covered Untouched)
  explicit VerifiesOp
  (Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))])
  [] WithDefaults []
  (brief "hands a stored value's reference to the memory that holds it")

--------------------------------------------------------------------------------
-- The area
--------------------------------------------------------------------------------

public export
declarations : Declarations
declarations =
  { ops := [ SomeOp dup, SomeOp drop, SomeOp share, SomeOp take, SomeOp takeOpen
           , SomeOp Counting.Declarations.unpack, SomeOp takeInto
           , SomeOp matchUnique, SomeOp cellNew, SomeOp cellInit, SomeOp cellRecycle
           , SomeOp tokenFree, SomeOp tokenNull, SomeOp tokenRebuild, SomeOp adopt, SomeOp give ]
  , types := [SomeType cellType, SomeType reuseTokenType]
  , directives := [sharedDirective, cellResultDirective, cellDestsDirective]
  , predicates := [countedValue, usedMany, takeable, takeableWithArrays, unpackable, tokenValue, heldValue]
  , interfaces := [reuseSourceInterface, reuseSinkInterface]
  , traits := [endsOwner]
  } nothing
