-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
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
import Core.Name.Namespace
import Core.Options
import Core.TT
import Idris.Host
import Idris.Version
import Libraries.Data.Version
import Libraries.Utils.Path

import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.String

%default total

------------------------------------------------------------------------------
-- Names and modules
------------------------------------------------------------------------------

||| A full name as the registry writes it.
export
qname : Name -> QName
qname (NS ns n) = MkQName (reverse (unsafeUnfoldNamespace ns)) (show n)
qname n = MkQName [] (show n)

||| Whether two names are one definition's: their full names are equal.
export
sameName : {auto c : Ref Ctxt Defs} -> Name -> Name -> Core Bool
sameName n m = (==) <$> toFullNames n <*> toFullNames m

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
||| elaborates from source is in no TTC, and is the project's. An
||| installed module's TTC is `<package>-<version>/<ttc version>/<path>.ttc`.
||| That directory is the package, under the prefix or on the package
||| search path alike: a test installs into a fresh prefix and leaves the
||| libraries on the search path. The module's name says nothing about it.
homeOf : {auto c : Ref Ctxt Defs} -> ModuleIdent -> Core Home
homeOf ident = do
  defs <- get Ctxt
  case lookup ident (map (\(file, (m, _, _)) => (m, file)) defs.allImported) of
    Nothing => pure Project
    Just file => do
      let own = ModuleIdent.toPath ident <.> "ttc"
      bdir <- ttcBuildDirectory
      pure $ if dropBase bdir file == Just own then Project
             else fromMaybe Elsewhere (installed own (splitPath file))
  where
    ||| The name before a package directory's `-<version>`.
    packageName : String -> Maybe String
    packageName dir =
      case break (== '-') (reverse (unpack dir)) of
        (ver, '-' :: name) =>
          if not (null ver) && not (null name) && all (\c => isDigit c || c == '.') ver
             then Just (pack (reverse name)) else Nothing
        _ => Nothing
    ||| The package whose directory sits above this TTC's version directory.
    installed : String -> List String -> Maybe Home
    installed own parts = search parts
      where
        ver : String
        ver = show ttcVersion
        search : List String -> Maybe Home
        search (dir :: v :: rest) =
          if v == ver && splitPath own == rest then
            case packageName dir of
              Just name => Just (Installed name)
              Nothing => search (v :: rest)
          else search (v :: rest)
        search _ = Nothing

||| Where the code of a module comes from (the registry's library table),
||| by the package Idris loaded it from, never by its name alone.
export
originOf : {auto c : Ref Ctxt Defs} -> ModuleIdent -> Core Origin
originOf ident = pure (moduleOrigin !(homeOf ident) (modulePath ident))

||| The checked module Idris reloads as the file just elaborated has no name.
unnamed : (String, (ModuleIdent, Bool, Namespace)) -> Bool
unnamed (_, (m, _, _)) = null (unsafeUnfoldModuleIdent m)

||| The file just elaborated, recovered from the checked module Idris
||| reloads with no name. Its path is the file's, which need not be the
||| module's: a file with no module header is `Main` whatever it is called.
elaboratedFile : {auto c : Ref Ctxt Defs} -> Core (Maybe String)
elaboratedFile = do
  defs <- get Ctxt
  let ttcs = map fst (filter unnamed defs.allImported)
  case ttcs of
    [ttc] => do
      bdir <- ttcBuildDirectory
      let Just rel = dropBase bdir ttc
        | Nothing => pure Nothing
      d <- getDirs
      let stem = dropExtensions rel
      let base = maybe stem (\srcdir => srcdir </> stem) (source_dir d)
      firstAvailable (map (base ++) listOfExtensionsStr)
    _ => pure Nothing

||| The source of a module of the project. It is the file named for the
||| module, except the main module, which Idris allows to be any file: that
||| file is the one just elaborated.
export
moduleSource : {auto c : Ref Ctxt Defs} -> FC -> ModuleIdent -> Core (Maybe String)
moduleSource fc ident = do
  named <- catch (Just <$> nsToSource fc ident) (\_ => pure Nothing)
  if ident == nsAsModuleIdent mainNS
    then do
      elaborated <- elaboratedFile
      pure (elaborated <|> named)
    else pure named

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

||| The hooks of a definition, by its full name.
export
hooksOf : Name -> Hooks
hooksOf n = hooks (Def (qname n))

||| What the registry makes of a `%foreign` definition, by its full name and
||| the specs Idris recorded for it: nothing, its hook, or the message of
||| a shape mismatch when another definition declares an entry's spec.
export
foreignHookOf : Name -> List String -> Maybe (Either String Hooks)
foreignHookOf n specs = map (mapFst (\(e, m) => mismatch e m)) (foreignHook (qname n) specs)

------------------------------------------------------------------------------
-- Shapes
------------------------------------------------------------------------------

||| How a runtime value bound with multiplicity 1 or ω is used. A binder of
||| multiplicity 0 binds no runtime value, so it has no quantity: whoever
||| meets one leaves the position out.
export
quantityOf : RigCount -> Quantity
quantityOf rig = if isLinear rig then One else Many

||| The product of two quantities, as Idris uses a field through the
||| binder that holds its value: one is the unit, and many absorbs.
export
quantityTimes : Quantity -> Quantity -> Quantity
quantityTimes One q = q
quantityTimes Many _ = Many

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
primTy Primitive.WorldType = Just WorldP

||| The shape of a normalised type whose names are full. What no shape
||| describes (a variable, an erased or delayed term) is a hole.
export
shapeOf : Term vars -> Shape
shapeOf (Bind _ _ (Pi _ rig _ a) sc) = Pi (multiplicity rig) (shapeOf a) (shapeOf sc)
  where
    multiplicity : RigCount -> Multiplicity
    multiplicity rig = if isErased rig then M0 else if isLinear rig then M1 else Mw
shapeOf (PrimVal _ (PrT t)) = maybe Hole Prim (primTy t)
shapeOf (TType _ _) = TypeOfTypes
shapeOf tm = spine tm []
  where
    ||| An application's head and the shapes of its arguments, walked down
    ||| the spine so that every argument is a subterm.
    spine : Term vars -> List Shape -> Shape
    spine (App _ f a) args = spine f (shapeOf a :: args)
    spine (Ref _ _ n) args = Head (Def (qname n)) args
    spine _ _ = Hole

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

||| Every entry, resolved against the loaded context once per
||| compilation, before anything uses the registry. An entry whose module the
||| program does not load is not checked; one whose definition is present
||| must be what the entry expects. There is no fallback: a mismatch stops
||| the compilation. A test of the validation gives it a program whose own
||| module defines a keyed name at another shape.
export
validate : {auto c : Ref Ctxt Defs} -> Core Validation
validate = check entries
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
        if not declared then pure (Wrong (location def) (show q) (mismatch e Undeclared)) else
          case expected of
            -- A bodiless declaration is its own shape: there is nothing of
            -- its type to compare, only that no body gives it a second
            -- meaning.
            IsBodiless => case definition def of
              ExternDef _ => check es
              _ => pure (Wrong (location def) (show q) (mismatch e Bodied))
            HasShape shape => do
              ty <- toFullNames !(host.normalise defs Env.Nil (type def))
              let found = shapeOf ty
              if conforms shape found then check es
                 else pure (Wrong (location def) (show q) (mismatch e (Found found)))
