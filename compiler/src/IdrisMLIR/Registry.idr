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
||| (`Libraries`). Everything else asks with a `Key` and matches on the
||| `Hook` it gets back.
module IdrisMLIR.Registry

import public IdrisMLIR.Registry.Entry
import public IdrisMLIR.Registry.Name
import public IdrisMLIR.Registry.Primitives
import IdrisMLIR.Registry.Recognized
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.SortedMap

%default total

||| Every entry: category 1, then category 2.
export
entries : List Entry
entries = primitives ++ recognized

||| The hooks of each definition the registry names, by its qualified name,
||| in the entries' order: the definitions' keys indexed once, since every
||| definition the compiler reaches and every call it translates asks.
defHooks : SortedMap (List String, String) Hooks
defHooks = foldl add empty entries
  where
    add : SortedMap (List String, String) Hooks -> Entry -> SortedMap (List String, String) Hooks
    add m e = case e.key of
      Def q => insert (q.space, q.name) (withHook (fromMaybe noHooks (lookup (q.space, q.name) m)) e.hook) m
      _ => m

||| The hooks of a key: those of every entry that has it.
export
hooks : Key -> Hooks
hooks (Def q) = fromMaybe noHooks (lookup (q.space, q.name) defHooks)
hooks k = foldl withHook noHooks (map (.hook) (filter (\e => e.key == k) entries))

||| Does a definition's spec list declare an entry's spec?
export
declares : Entry -> List String -> Bool
declares e specs = any (\s => Foreign s == e.key) (mapMaybe parseSpec specs)

||| The name an entry's definition has, when it names one.
declaredAt : Entry -> Maybe QName
declaredAt e = fst <$> site e

||| What the registry makes of a `%foreign` definition, by the specs Idris
||| recorded for it: `Nothing` if it declares no entry's spec; the entry's
||| hook if it is the definition the entry names; otherwise the entry and
||| its mismatch.
export
foreignHook : QName -> List String -> Maybe (Either (Entry, Mismatch) Hooks)
foreignHook q specs = do
  -- Two entries may declare one spec at two names (Chez names one
  -- bytevector operation for a deprecated Int spelling and for Bits8, and
  -- base one C function for a file's size and for its poll): the entry
  -- declared at this name wins.
  e <- case find (\e => declares e specs && declaredAt e == Just q) entries of
         Just e => Just e
         Nothing => find (\e => declares e specs) entries
  pure (case site e of
          Just (declared, _) => if declared == q then Right (withHook noHooks e.hook) else Left (e, DeclaredBy q)
          Nothing => Right (withHook noHooks e.hook))

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
