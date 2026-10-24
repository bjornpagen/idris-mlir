-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Every file the generator writes, in a fixed order, each a pure function
||| of the specification: no file is read, nothing is sorted, no time, path,
||| host or target is consulted. The order is the outputs' and the
||| manifest's.
module IdrisMLIR.Spec.Generator.Outputs

import IdrisMLIR.Spec
import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Pipeline.Pass
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Pipeline.Pipeline
import IdrisMLIR.Spec.Generator.Render
import IdrisMLIR.Spec.Generator.Ods
import IdrisMLIR.Spec.Generator.Cpp
import IdrisMLIR.Spec.Generator.Bytecode
import IdrisMLIR.Spec.Generator.Idris
import IdrisMLIR.Spec.Generator.Package
import IdrisMLIR.Spec.Generator.Wire
import IdrisMLIR.Spec.Ops.Checks
import IdrisMLIR.Spec.Ops.Shapes

import Data.Fin
import Data.List
import Data.List1
import Data.Vect

%default total

||| A file of the generated tree.
export
generated : String -> Path
generated f = "foreign" ::: ["idr", "include", "idr", "IR", "Generated", f]

||| A `.td` file: the banner, its guard, its includes, its body.
export
tdFile : String -> List String -> Lines -> String
tdFile guard includes body =
  render (banner slashComment
          ++ ["#ifndef " ++ guard, "#define " ++ guard, ""]
          ++ map (\i => "include " ++ quoted i) includes
          ++ [""] ++ body
          ++ ["#endif // " ++ guard])

export
allOps : List AnyOp
allOps = declarations.ops

export
isOurs : AnyOp -> Bool
isOurs (SomeOp op) = case op.home of
  InIdr => True
  InTransform _ => False

||| The upstream interfaces' files the allOps and types name.
export
interfaceIncludes : List String
interfaceIncludes = nub (concatMap fromOp allOps ++ concatMap fromType declarations.types)
  where
    files : List InterfaceUse -> List String
    files [] = []
    files (Declares u _ :: us) = upInterfaceInclude u :: files us
    files (InfersTypes _ :: us) = inferTypeInclude :: files us
    files (Implements _ _ :: us) = files us
    fromOp : AnyOp -> List String
    fromOp (SomeOp op) = files op.interfaces
    fromType : AnyTypeDef -> List String
    fromType (SomeType t) = files t.interfaces

export
baseTd : String
baseTd =
  tdFile "IDR_GENERATED_BASE" (odsBaseIncludes ++ interfaceIncludes)
    ( dialectOds dialect
      ++ baseClasses
      ++ concatMap enumOds declarations.enums
      ++ concatMap traitDefOds declarations.traits
      ++ concatMap resourceOdsDef declarations.resources
      ++ [""] )

export
interfacesTd : String
interfacesTd =
  tdFile "IDR_GENERATED_INTERFACES" ["mlir/IR/OpBase.td", "idr/IR/Generated/IdrBase.td"]
    (concatMap interfaceOds declarations.interfaces)

export
typesTd : String
typesTd =
  tdFile "IDR_GENERATED_TYPES" ["idr/IR/Generated/IdrBase.td", "idr/IR/Generated/IdrInterfaces.td"]
    (concatMap anyTypeOds declarations.types ++ concatMap anyAttrOds declarations.attributes)

export
opsTd : String
opsTd =
  tdFile "IDR_GENERATED_OPS" ["idr/IR/Generated/IdrBase.td", "idr/IR/Generated/IdrInterfaces.td", "idr/IR/Generated/IdrTypes.td"]
    (concatMap anyOpOds (filter isOurs allOps))

export
transformTd : String
transformTd =
  tdFile "IDR_GENERATED_TRANSFORM_OPS"
    [ "mlir/Dialect/Transform/IR/TransformDialect.td"
    , "mlir/Dialect/Transform/Interfaces/TransformInterfaces.td"
    , "mlir/Interfaces/SideEffectInterfaces.td" ]
    (concatMap anyOpOds (filter (not . isOurs) allOps))

export
passesTd : String
passesTd =
  tdFile "IDR_GENERATED_PASSES" ["mlir/Pass/PassBase.td"]
    (concatMap passOds (filter registered passes))
  where
    registered : Pass -> Bool
    registered p = case p.construction of
      Registered => True
      MadeBy _ _ => False

