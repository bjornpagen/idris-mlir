-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The `idr` dialect, whole: its settings, and the union of what each area
||| of the specification declares, in a fixed order (no area is found by
||| listing a directory), with the decisions that span them. Every `.td` of
||| ours, every generated C++ table and the Idris modules the frontend
||| cannot import are printed from this by the generator; nothing else
||| states the dialect.
module IdrisMLIR.Spec

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Core.Verdict
import IdrisMLIR.Spec.Pipeline.Pass
import IdrisMLIR.Spec.Effects.Declaration

import IdrisMLIR.Spec.Effects.Declarations as Effects
import IdrisMLIR.Spec.Functions.Declarations as Functions
import IdrisMLIR.Spec.Families.Declarations as Families
import IdrisMLIR.Spec.Grades.Declarations as Grades
import IdrisMLIR.Spec.Lifetimes.Declarations as Lifetimes
import IdrisMLIR.Spec.Control.Declarations as Control
import IdrisMLIR.Spec.Runtime.Declarations as Runtime
import IdrisMLIR.Spec.Arrays.Declarations as Arrays
import IdrisMLIR.Spec.Ops.Declarations as Ops
import IdrisMLIR.Spec.Counting.Declarations as Counting
import IdrisMLIR.Spec.Closures.Declarations as Closures
import IdrisMLIR.Spec.Tail.Declarations as Tail

-- The modules each area's declarations are written from, named here too so
-- the root names every module of the specification.
import IdrisMLIR.Spec.Closures.Memo
import IdrisMLIR.Spec.Counting.Types
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Families.Layout
import IdrisMLIR.Spec.Families.Ops
import IdrisMLIR.Spec.Families.Terms
import IdrisMLIR.Spec.Families.Types
import IdrisMLIR.Spec.Functions.Copy
import IdrisMLIR.Spec.Functions.LivesIn
import IdrisMLIR.Spec.Functions.Tail
import IdrisMLIR.Spec.Runtime.Clocks
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Runtime.Handles
import IdrisMLIR.Spec.Runtime.Helpers
import IdrisMLIR.Spec.Runtime.Layout

-- The modules that declare ops which reach the root only through an area's
-- declarations: `namesDistinct` reduces each op's name only where the
-- module defining it is visible.
import IdrisMLIR.Spec.Control.Matches
import IdrisMLIR.Spec.Control.Joins
import IdrisMLIR.Spec.Arrays.Memory
import IdrisMLIR.Spec.Arrays.Generating
import IdrisMLIR.Spec.Ops.Shapes
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Spec.Ops.Scalars
import IdrisMLIR.Spec.Ops.Strings
import IdrisMLIR.Spec.Ops.Bigs
import IdrisMLIR.Spec.Ops.Checks
import IdrisMLIR.Spec.Ops.IO
import IdrisMLIR.Spec.Ops.Platform

import Data.List
import Data.List.Elem
import Data.List1
import Data.So
import Data.Vect

%default total

||| The dialect's own settings.
public export
dialect : DialectDef
dialect = MkDialectDef
  { summary = "Monomorphic Idris programs: families, closures, matches, strings and bigs"
  , description = "The dialect holds only what upstream's dialects do not mean: Idris's data\nas the families it checked, its grades in types, lifetimes as values, join\npoints, counting, and the runtime's values. Every fact a pass reads is an\nop's property or a type, never a discardable attribute."
  -- Bufferization with the rest: a builtin tensor is tensor-like, its
  -- aliases followed through bufferization's interfaces, only once that
  -- dialect is loaded, so a module read as text holds what the loan check
  -- follows as one read by the pipeline does.
  , loads = [LoadsArith, LoadsUB, LoadsLLVM, LoadsBufferization]
  , members =
      [ MkMember OnObject "void" "registerTypes" []
      , MkMember OnObject "void" "registerValueFacts" [] ]
  }

||| A binder of the program as Idris wrote it, by the definition that binds
||| it and its position there: the typed identity a quantity check keys a
||| binder by, which the frontend fuses into the binder's location.
public export
binderAttr : AttrDef 2
binderAttr = MkAttrDef
  { mnemonic = "binder"
  , stages = Always
  , params = [ MkParameter "definition" AttrValue AlwaysWritten "the definition that binds it, by its symbol"
             , MkParameter "index" CountValue AlwaysWritten "its position among the definition's binders" ]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ",", ParamAt 1, Keyword ">"]
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , doc = brief "a binder of the program, by its definition and position"
  }

