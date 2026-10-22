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
import IdrisMLIR.Spec.Pipeline.Pipeline
import IdrisMLIR.Spec.Generator.Render
import IdrisMLIR.Spec.Generator.Ods
import IdrisMLIR.Spec.Generator.Cpp
import IdrisMLIR.Spec.Generator.Bytecode
import IdrisMLIR.Spec.Generator.Idris
import IdrisMLIR.Spec.Generator.Wire

import Data.List
import Data.List1

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
    files (_ :: us) = files us
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
    , "// the guard op's name, the positions among upstream's operand groups of"
    , "// those it is given (the one it guards first), and the number of the"
    , "// cause its crash names."
    , "class IdrAdmittedGuard<string check, list<int> given, int cause> {"
    , "  string guardOp = check;"
    , "  list<int> operandGroups = given;"
    , "  int causeNumber = cause;"
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

||| A guard of an admitted op, as its record's argument.
admittedGuard : Guard Nat -> String
admittedGuard g =
  "IdrAdmittedGuard<" ++ quoted ("idr." ++ mnemonicText g.check) ++ ", ["
    ++ joinWith ", " (map decimal (forget g.given)) ++ "], " ++ decimal (caseNumber g.cause) ++ ">"

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

||| Whether two dialects are one.
sameDialect : Dialect -> Dialect -> Bool
sameDialect x y = identText (dialectName x) == identText (dialectName y)

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
      [odsInclude d, "idr/IR/Generated/IdrAdmittedBase.td"]
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
     , (generated "Actions.h.inc", render (actionsHeader everyAction)) ]
  ++ map (\t => (generated (identText t ++ ".h.inc"), render (specializationHeader declarations.headers t ourOps))) (templatesOf ourOps)
  ++ map areaHeader declarations.headers
  ++ [ ("compiler" ::: ["src", "IdrisMLIR", "Dialect", "Idr.idr"], render (buildersModule ourOps))
     , ("compiler" ::: ["src", "IdrisMLIR", "Encoding", "Wire.idr"], render (wireModule (compositesOf declarations.types declarations.attributes)))
     , ("compiler" ::: ["src", "IdrisMLIR", "Encoding", "Idr.idr"], render (encodersModule declarations.types declarations.attributes)) ]
