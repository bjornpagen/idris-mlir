-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The specification's package, its modules held here once: the generator
||| prints the package file Idris builds and installs the library from
||| (`compiler/spec/spec.ipkg`), and fingerprints its own modules' sources,
||| from this list, so no list of modules is written twice and no text of
||| the package file is read.
module IdrisMLIR.Spec.Generator.Package

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Generator.Render

import Data.List
import Data.List1

%default total

||| A module of the package: its root, `IdrisMLIR.Spec`, or a module of one
||| of its areas, `IdrisMLIR.Spec.<area>.<module>`, each part an identifier
||| checked where it is written.
public export
data Module = Root | InArea Ident Ident

||| An area of the specification: its directory below `IdrisMLIR.Spec` and
||| its modules, in the package's order.
public export
record Area where
  constructor MkArea
  name : Ident
  modules : List1 Ident

||| The areas that state the dialect, in the package's order.
export
declaring : List Area
declaring =
  [ MkArea "Arrays" ("Declarations" ::: ["Generating", "Memory"])
  , MkArea "Closures" ("Declarations" ::: ["Memo"])
  , MkArea "Control" ("Declarations" ::: ["Flow", "Joins", "Matches", "Rules"])
  , MkArea "Core"
      ("Admitted" ::: [ "Constraints", "Cpp", "Declarations", "Dialect", "Enums", "Format", "Hooks"
                      , "Interfaces", "Ods", "Op", "Rewrite", "Rules", "Text", "Types", "Upstream"
                      , "Verdict", "Vocabulary" ])
  , MkArea "Counting" ("Declarations" ::: ["Types"])
  , MkArea "Effects" ("Atom" ::: ["Declaration", "Declarations", "LLVM", "Resource"])
  , MkArea "Families" ("Declarations" ::: ["Dialect", "Group", "Layout", "Ops", "Terms", "Types"])
  , MkArea "Functions"
      ("Copy" ::: ["Declarations", "Extents", "LivesIn", "Parameters", "Tail", "Termination"])
  , MkArea "Grades" ("Declarations" ::: ["Grade", "Hold"])
  , MkArea "Lifetimes" ("Declarations" ::: ["Kind"])
  , MkArea "Ops"
      ("Bigs" ::: [ "Checks", "Declarations", "IO", "Numeric", "Platform", "Rewrites", "Scalars"
                  , "Shapes", "Strings", "Values" ])
  , MkArea "Pipeline" ("Pass" ::: ["Pipeline", "Stage"])
  , MkArea "Runtime" ("Clocks" ::: ["Declarations", "Endings", "Handles", "Helpers", "Layout"])
  , MkArea "Tail" ("Declarations" ::: []) ]

||| The generator's own area, in the order the manifest fingerprints its
||| modules' sources.
export
generator : Area
generator =
  MkArea "Generator"
    ("Bytecode" ::: ["Cpp", "Idris", "Main", "Manifest", "Ods", "Outputs", "Package", "Render", "Wire"])

||| An area's modules, in its order.
export
inArea : Area -> List1 Module
inArea a = map (InArea a.name) a.modules

||| Every module of the package, in its order: the root, the areas that
||| state the dialect, the generator's.
export
packageModules : List1 Module
packageModules = Root ::: concatMap (forget . inArea) (declaring ++ [generator])

||| A module's name, as an import names it.
export
moduleName : Module -> String
moduleName Root = "IdrisMLIR.Spec"
moduleName (InArea a m) = "IdrisMLIR.Spec." ++ identText a ++ "." ++ identText m

||| A module's source under the checkout's root.
export
moduleSource : Module -> Path
moduleSource Root = "compiler" ::: ["spec", "IdrisMLIR", "Spec.idr"]
moduleSource (InArea a m) = "compiler" ::: ["spec", "IdrisMLIR", "Spec", identText a, identText m ++ ".idr"]

||| The package file's path, beside the specification's sources.
export
packagePath : Path
packagePath = "compiler" ::: ["spec", "spec.ipkg"]

||| The package file: the library of every module, which the frontend, the
||| tests' runner and specgen's own package (specgen.ipkg) depend on.
export
packageText : String
packageText =
  render (banner (map ("-- " ++))
          ++ [ "package idris-mlir-spec"
             , "version = 0.1.0"
             , "brief = " ++ quoted "The idr dialect's one source, and the generator that prints it"
             , ""
             , "sourcedir = " ++ quoted "." ]
          ++ listed (map moduleName packageModules))
  where
    listed : List1 String -> Lines
    listed (m ::: ms) = ("modules = " ++ m) :: map ("        , " ++) ms
