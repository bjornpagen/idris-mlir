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
import Core.FC
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
-- Refusals
------------------------------------------------------------------------------

||| A program the compiler refuses, from the moment the refusal is made: the
||| rule that refuses it, Idris's location of what it refuses, which a
||| refusal always has, and the message, which names what is refused.
public export
record Refusal where
  constructor MkRefusal
  rule : Rule
  site : NonEmptyFC
  message : String

export
Eq Refusal where
  r == r' = r.rule == r'.rule && r.site == r'.site && r.message == r'.message

||| Why a program is not compiled: a refusal, or an error Idris raised,
||| held as Idris gave it until the driver renders its message (rendering
||| needs Idris's printing options, which only the driver has).
public export
data Rejection = Refused Refusal | ByIdris Error

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

||| The hooks of a definition, by its full name.
export
hooksOf : Name -> Hooks
hooksOf n = hooks (Def (qname n))

||| What the registry makes of a `%foreign` definition, by its full name and
||| the specs Idris recorded for it, at the site that reaches it: its hooks,
||| or the refusal of it, a shape mismatch when another definition declares
||| an entry's spec, or an escape hatch when no entry names a spec (`owner`
||| reaches it, `via` the path that does).
export
foreignHookOf : NonEmptyFC -> (owner : String) -> (via : String) -> Name -> List String -> Either Refusal Hooks
foreignHookOf site owner via n specs = case foreignHook (qname n) specs of
  Just (Right hs) => Right hs
  Just (Left (e, m)) => Left (MkRefusal HookShape site (show n ++ ": " ++ mismatch e m))
  Nothing => Left (MkRefusal EscapeHatch site (owner ++ ": %foreign " ++ show n ++ via))

------------------------------------------------------------------------------
-- Shapes
------------------------------------------------------------------------------

||| How a binder's value is used at run time: not at all (quantity 0, a
||| binder of no runtime value, whose position whoever meets it leaves
||| out), or as a quantity says.
public export
data Use = Erased | Used Quantity

||| The use a binder's multiplicity gives its value.
export
use : RigCount -> Use
use = elimSemi Erased (Used One) (const (Used Many))

||| A use as the registry writes a binder's multiplicity.
export
multiplicity : Use -> Multiplicity
multiplicity Erased = M0
multiplicity (Used One) = M1
multiplicity (Used Many) = Mw

||| The product of two quantities, as Idris uses a field through the
||| binder that holds its value: one is the unit, and many absorbs.
export
quantityTimes : Quantity -> Quantity -> Quantity
quantityTimes One q = q
quantityTimes Many _ = Many

||| A primitive type as the registry has it.
export
primTy : PrimType -> PrimTy
primTy IntType = IntP IdrisInt
primTy Int8Type = IntP SInt8
primTy Int16Type = IntP SInt16
primTy Int32Type = IntP SInt32
primTy Int64Type = IntP SInt64
primTy Bits8Type = IntP UInt8
primTy Bits16Type = IntP UInt16
primTy Bits32Type = IntP UInt32
primTy Bits64Type = IntP UInt64
primTy IntegerType = IntegerP
primTy StringType = StringP
primTy CharType = CharP
primTy DoubleType = DoubleP
primTy Primitive.WorldType = WorldP

||| The shape of a normalised type whose names are full. What no shape
||| describes (a variable, an erased or delayed term) is a hole.
export
shapeOf : Term vars -> Shape
shapeOf (Bind _ _ (Pi _ rig _ a) sc) = Pi (multiplicity (use rig)) (shapeOf a) (shapeOf sc)
shapeOf (PrimVal _ (PrT t)) = Prim (primTy t)
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
-- The registry against the context
------------------------------------------------------------------------------

||| Every entry, resolved against the loaded context once per
||| compilation, before anything uses the registry. An entry whose module the
||| program does not load is not checked; one whose definition is present
||| must be what the entry expects. There is no fallback: a mismatch stops
||| the compilation. A test of the validation gives it a program whose own
||| module defines a keyed name at another shape. The first entry that does
||| not validate is refused where its definition is, or, when the
||| definition is missing, at `fallback`.
export
validate : {auto c : Ref Ctxt Defs} -> (fallback : NonEmptyFC) -> Core (Maybe Refusal)
validate fallback = check entries
  where
    wrong : FC -> QName -> String -> Refusal
    wrong loc q msg = MkRefusal HookShape (fromMaybe fallback (isNonEmptyFC loc)) (show q ++ ": " ++ msg)

    check : List Entry -> Core (Maybe Refusal)
    check [] = pure Nothing
    check (e :: es) = case site e of
      Nothing => check es
      Just (q, expected) => do
        defs <- get Ctxt
        let loaded = map (\(_, (m, _, _)) => modulePath m) defs.allImported
        Just def <- lookupCtxtExact (toName q) (gamma defs)
          | Nothing => if inModules loaded q then pure (Just (wrong EmptyFC q (mismatch e Missing)))
                       else check es
        let declared = case (e.key, definition def) of
                         (Foreign _, ForeignDef _ specs) => declares e specs
                         (Foreign _, _) => False
                         _ => True
        if not declared then pure (Just (wrong (location def) q (mismatch e Undeclared))) else
          case expected of
            -- A bodiless declaration is its own shape: there is nothing of
            -- its type to compare, only that no body gives it a second
            -- meaning.
            IsBodiless => case definition def of
              ExternDef _ => check es
              _ => pure (Just (wrong (location def) q (mismatch e Bodied)))
            HasShape shape => do
              ty <- toFullNames !(host.normalise defs Env.Nil (type def))
              let found = shapeOf ty
              if conforms shape found then check es
                 else pure (Just (wrong (location def) q (mismatch e (Found found))))