export
innerPassesTd : String
innerPassesTd =
  tdFile "IDR_GENERATED_INNER_PASSES" ["mlir/Pass/PassBase.td"]
    (concatMap passOds (filter inner passes))
  where
    inner : Pass -> Bool
    inner p = case p.construction of
      Registered => False
      MadeBy _ _ => True

||| The record every admitted op is, which the D51 backend reads. Its laws
||| are not here: the e-graph's rules and the laws' table are printed from
||| the specification directly. Its guards are, since the backend prints the
||| builder that places them.
export
admittedBaseTd : String
admittedBaseTd =
  tdFile "IDR_GENERATED_ADMITTED_BASE" ["mlir/IR/OpBase.td"]
    [ "// A guard an admitted op takes, which its Idris builder gives with it:"
    , "// the guard op's dialect, as the specification names it, and its name"
    , "// there; the positions among upstream's operand groups of those it is"
    , "// given (the one it guards first); and the cause its crash names, by"
    , "// its position in the closed set of causes, which the module and name"
    , "// give, so the builder writes the cause typed, by `caseAt`; and what a"
    , "// module that writes a case by `caseAt` imports, the Idris printer's"
    , "// own list, so the backend does not restate it."
    , "class IdrAdmittedGuard<string dialect, string check, list<int> given,"
    , "                       string causeHome, string causeSet, int cause> {"
    , "  string guardDialect = dialect;"
    , "  string guardName = check;"
    , "  list<int> operandGroups = given;"
    , "  string causeModule = causeHome;"
    , "  string causeSetName = causeSet;"
    , "  int causeNumber = cause;"
    , "  list<string> caseImports = [" ++ joinWith ", " (map quoted caseImports) ++ "];"
    , "}"
    , ""
    , "// An upstream op the dialect admits: upstream's own record, the alias"
    , "// its C++ class is known by among every dialect's admitted ops, the"
    , "// stages it may stand at, whether the frontend writes it (its Idris"
    , "// builder is printed), and the guards that builder gives it."
    , "class IdrAdmitted<Op upstream, string aliasName, string first, string last,"
    , "                  int written, list<IdrAdmittedGuard> guarded> {"
    , "  Op op = upstream;"
    , "  string alias = aliasName;"
    , "  string firstStage = first;"
    , "  string lastStage = last;"
    , "  int frontendWrites = written;"
    , "  list<IdrAdmittedGuard> guards = guarded;"
    , "}"
    , "" ]

||| A guard of an admitted op, as its record's argument: its kind's op by
||| the dialect it is defined in and its name there, its groups, and its
||| cause by the closed set's module and name and its position there.
admittedGuard : Guard Nat -> String
admittedGuard g =
  let checkOp = guardOpOf g.check
  in "IdrAdmittedGuard<" ++ quoted (identText (dialectName (homeDialect checkOp.home))) ++ ", "
       ++ quoted (mnemonicText checkOp.mnemonic) ++ ", ["
       ++ joinWith ", " (map decimal (toList g.given)) ++ "], "
       ++ quoted (moduleName causeEnum.source.setHome) ++ ", " ++ quoted (identText causeEnum.source.setName) ++ ", "
       ++ decimal (position causeClosed g.cause) ++ ">"

export
admittedRow : Admitted -> String
admittedRow a =
  let (first, last) = bounds a.legal
      written = case a.writer of
                  FrontendWrites => "1"
                  PassesOnly => "0"
  in "def IdrAdmitted_" ++ identText a.alias ++ " : IdrAdmitted<" ++ identText a.upstreamRecord ++ ", "
       ++ quoted (identText a.alias) ++ ", " ++ quoted first ++ ", " ++ quoted last ++ ", " ++ written ++ ", ["
       ++ joinWith ", " (map admittedGuard a.guards) ++ "]>;"
  where
    name : Stage -> String
    name s = identText (stageClosed.describe s).name
    bounds : Legal -> (String, String)
    bounds Always = ("Higher", "Lowered")
    bounds (Between f l _) = (name f, name l)

