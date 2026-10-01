||| The frontend's side of the registry: Idris's names, modules and types as
||| the registry's names, origins and shapes, and the validation of every
||| entry against the loaded context. This module converts and asks; the
||| registry compares.
module IdrisMLIR.Frontend.Resolve

import Core.Binary
import Core.Context
import Core.Core
import Core.Directory
import Core.Env
import Core.Normalise
import Core.Options
import Core.TT
import Idris.Version
import Libraries.Data.Version
import Libraries.Utils.Path

import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.String

%default covering

------------------------------------------------------------------------------
-- Names and modules
------------------------------------------------------------------------------

||| A full name as the registry writes it.
export
qname : Name -> QName
qname (NS ns n) = MkQName (reverse (unsafeUnfoldNamespace ns)) (show n)
qname n = MkQName [] (show n)

||| A registry name as Idris's, to look it up.
export
toName : QName -> Name
toName q = case q.space of
  [] => UN (Basic q.name)
  ns => NS (unsafeFoldNamespace (reverse ns)) (UN (Basic q.name))

||| A module's path, outermost first, as the registry takes it.
export
modulePath : ModuleIdent -> List String
modulePath ident = reverse (unsafeUnfoldModuleIdent ident)

||| A module given by its path, outermost first.
export
moduleIdent : List String -> ModuleIdent
moduleIdent path = unsafeFoldModuleIdent (reverse path)

||| Where Idris found the TTC it loaded a module from. The module it
||| elaborates from source is in no TTC, and is the project's.
homeOf : {auto c : Ref Ctxt Defs} -> ModuleIdent -> Core Home
homeOf ident = do
  defs <- get Ctxt
  case lookup ident (map (\(file, (m, _, _)) => (m, file)) defs.allImported) of
    Nothing => pure Project
    Just file => do
      let own = ModuleIdent.toPath ident <.> "ttc"
      bdir <- ttcBuildDirectory
      global <- pkgGlobalDirectory
      pure $ if dropBase bdir file == Just own then Project else
        case map splitPath (dropBase global file) of
          Just (dir :: _) =>
            -- An installed package's directory is its name and its
            -- version: `base-0.8.0`, `mlir-linear-0.1.0`.
            case packageName dir of
              Just name => if dropBase (global </> dir </> show ttcVersion) file == Just own
                              then Installed name else Elsewhere
              Nothing => Elsewhere
          _ => Elsewhere
  where
    ||| The name before a package directory's `-<version>`.
    packageName : String -> Maybe String
    packageName dir =
      case break (== '-') (reverse (unpack dir)) of
        (ver, '-' :: name) =>
          if not (null ver) && not (null name) && all (\c => isDigit c || c == '.') ver
             then Just (pack (reverse name)) else Nothing
        _ => Nothing

