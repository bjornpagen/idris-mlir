-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What one area of the dialect declares: its ops, types, attributes,
||| enums and tables, interfaces and traits, custom directives and hand
||| predicates, the resources of the effect tree, the runtime's helper
||| functions, the admitted upstream ops it reads, its rules, and the
||| headers of constants its hand C++ includes. Each area
||| of the specification exports one value of this from its directory's
||| `Declarations` module (`IdrisMLIR.Spec.<Area>.Declarations`), and the
||| dialect is their union in the specification's root, in a fixed order:
||| no area is found by listing a directory.
module IdrisMLIR.Spec.Core.Declarations

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Hooks
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Cpp
import IdrisMLIR.Spec.Core.Interfaces
import IdrisMLIR.Spec.Core.Types
import IdrisMLIR.Spec.Core.Ods
import IdrisMLIR.Spec.Core.Admitted
import IdrisMLIR.Spec.Core.Op
import IdrisMLIR.Spec.Core.Rewrite
import IdrisMLIR.Spec.Pipeline.Pass

%default total

public export
record Declarations where
  constructor MkDeclarations
  ops : List AnyOp
  types : List AnyTypeDef
  attributes : List AnyAttrDef
  enums : List EnumDef
  tables : List Table
  interfaces : List InterfaceDef
  traits : List TraitDef
  directives : List Directive
  predicates : List Predicate
  resources : List ResourceDef
  helpers : List RuntimeHelper
  admitted : List Admitted
  rewrites : List AnyRewrite
  skeleton : List SkeletonRule
  headers : List Header

||| An area that declares nothing yet; an area's value is this with its
||| fields given.
public export
nothing : Declarations
nothing = MkDeclarations [] [] [] [] [] [] [] [] [] [] [] [] [] [] []

||| Two areas' declarations together, the first's first.
public export
union : Declarations -> Declarations -> Declarations
union x y = MkDeclarations
  (x.ops ++ y.ops) (x.types ++ y.types) (x.attributes ++ y.attributes)
  (x.enums ++ y.enums) (x.tables ++ y.tables) (x.interfaces ++ y.interfaces)
  (x.traits ++ y.traits) (x.directives ++ y.directives) (x.predicates ++ y.predicates)
  (x.resources ++ y.resources) (x.helpers ++ y.helpers) (x.admitted ++ y.admitted)
  (x.rewrites ++ y.rewrites) (x.skeleton ++ y.skeleton) (x.headers ++ y.headers)

||| The dialect's own settings, which the specification's root states: what
||| it is, the dialects it loads when it loads, and the members its class
||| declares and hand units define (where its types are registered, where
||| the value facts of builtin types attach). It reads and prints its types
||| and attributes by the generated parsers, materializes constants, and
||| refuses every attribute of its namespace on an op or an argument: a fact
||| a pass reads is an op's property or a type, where no pass drops it.
public export
record DialectDef where
  constructor MkDialectDef
  summary : Line
  description : Prose
  loads : List Loads
  members : List Member