||| Whether two dialects are one: their positions in the closed set.
sameDialect : Dialect -> Dialect -> Bool
sameDialect x y = position dialectClosed x == position dialectClosed y

||| The ops the specification admits from a dialect, in declaration order.
admittedOf : Dialect -> List Admitted
admittedOf d = filter (\a => sameDialect a.dialect d) declarations.admitted

||| Whether the frontend writes the op.
frontendWrites : Admitted -> Bool
frontendWrites a = case a.writer of
  FrontendWrites => True
  PassesOnly => False

||| The upstream dialects that admit an op, in the dialects' order: each has
||| an admitted record file, read by one run of the backend apiece, and a
||| dialect that admits nothing has none.
export
admittingDialects : List Dialect
admittingDialects = filter (not . null . admittedOf) upstreamDialects

||| The upstream dialects the frontend writes an op of, in the dialects'
||| order: the ones the Idris side holds a vocabulary of, generated from
||| each one's admitted record file.
export
writtenDialects : List Dialect
writtenDialects = filter (any frontendWrites . admittedOf) upstreamDialects

||| One admitted record file per upstream dialect that admits an op.
export
admittedTd : Dialect -> (Path, String)
admittedTd d =
  ( generated ("IdrAdmitted" ++ identText (dialectName d) ++ ".td")
  , tdFile ("IDR_GENERATED_ADMITTED_" ++ pack (map up (unpack (identText (dialectName d)))))
      (forget (odsIncludes d) ++ ["idr/IR/Generated/IdrAdmittedBase.td"])
      (map admittedRow (admittedOf d)) )
  where
    up : Char -> Char
    up c = if lower c then chr (ord c - 32) else c

||| The dialects the frontend writes, one per line, as the script that
||| generates the Idris side's vocabulary of each reads them: its namespace
||| in the IR, its name (of its admitted record file and its modules), and
||| its bytecode records under MLIR's include directory, or `-` where the
||| frontend writes its types and attributes as text.
export
writtenDialectsList : String
writtenDialectsList =
  render (banner hashComment
          ++ hashComment ["namespace, name, bytecode records: the upstream dialects the frontend writes."]
          ++ map row writtenDialects)
  where
    row : Dialect -> String
    row d = wordText (namespaceWord d) ++ " " ++ identText (dialectName d) ++ " " ++ maybe "-" id (bytecodeRecords d)

||| The dialect's own allOps, which every table and the frontend's builders
||| hold; an op the dialect defines in upstream's transform dialect is
||| printed into its own file alone.
export
ourOps : List AnyOp
ourOps = filter isOurs allOps

||| Why an op's result-type rules cannot be printed, if they cannot: a rule
||| that reads or fixes a group of other than one value, since the C++ and
||| the builder read one type each; a fixed type the result's constraint is
||| not, which ODS would not build; and a hand inference beside the rules,
||| which upstream's ODS takes over the rules.
typingRefusals : Op i o a r -> List String
typingRefusals op = case op.typing of
  StatedTypes => []
  InferredTypes rules =>
    concatMap (\(y, rule) => refused y rule) (toList (zip op.outs rules))
    ++ concatMap handInference op.interfaces
  where
    fixedIs : Buildable -> TypeC -> Bool
    fixedIs BuiltI1 (UpstreamType I1C) = True
    fixedIs BuiltI8 (UpstreamType I8C) = True
    fixedIs BuiltI16 (UpstreamType I16C) = True
    fixedIs BuiltI32 (UpstreamType I32C) = True
    fixedIs BuiltI64 (UpstreamType I64C) = True
    fixedIs BuiltIndex (UpstreamType IndexC) = True
    fixedIs BuiltF64 (UpstreamType F64C) = True
    fixedIs BuiltNone (UpstreamType NoneTypeC) = True
    fixedIs _ _ = False
    said : Result -> String -> List String
    said y why = [opName op ++ ": the type rule of " ++ identText y.name ++ " " ++ why]
    readsOne : Result -> Fin i -> List String
    readsOne y g = case (y.arity, (index g op.ins).arity) of
      (Single, Single) => []
      _ => said y "reads or fixes a group of other than one value"
    refused : Result -> TypeRule i -> List String
    refused y (OperandType g) = readsOne y g
    refused y (ElementTypeOf g) = readsOne y g
    refused y (FixedType b) =
      (case y.arity of
         Single => []
         _ => said y "fixes a group of other than one value")
      ++ (if fixedIs b y.type then [] else said y "fixes a type its constraint is not")
    handInference : InterfaceUse -> List String
    handInference (InfersTypes _) = [opName op ++ ": its result types have rules and a hand inference"]
    handInference _ = []