||| The transform op the schedule library uses: upstream's transform dialect
||| has no arithmetic on its params, and its vectorize op takes one param per
||| dimension, so no script can divide the target's vector width by a loop's
||| widest word or name the sizes of a loop of any rank; this op decides them
||| and computes the loop on the lanes they give. It goes when upstream can
||| state both. Its effects are the transform interface's own.
public export
vectorizeLanes : Op 1 1 0 0
vectorizeLanes = MkOp
  { home = InTransform (ident "idr" ::: [ident "target", ident "VectorizeLanesOp"])
  , mnemonic = "idr.vectorize_lanes"
  , ins = [single "target" (UpstreamType TransformHandleC)]
  , outs = [result "vectorized" (UpstreamType TransformHandleC)]
  , attrs = []
  , regions = []
  , traits = [ReportTrackingListenerFailures]
  , interfaces = [Declares TransformOp ["apply"], Declares TransformEffects ["getEffects"]]
  , effects = Definition
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", FunctionalType OfOperands OfResults]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "Computes each loop over an array on the target's vector lanes"
      "For each linalg.generic of `target` on buffers with a parallel dimension that the\nvectorizer takes: lanes along its last parallel dimension (the module's\nmax_vector_op_width for its CPU over the widest word the loop computes) and one\nelement along every other, the lane dimension's tile loop peeled, the full tiles\nvectorized without masks and the last one masked. Any other op, or a loop the\nvectorizer refuses, is left as it is. `vectorized` holds each function that now\ncomputes on lanes, once. Consumes `target`."
  }

||| The kind of word a runtime component is, which decides how its count is
||| kept and so which runtime entry counts it: no count, or one of the
||| counted kinds the runtime has an entry for. The counted kinds are the
||| runtime's own, so a kind the runtime adds is a case of this, and of the
||| lattice the lowering joins kinds in.
public export
data ComponentWord = NoCount | CountedAs WordKind

public export
componentWordClosed : Closed ComponentWord
componentWordClosed = MkClosed
  { name = ident "Word"
  , shape = OneOf
  , every = NoCount ::: map CountedAs Helpers.words
  , complete = \case
      NoCount => Here
      CountedAs Helpers.CellWord => There Here
      CountedAs Helpers.MaybeCellWord => There (There Here)
      CountedAs Helpers.BigWord => There (There (There Here))
      CountedAs Helpers.AnyWord => There (There (There (There Here)))
  , describe = \case
      NoCount => MkCase (ident "Uncounted") (word "uncounted" ::: []) (line "no count is kept of it")
      CountedAs Helpers.CellWord => MkCase (ident "Cell") (word "cell" ::: []) (line "a pointer to a cell, never null")
      CountedAs Helpers.MaybeCellWord => MkCase (ident "MaybeCell") (word "maybe_cell" ::: []) (line "a pointer to a cell, or null where a constructor leaves the slot empty")
      CountedAs Helpers.BigWord => MkCase (ident "Big") (word "big" ::: []) (line "a big's word: a small integer or a cell's address")
      CountedAs Helpers.AnyWord => MkCase (ident "Any") (word "any" ::: []) (line "a slot that may be any of these")
  , doc = brief (line "the kind of word a runtime component is")
  }

||| The least kind two kinds both stand in: no count is the bottom, a cell
||| and a slot that may be empty join to the latter, and any other two
||| different kinds join to any.
public export
joinWord : ComponentWord -> ComponentWord -> ComponentWord
joinWord NoCount b = b
joinWord a NoCount = a
joinWord (CountedAs x) (CountedAs y) = CountedAs (joinCounted x y)
  where
    joinCounted : WordKind -> WordKind -> WordKind
    joinCounted Helpers.CellWord Helpers.CellWord = Helpers.CellWord
    joinCounted Helpers.CellWord Helpers.MaybeCellWord = Helpers.MaybeCellWord
    joinCounted Helpers.MaybeCellWord Helpers.CellWord = Helpers.MaybeCellWord
    joinCounted Helpers.MaybeCellWord Helpers.MaybeCellWord = Helpers.MaybeCellWord
    joinCounted Helpers.BigWord Helpers.BigWord = Helpers.BigWord
    joinCounted _ _ = Helpers.AnyWord

||| The kinds, and their join as a table the lowering reads by load.
public export
wordsHeader : Header
wordsHeader = MkHeader (ident "Words")
  [ ( Nested (ident "layout" ::: [])
    , [ EnumOf (enumDef componentWordClosed)
      , Array2 (ident "wordJoin") (EnumColumn (enumDef componentWordClosed))
          (map (\a => map (\b => CaseCell (caseRef componentWordClosed (joinWord a b))) kinds) kinds)
          (line "the least kind both stand in, by the kinds' positions") ] ) ]
  (brief (line "the kinds of word a runtime component is, and their lattice"))
  where
    kinds : List ComponentWord
    kinds = forget componentWordClosed.every

