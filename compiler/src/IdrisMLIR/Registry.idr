-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The registry of privileged knowledge.
|||
||| No language features in the compiler: features are Idris libraries, and
||| the compiler has privileged knowledge of a fixed, registered set of them,
||| which it may make faster or stricter, but never different. Removing any
||| hook may change speed or add a rejection; it never changes a program's
||| result, which the tests' expected files pin.
|||
||| This module and the files under `Registry/` are the only code that names
||| an Idris definition: one file per category (`Primitives`, Idris's backend
||| contract; `Recognized`, the privileged knowledge) and the library table
||| (`Libraries`). Everything else asks what the registry says of a
||| definition at the entry the definition's name resolves to in the
||| context (`Frontend.Resolve`), or of a spelling by its text, and matches
||| on the `Hook` it gets back.
module IdrisMLIR.Registry

import public IdrisMLIR.Registry.Entry
import public IdrisMLIR.Registry.Name
import public IdrisMLIR.Registry.Primitives
import IdrisMLIR.Registry.Faster
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Registry.Recognized
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.SortedMap

%default total

||| Every entry: category 1, then category 2, then the faster lowerings,
||| which live in a module of their own so that a build can leave them all
||| out and compile every program from the bodies alone.
export
entries : List AnyEntry
entries = primitives ++ recognized ++ map Kinded faster

||| The hooks of each spelling the registry forbids in source, by its text,
||| which is what the source gives: indexed once, since every identifier a
||| user module spells asks. A definition's hooks are found by the entry
||| its name resolves to in the context (`Frontend.Resolve.readRegistry`),
||| never by a name printed to text.
spellings : SortedMap String (Hooks QName)
spellings = foldl add empty entries
  where
    add : SortedMap String (Hooks QName) -> AnyEntry -> SortedMap String (Hooks QName)
    add m (Kinded e) = case e.key of
      Spelling s => insert s (withHook (fromMaybe noHooks (lookup s m)) e.hook) m
      _ => m

||| The hooks of a spelling in source: those of every entry that has it.
export
spellingHooks : String -> Hooks QName
spellingHooks s = fromMaybe noHooks (lookup s spellings)

||| Does a definition's spec list declare an entry's spec?
export
declares : AnyEntry -> List String -> Bool
declares e specs = any (\s => Foreign s == e.entry.key) (mapMaybe parseSpec specs)

||| Is a definition of this origin admitted, by the hooks of its name, or
||| for a case or with block its parent's: its library admits every
||| definition of it, or its entry admits it. `Builtin`'s escape hatches
||| are admitted like the rest of it: Idris flags them (`isEscapeHatch`),
||| and the escape-hatch check rejects them on that flag first.
export
admits : Origin -> Hooks lib -> Bool
admits o hs = covers Admitted o || hs.admission

||| Is a registry name in one of these modules (given by their paths,
||| outermost first)? Every entry's definition is in the module its
||| namespace names.
export
inModules : List (List String) -> QName -> Bool
inModules mods q = elem q.space mods

||| Is a shape found the type of the array language's shapes, a snoc list of
||| naturals? The frontend asks; the registry compares.
export
isShapeType : Shape -> Bool
isShapeType = conforms shapeType