||| An enum property over a set of cases, which a builder would encode as a
||| mask no frontend value holds; an enum property is one case.
setProperties : Op i o a r -> List String
setProperties op = concatMap refused (toList op.attrs)
  where
    setOf : ImportedEnum -> Attr -> List String
    setOf e x = case e.enum.shape of
      OneOf => []
      SetOf => [opName op ++ ": the property " ++ identText x.name ++ " holds a set of cases"]
    refused : Attr -> List String
    refused x = case x.kind of
      AProperty (EnumProperty e) => setOf e x
      AProperty (DefaultedEnumProperty e _) => setOf e x
      _ => []

||| The one-carrier trait compares its operands' values, one each: a group
||| of any number, or of none, has no value to compare.
carrierGroups : Op i o a r -> List String
carrierGroups op = concatMap refused op.traits
  where
    groupOfOne : Operand -> List String
    groupOfOne x = case x.arity of
      Single => []
      _ => [opName op ++ ": the one-carrier trait reads " ++ identText x.name ++ ", a group that may hold other than one value"]
    refused : Trait i o -> List String
    refused SameCarrierOperands = concatMap groupOfOne (toList op.ins)
    refused _ = []

||| Whether an op eliminates a string: it carries `EliminatesOperand`, and
||| its first operand is a string read in place.
eliminatesString : Op i o a r -> Bool
eliminatesString op = any eliminates op.traits && readsString op.ins
  where
    eliminates : Trait i o -> Bool
    eliminates (OurTrait t) = t.name == eliminatesOperand.name
    eliminates _ = False
    readsString : Vect n Operand -> Bool
    readsString [] = False
    readsString (x :: _) = case x.type of
      SatisfiesType p => p.name == strReadP.name
      _ => False

||| The tables that name `out` by its runtime function: each template an op
||| specializes with a constant that is `out`'s entry, an op of the
||| dialect's by its mnemonic.
tablesNaming : Op i o a r -> List AnyOp -> List Ident
tablesNaming out ops =
  concatMap (\(SomeOp op) => map (.template) (filter (any (names . snd) . (.constants)) op.specializations)) ops
  where
    names : Constant -> Bool
    names (OpEntry m) = case out.home of
      InIdr => out.mnemonic == m
      InTransform _ => False
    names _ = False

||| The string lowering takes an op that eliminates a string, wherever it
||| finds one, for the one output its tables are written against: a list's
||| pack or concat made only to be written is written an element at a time,
||| and a number's show by its writer, where that output stood, the
||| writer's call told that output's effects. An output's stream is its
||| identity alone, so a second output of a string would be written as the
||| first, silently. Until an output states its stream, exactly one op
||| eliminates a string, and a table names it by its runtime function, as
||| a list's table names the writer of a string element. A show's writer
||| names no op: that it writes where the output would is the runtime's,
||| and the row its call is told is the lowering's.
stringOutputRefusals : List AnyOp -> List String
stringOutputRefusals ops = case filter (\(SomeOp op) => eliminatesString op) ops of
  [] => ["no op eliminates a string, where the string lowering's tables are written against one output of a string"]
  [SomeOp out] => case tablesNaming out ops of
    [] => [opName out ++ ": eliminates a string, but no table names it by its runtime function, so the string lowering's tables are written against another output"]
    _ :: _ => []
  outs =>
    [ joinWith ", " (map (\(SomeOp op) => opName op) outs)
      ++ ": each eliminates a string, where the string lowering writes every output of a string as the one its tables are written against; exactly one may, until an output states its stream" ]