||| `builtin.module`, which the frontend writes around every program and
||| which stands at every stage: upstream's record holds its meaning.
public export
builtinModule : Admitted
builtinModule = MkAdmitted Builtin "ModuleOp" "Builtin_ModuleOp" Always FrontendWrites [] [] Nothing UpstreamFold

||| A refusal of the program, which the frontend writes into the module in
||| place of a program, one per refusal, at the module's top level: its rule
||| a case of the closed set of rules, held as a property, so the verdict is
||| read from the rule and never from text; what it says beside the rule's
||| phrase; and its site, the op's location. The driver reports each and
||| compiles nothing, so a refused module never enters the pipeline and the
||| op stands at the frontend's stage alone. Nothing runs it, so it declares
||| no effect.
public export
refusalOp : Op 0 0 2 0
refusalOp = MkOp
  { home = InIdr
  , mnemonic = "refusal"
  , ins = []
  , outs = []
  , attrs =
      [ property "rule"
          (EnumProperty (imported Rules.ruleClosed
             (MkSource ("IdrisMLIR" ::: ["Spec", "Core", "Rules"]) "SomeRule"
                       ("IdrisMLIR" ::: ["Spec", "Core", "Rules"]) "ruleClosed")))
      , attr "message" (UpstreamAttr StrAttrC) ]
  , regions = []
  , traits = [HasUpstreamParent (ident "mlir" ::: [ident "ModuleOp"])]
  , interfaces = []
  , effects = Definition
  , speculation = NotSpeculatable
  , stages = between Higher Higher
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared [ValueOf (AttrRef 0), ValueOf (AttrRef 1), AttrDict]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a refusal of the program, which the driver reports in place of compiling it"
  }

||| What the specification's core declares of the dialect: the stages a
||| program passes through, the refusal rules, their facts and the op a
||| refusal is, the value facts' interface and the one an op's structure
||| is asked through, the traits of ours an op may carry, and the module a
||| program is.
public export
core : Declarations
core = { ops := [ SomeOp vectorizeLanes, SomeOp refusalOp ]
       , admitted := [ builtinModule ]
       , enums := [ enumDef stageClosed, enumDef categoryClosed, enumDef Rules.ruleClosed ]
       , interfaces := [ valueFactsInterface, structureInterface ]
       , traits := [ resultCarriesOperand, sameValue, eliminatesOperand ]
       , attributes := [ SomeAttr binderAttr ]
       , headers := [ MkHeader "Rules" [(DialectNamespace, [TableOf Rules.ruleTable])]
                        (brief "the fact of each refusal rule: its category")
                    , wordsHeader
                    , MkHeader "StageFacts"
                        [(DialectNamespace, [ EnumOf (enumDef closuresClosed), EnumOf (enumDef countingClosed)
                                            , EnumOf (enumDef functionsClosed), EnumOf (enumDef tailsClosed)
                                            , EnumOf (enumDef tailLayoutsClosed), EnumOf (enumDef edgeHoldsClosed)
                                            , TableOf stageFacts ])]
                        (brief "what each stage of a program implies of its functions")
                    , verdictHeader ]
       } nothing

||| Every area's declarations, in the order they are printed.
public export
areas : List Declarations
areas =
  [ core
  , Effects.declarations
  , Functions.declarations
  , Families.declarations
  , Grades.declarations
  , Lifetimes.declarations
  , Control.declarations
  , Runtime.declarations
  , Arrays.declarations
  , Ops.declarations
  , Counting.declarations
  , Closures.declarations
  , Tail.declarations
  ]

||| The dialect's declarations, whole.
public export
declarations : Declarations
declarations = foldr union nothing areas

||| Every op's name in the IR. The root's own declarations, which every area
||| module's share a name with.
public export
opNames : List String
opNames = map (\(SomeOp op) => opName op) (Spec.declarations).ops

||| Whether no string occurs twice.
public export
distinctStrings : List String -> Bool
distinctStrings [] = True
distinctStrings (x :: xs) = not (elem x xs) && distinctStrings xs

||| No two ops share a name, so no two share a class: a duplicate fails
||| here, at the specification's build, before any `.td` exists.
0 namesDistinct : So (distinctStrings Spec.opNames)
namesDistinct = Oh
