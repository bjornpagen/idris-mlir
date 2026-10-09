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

%default total

||| Every entry: category 1, then category 2.
export
entries : List Entry
entries = primitives ++ recognized

||| The hooks of a key, one per entry that has it.
export
hooks : Key -> List Hook
hooks k = map (.hook) (filter (\e => e.key == k) entries)

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
foreignHook : QName -> List String -> Maybe (Either (Entry, Mismatch) Hook)
foreignHook q specs = do
  -- Two entries may declare one spec at two names (Chez names one
  -- bytevector operation for a deprecated Int spelling and for Bits8, and
  -- base one C function for a file's size and for its poll): the entry
  -- declared at this name wins.
  e <- case find (\e => declares e specs && declaredAt e == Just q) entries of
         Just e => Just e
         Nothing => find (\e => declares e specs) entries
  pure (case site e of
          Just (declared, _) => if declared == q then Right e.hook else Left (e, DeclaredBy q)
          Nothing => Right e.hook)

||| Is a registry name in one of these modules (given by their paths,
||| outermost first)? Every entry's definition is in the module its
||| namespace names.
export
inModules : List (List String) -> QName -> Bool
inModules mods q = elem q.space mods

||| The test hook of shape validation: the entries with the one whose key is
||| shown as `name` expecting one more argument in front, a world at
||| quantity ω, which no entry's definition takes. `Nothing` when no entry
||| with a definition is shown so.
export
breaking : String -> List Entry -> Maybe (List Entry)
breaking name es = if any named es then Just (map (\e => if named e then broken e else e) es) else Nothing
  where
    named : Entry -> Bool
    named e = show e.key == name && isJust (site e)
    wrong : Shape -> Shape
    wrong = Pi Quantity.Many (Prim WorldP)
    break : (k : Key) -> Expect k -> Expect k
    break (Def _) (Typed s) = Typed (wrong s)
    break (Foreign _) (Declared q s) = Declared q (wrong s)
    break (Spelling _) Written = Written
    broken : Entry -> Entry
    broken e = MkEntry e.key (break e.key e.expect) e.hook e.rules