||| What the generator refuses to print, said for the one who wrote the
||| specification: each pair rule over a group that may hold other than one
||| value, each op whose result-type rules cannot be printed, each enum
||| property over a set of cases, each one-carrier trait over a group that
||| may hold other than one value, and outputs of a string other than the
||| one the string lowering's tables are written against.
export
refusals : List String
refusals =
  map (\(op, rule) => op ++ ": the pair rule " ++ identText rule ++ " reads a group that may hold other than one value")
      (unpairedRules allOps)
  ++ concatMap (\(SomeOp op) => typingRefusals op) allOps
  ++ concatMap (\(SomeOp op) => setProperties op) allOps
  ++ concatMap (\(SomeOp op) => carrierGroups op) allOps
  ++ stringOutputRefusals allOps

||| Every op key: ours, then the admitted upstream allOps.
export
opKeys : List OpKey
opKeys = map OurOp ourOps ++ map AdmittedOp declarations.admitted

||| Every file the generator writes, in order.
export
generate : List (Path, String)
generate =
  [ (generated "IdrBase.td", baseTd)
  , (generated "IdrInterfaces.td", interfacesTd)
  , (generated "IdrTypes.td", typesTd)
  , (generated "IdrOps.td", opsTd)
  , (generated "IdrTransformOps.td", transformTd)
  , (generated "IdrBytecode.td", render (bytecodeOds declarations.types declarations.attributes))
  , (generated "IdrPasses.td", passesTd)
  , (generated "IdrInnerPasses.td", innerPassesTd)
  , (generated "IdrAdmittedBase.td", admittedBaseTd) ]
  ++ map admittedTd admittingDialects
  ++ [ (generated "AdmittedClasses.h.inc", render (admittedClassesHeader admittingDialects))
     , (generated "WrittenDialects.txt", writtenDialectsList)
     , (generated "EnumTraits.h.inc", render (odsEnumTraits declarations.enums))
     , (generated "Storages.h.inc", render (storagesHeader declarations.types declarations.attributes))
     , (generated "Defaults.h.inc", render (defaultsHeader declarations.interfaces))
     , (generated "PassDialects.h.inc", render (passDialectsHeader passes))
     , (generated "OpIndex.h.inc", render (opIndexHeader opKeys))
     , (generated "Guards.h.inc", render (guardsHeader ourOps))
     , (generated "InlineMeanings.h.inc", render (inlineMeaningsHeader ourOps))
     , (generated "RuntimeAbi.h.inc", render (runtimeAbi ourOps declarations.helpers))
     , ("runtime" ::: ["Generated", "idris_rt_ops.h"], render (runtimeOps ourOps declarations.helpers))
     , (generated "Resources.h.inc", render (resourcesHeader declarations.resources))
     , (generated "Effects.h.inc", render (effectsHeader ourOps))
     , (generated "Effects.cpp.inc", render (effectsDefinitions ourOps))
     , (generated "Wire.cpp.inc", render (wireDefinitions declarations.types declarations.attributes))
     , (generated "SkeletonRules.h.inc", render (skeletonRulesHeader declarations.skeleton))
     , (generated "Rewrites.h.inc", render (rewritesHeader declarations.rewrites ourOps declarations.admitted declarations.skeleton))
     , (generated "Laws.h.inc", render (lawsHeader ourOps declarations.admitted))
     , (generated "Hooks.h.inc", render (hooksHeader declarations.directives declarations.predicates declarations.interfaces declarations.types declarations.attributes ourOps))
     , (generated "Pipeline.h.inc", render (pipelineHeader (fst (stepsOf Higher [] pipeline))))
     , (generated "ApplyGroups.h.inc", render (applyGroupsHeader (groupsOf Higher pipeline)))
     , (generated "Actions.h.inc", render (actionsHeader everyAction)) ]
  ++ map (\t => (generated (identText t ++ ".h.inc"), render (specializationHeader declarations.headers t ourOps))) (templatesOf ourOps)
  ++ map areaHeader declarations.headers
  ++ [ ("compiler" ::: ["src", "IdrisMLIR", "Dialect", "Idr.idr"], render (buildersModule ourOps))
     , ("compiler" ::: ["src", "IdrisMLIR", "Encoding", "Wire.idr"], render (wireModule (compositesOf declarations.types declarations.attributes)))
     , ("compiler" ::: ["src", "IdrisMLIR", "Encoding", "Idr.idr"], render (encodersModule declarations.types declarations.attributes))
     , (packagePath, packageText) ]