||| Where the code of a module comes from (the registry's library table),
||| by the package Idris loaded it from, never by its name alone.
export
originOf : {auto c : Ref Ctxt Defs} -> ModuleIdent -> Core Origin
originOf ident = pure (moduleOrigin !(homeOf ident) (modulePath ident))

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

||| The hooks of a definition, by its full name.
export
hooksOf : Name -> List Hook
hooksOf n = hooks (Def (qname n))

||| What the registry makes of a `%foreign` definition, by its full name and
||| the specs Idris recorded for it: nothing, its hook, or the message of
||| a shape mismatch when another definition declares an entry's spec.
export
foreignHookOf : Name -> List String -> Maybe (Either String Hook)
foreignHookOf n specs = map (mapFst (\(e, m) => mismatch e m)) (foreignHook (qname n) specs)

------------------------------------------------------------------------------
-- Shapes
------------------------------------------------------------------------------

||| How a value bound with multiplicity 1 or ω is used.
export
useOf : RigCount -> Use
useOf rig = if isLinear rig then Once else Many

||| The Core binder of an Idris binder of this multiplicity; the type of what
||| it binds is computed only when it binds a runtime value.
export
binderOf : RigCount -> Lazy (Core Ty) -> Core Binder
binderOf rig t = if isErased rig then pure Gone else Held (useOf rig) <$> t

primTy : PrimType -> Maybe PrimTy
primTy IntType = Just (IntP IdrisInt)
primTy Int8Type = Just (IntP SInt8)
primTy Int16Type = Just (IntP SInt16)
primTy Int32Type = Just (IntP SInt32)
primTy Int64Type = Just (IntP SInt64)
primTy Bits8Type = Just (IntP UInt8)
primTy Bits16Type = Just (IntP UInt16)
primTy Bits32Type = Just (IntP UInt32)
primTy Bits64Type = Just (IntP UInt64)
primTy IntegerType = Just IntegerP
primTy StringType = Just StringP
primTy CharType = Just CharP
primTy DoubleType = Just DoubleP
primTy WorldType = Just WorldP

spine : Term vars -> List (Term vars) -> (Term vars, List (Term vars))
spine (App _ f a) as = spine f (a :: as)
spine f as = (f, as)

||| The shape of a normalised type whose names are full. What no shape
||| describes (a variable, an erased or delayed term) is a hole.
export
shapeOf : Term vars -> Shape
shapeOf (Bind _ _ (Pi _ rig _ a) sc) = Pi (multiplicity rig) (shapeOf a) (shapeOf sc)
  where
    multiplicity : RigCount -> Quantity
    multiplicity rig = if isErased rig then Q0 else if isLinear rig then Q1 else QW
shapeOf (PrimVal _ (PrT t)) = maybe Hole Prim (primTy t)
shapeOf (TType _ _) = TypeOfTypes
shapeOf tm = case spine tm [] of
  (Ref _ _ n, args) => Head (Def (qname n)) (map shapeOf args)
  _ => Hole

------------------------------------------------------------------------------
-- Validation
------------------------------------------------------------------------------

||| What validation found.
public export
data Validation
  = Valid
  | ||| An entry whose definition is present and wrong: where, the name the
    ||| entry resolves, and the message.
    Wrong FC String String
  | ||| The test directive names no entry with a definition.
    NoSuchEntry String

||| The test hook: `--directive break-shape=<key>` breaks that entry's shape.
breakDirective : String -> Maybe String
breakDirective d =
  let flag = "break-shape=" in
  if isPrefixOf flag d then Just (substr (length flag) (length d) d) else Nothing

||| Every entry, resolved against the loaded context once per
||| compilation, before anything uses the registry. An entry whose module the
||| program does not load is not checked; one whose definition is present
||| must be what the entry expects. There is no fallback: a mismatch stops
||| the compilation.
export
validate : {auto c : Ref Ctxt Defs} -> Core Validation
validate = do
  ds <- getDirectives (Other "mlir")
  case mapMaybe breakDirective ds of
    [] => check entries
    (name :: _) => maybe (pure (NoSuchEntry name)) check (breaking name entries)
  where
    check : List Entry -> Core Validation
    check [] = pure Valid
    check (e :: es) = case site e of
      Nothing => check es
      Just (q, expected) => do
        defs <- get Ctxt
        let loaded = map (\(_, (m, _, _)) => modulePath m) defs.allImported
        Just def <- lookupCtxtExact (toName q) (gamma defs)
          | Nothing => if inModules loaded q then pure (Wrong EmptyFC (show q) (mismatch e Missing))
                       else check es
        let declared = case (e.key, definition def) of
                         (Foreign _, ForeignDef _ specs) => declares e specs
                         (Foreign _, _) => False
                         _ => True
        if not declared then pure (Wrong (location def) (show q) (mismatch e Undeclared)) else do
          ty <- toFullNames !(normalise defs Env.Nil (type def))
          let found = shapeOf ty
          if conforms expected found then check es
             else pure (Wrong (location def) (show q) (mismatch e (Found found)))
