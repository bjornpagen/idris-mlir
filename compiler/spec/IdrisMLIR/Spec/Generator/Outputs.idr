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
||| the specification directly.
export
admittedBaseTd : String
admittedBaseTd =
  tdFile "IDR_GENERATED_ADMITTED_BASE" ["mlir/IR/OpBase.td"]
    [ "// An upstream op the dialect admits: upstream's own record, the stages"
    , "// it may stand at, and whether the frontend writes it (its Idris builder"
    , "// is printed)."
    , "class IdrAdmitted<Op upstream, string first, string last, int written> {"
    , "  Op op = upstream;"
    , "  string firstStage = first;"
    , "  string lastStage = last;"
    , "  int frontendWrites = written;"
    , "}"
    , "" ]

export
admittedRow : Admitted -> String
admittedRow a =
  let (first, last) = bounds a.legal
      written = case a.writer of
                  FrontendWrites => "1"
                  PassesOnly => "0"
  in "def IdrAdmitted_" ++ identText a.upstreamRecord ++ " : IdrAdmitted<" ++ identText a.upstreamRecord ++ ", "
       ++ quoted first ++ ", " ++ quoted last ++ ", " ++ written ++ ">;"
  where
    name : Stage -> String
    name s = identText (stageClosed.describe s).name
    bounds : Legal -> (String, String)
    bounds Always = ("Higher", "Lowered")
    bounds (Between f l _) = (name f, name l)

||| One admitted record file per upstream dialect.
export
admittedTd : Dialect -> (Path, String)
admittedTd d =
  ( generated ("IdrAdmitted" ++ identText (dialectName d) ++ ".td")
  , tdFile ("IDR_GENERATED_ADMITTED_" ++ pack (map up (unpack (identText (dialectName d)))))
      [odsInclude d, "idr/IR/Generated/IdrAdmittedBase.td"]
      (map admittedRow (filter (\a => sameDialect a.dialect d) declarations.admitted)) )
  where
    up : Char -> Char
    up c = if lower c then chr (ord c - 32) else c
    sameDialect : Dialect -> Dialect -> Bool
    sameDialect x y = identText (dialectName x) == identText (dialectName y)

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
  ++ map admittedTd upstreamDialects
  ++ [ (generated "EnumTraits.h.inc", render (odsEnumTraits declarations.enums))
     , (generated "OpIndex.h.inc", render (opIndexHeader opKeys))
     , (generated "Guards.h.inc", render (guardsHeader ourOps))
     , (generated "InlineMeanings.h.inc", render (inlineMeaningsHeader ourOps))
     , (generated "RuntimeAbi.h.inc", render (runtimeAbi ourOps declarations.helpers))
     , ("runtime" ::: ["Generated", "idris_rt_ops.h"], render (runtimeOps ourOps declarations.helpers))
     , (generated "Resources.h.inc", render (resourcesHeader declarations.resources))
     , (generated "Effects.h.inc", render (effectsHeader ourOps))
     , (generated "Effects.cpp.inc", render (effectsDefinitions ourOps))
     , (generated "SkeletonRules.h.inc", render (skeletonRulesHeader declarations.skeleton))
     , (generated "Rewrites.h.inc", render (rewritesHeader declarations.rewrites ourOps declarations.admitted declarations.skeleton))
     , (generated "Laws.h.inc", render (lawsHeader ourOps declarations.admitted))
     , (generated "Hooks.h.inc", render (hooksHeader declarations.directives declarations.predicates declarations.interfaces declarations.types declarations.attributes ourOps))
     , (generated "Pipeline.h.inc", render (pipelineHeader (fst (stepsOf Higher [] pipeline))))
     , (generated "Actions.h.inc", render (actionsHeader everyAction)) ]
  ++ map (\t => (generated (identText t ++ ".h.inc"), render (specializationHeader t ourOps))) (templatesOf ourOps)
  ++ map areaHeader declarations.headers
  ++ [ ("compiler" ::: ["src", "IdrisMLIR", "Dialect", "Idr.idr"], render (buildersModule ourOps))
     , ("compiler" ::: ["src", "IdrisMLIR", "Encoding", "Idr.idr"], render (encodersModule declarations.types declarations.attributes)) ]
