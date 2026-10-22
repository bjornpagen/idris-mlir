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

import Data.List
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
  , loads = [LoadsArith, LoadsUB, LoadsLLVM]
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
  , params = [ MkParameter "definition" AttrValue AlwaysWritten "the definition that binds it, by its symbol"
             , MkParameter "index" CountValue AlwaysWritten "its position among the definition's binders" ]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ",", ParamAt 1, Keyword ">"]
  , typed = Untyped
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
  , interfaces = [Declares TransformOp [], Declares TransformEffects []]
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

||| What the specification's core declares of the dialect: the stages a
||| program passes through, the refusal rules and their facts, the value
||| facts' interface, and the traits of ours an op may carry.
public export
core : Declarations
core = { ops := [ SomeOp vectorizeLanes ]
       , enums := [ enumDef stageClosed, enumDef categoryClosed, enumDef scopeClosed, enumDef ruleClosed ]
       , interfaces := [ valueFactsInterface ]
       , traits := [ resultCarriesOperand, sameValue ]
       , attributes := [ SomeAttr binderAttr ]
       , headers := [ MkHeader "Rules" [(ident "idr" ::: [], [TableOf ruleTable])]
                        (brief "the facts of each refusal rule: its category and where it is decided")
                    , MkHeader "StageFacts"
                        [(ident "idr" ::: [], [ EnumOf (enumDef closuresClosed), EnumOf (enumDef holdsClosed)
                                              , EnumOf (enumDef countingClosed), EnumOf (enumDef functionsClosed)
                                              , TableOf stageFacts ])]
                        (brief "what each stage of a program implies of its functions") ]
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
  ]

||| The dialect's declarations, whole.
public export
declarations : Declarations
declarations = foldr union nothing areas

||| Every op's name in the IR.
public export
opNames : List String
opNames = map (\(SomeOp op) => opName op) declarations.ops

||| Whether no string occurs twice.
public export
distinctStrings : List String -> Bool
distinctStrings [] = True
distinctStrings (x :: xs) = not (elem x xs) && distinctStrings xs

||| No two ops share a name, so no two share a class: a duplicate fails
||| here, at the specification's build, before any `.td` exists.
0 namesDistinct : So (distinctStrings opNames)
namesDistinct = Oh
