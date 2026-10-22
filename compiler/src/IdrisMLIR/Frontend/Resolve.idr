-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The frontend's side of the registry: Idris's names, modules and types as
||| the registry's names, origins and shapes, and the validation of every
||| entry against the loaded context. This module converts and asks; the
||| registry compares.
module IdrisMLIR.Frontend.Resolve

import Core.Context
import Core.Core
import Core.Directory
import Core.Env
import Core.FC
import Core.Name.Namespace
import Core.Options
import Core.TT
import Idris.Host
import Libraries.Utils.Path

import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Core.Rules

import Data.List.Elem
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Types

import Data.DPair
import Data.List
import Data.Maybe
import Data.String

%default total

------------------------------------------------------------------------------
-- Names and modules
------------------------------------------------------------------------------

||| A full name as the registry writes it: its identifiers' text, which the
||| registry compares.
export
qname : Name -> QName
qname (NS ns n) = MkQName (map (.text) (reverse (unsafeUnfoldNamespace ns))) (show n)
qname n = MkQName [] (show n)

||| Whether two names are one definition's: their full names are equal.
export
sameName : {auto c : Ref Ctxt Defs} -> Name -> Name -> Core Bool
sameName n m = (==) <$> toFullNames n <*> toFullNames m

||| A registry name as Idris's, to look it up: its text interned in the
||| session's table, where it enters the compiler, so the name compares
||| with the context's by identity.
export
toName : {auto c : Ref Ctxt Defs} -> QName -> Core Name
toName q = do
  n <- UN <$> internUserName q.name
  case q.space of
    [] => pure n
    ns => (\parts => NS (nsOf parts) n) <$> traverse intern ns

||| A module's path, outermost first, as the registry takes it.
export
modulePath : ModuleIdent -> List String
modulePath ident = map (.text) (reverse (unsafeUnfoldModuleIdent ident))

||| Where Idris found a checked module it loaded, as the search recorded it
||| when it found the TTC: in the project's build directory, in a package
||| the build added, or in a directory named for imports. The module's name
||| says nothing about it.
homeOf : Found -> Home
homeOf InBuild = Project
homeOf (InPackage p) = Installed p.name
homeOf (InExtraDir _) = Elsewhere

||| The checked module Idris reloads as the file just elaborated has no name.
unnamed : Loaded -> Bool
unnamed l = null (unsafeUnfoldModuleIdent l.ident)

||| The checked module of the file just elaborated, which Idris reloads
||| with no name once it has built it: nothing before then.
export
elaboratedChecked : {auto c : Ref Ctxt Defs} -> Core (Maybe String)
elaboratedChecked = do
  defs <- get Ctxt
  pure (case map (.file) (filter unnamed defs.allImported) of
          [ttc] => Just ttc
          _ => Nothing)

||| The file just elaborated, recovered from its checked module. Its path
||| is the file's, which need not be the module's: a file with no module
||| header is `Main` whatever it is called.
elaboratedFile : {auto c : Ref Ctxt Defs} -> Core (Maybe String)
elaboratedFile = do
  Just ttc <- elaboratedChecked
    | Nothing => pure Nothing
  bdir <- ttcBuildDirectory
  let Just rel = dropBase bdir ttc
    | Nothing => pure Nothing
  d <- getDirs
  let stem = dropExtensions rel
  let base = maybe stem (\srcdir => srcdir </> stem) (source_dir d)
  firstAvailable (map (base ++) listOfExtensionsStr)

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

||| Every checked module the session loaded, by name, each with where Idris
||| found it and its checked file (`allImported`): with the main file, the
||| modules a term of the program can be located in, since Idris locates a
||| term in the module it elaborated it in. The file just elaborated is
||| reloaded under no name (`elaboratedChecked`); it is the project's, and
||| its terms are located in the module its path names, which is its
||| namespace but for a file with no module header.
export
loadedModules : {auto c : Ref Ctxt Defs} -> Core (List (ModuleIdent, Home, String))
loadedModules = do
  defs <- get Ctxt
  pure (map (\l => (l.ident, homeOf l.foundIn, l.file)) (filter (not . unnamed) defs.allImported))

------------------------------------------------------------------------------
-- Refusals
------------------------------------------------------------------------------

||| A program the compiler refuses, from the moment the refusal is made: the
||| rule that refuses it, Idris's location of what it refuses, which a
||| refusal always has, and the message, which names what is refused.
public export
record Refusal where
  constructor MkRefusal
  rule : SomeRule
  site : NonEmptyFC
  message : String

||| A rule's place among every rule, the one order the specification
||| gives them: two refusals are of one rule when their places are one.
rulePlace : SomeRule -> Nat
rulePlace r = place (ruleIn r)
  where
    place : Elem x xs -> Nat
    place Here = 0
    place (There e) = S (place e)

export
Eq Refusal where
  r == r' = rulePlace r.rule == rulePlace r'.rule && r.site == r'.site && r.message == r'.message

||| Why a program is not compiled: a refusal, or an error Idris raised,
||| held as Idris gave it until the driver renders its message (rendering
||| needs Idris's printing options, which only the driver has).
public export
data Rejection = Refused Refusal | ByIdris Error

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

||| The hooks of a definition, by its full name: looked up once, where the
||| definition is read (`Translate.Boundary`), and read from what was read
||| after (`Registered`).
export
hooksOf : Name -> Hooks QName
hooksOf n = hooks (Def (qname n))

||| Why the registry gives a `%foreign` definition no hooks: no entry
||| declares one of its specs, or the entry that declares one names another
||| definition.
public export
data ForeignMiss = NoEntry | DeclaredElsewhere AnyEntry Mismatch

||| What the registry makes of a `%foreign` definition, by its full name and
||| the specs Idris recorded for it: its hooks, or why it gives none.
export
foreignHooks : Name -> List String -> Either ForeignMiss (Hooks QName)
foreignHooks n specs = case foreignHook (qname n) specs of
  Just (Right hs) => Right hs
  Just (Left (e, m)) => Left (DeclaredElsewhere e m)
  Nothing => Left NoEntry

||| The refusal of a `%foreign` definition the registry gives no hooks, at
||| the site that reaches it: a shape mismatch when another definition
||| declares an entry's spec, or an escape hatch when no entry names a spec
||| (`owner` reaches it, `via` the path that does).
export
foreignRefusal : NonEmptyFC -> (owner : String) -> (via : String) -> Name -> ForeignMiss -> Refusal
foreignRefusal site owner via n (DeclaredElsewhere e m) = MkRefusal (Refusal HookShape) site (show n ++ ": " ++ mismatch e m)
foreignRefusal site owner via n NoEntry = MkRefusal (Refusal EscapeHatch) site (owner ++ ": %foreign " ++ show n ++ via)

%prefix_record_projections off

||| A library function a hook of the registry names (a natural's test or
||| its operation on integers, the function an alias stands for), read once
||| with the definition whose hook names it (`Translate.Boundary`): as the
||| registry names it, for a message, and as the context does, interned
||| where it enters the compiler (`toName`).
public export
record LibraryFunction where
  constructor MkLibraryFunction
  named : QName
  name : Name

%prefix_record_projections on

||| What the registry makes of a definition, read once with it
||| (`Translate.Boundary`), each library function a hook names read. Every
||| definition has the hooks of its name, which say what reaching it and
||| naming it are (forbidden, deprecated, a library's crash) and, for any
||| definition but a `%foreign` one, what its calls are. A `%foreign`
||| definition's calls are what its specs give: their hooks, or why none,
||| for which a call of it is refused where it is made (`foreignRefusal`).
public export
data Registered
  = ByName (Hooks LibraryFunction)
  | BySpecs (Hooks LibraryFunction) (Either ForeignMiss (Hooks LibraryFunction))

||| The hooks of a definition's name (`Registered`).
export
namedHooks : Registered -> Hooks LibraryFunction
namedHooks (ByName hs) = hs
namedHooks (BySpecs hs _) = hs

||| What a call of a definition is translated by (`Registered`): its
||| name's hooks, or a `%foreign` definition's specs' hooks or why it has
||| none.
export
callHooks : Registered -> Either ForeignMiss (Hooks LibraryFunction)
callHooks (ByName hs) = Right hs
callHooks (BySpecs _ called) = called

------------------------------------------------------------------------------
-- Shapes
------------------------------------------------------------------------------

||| How a binder's value is used at run time: not at all (quantity 0, a
||| binder of no runtime value, whose position whoever meets it leaves
||| out), or as a quantity says.
public export
data Use = Erased | Used Uses

||| The use a binder's multiplicity gives its value.
export
use : RigCount -> Use
use = elimSemi Erased (Used Once) (const (Used Many))

||| A use as the registry writes a binder's multiplicity.
export
multiplicity : Use -> Multiplicity
multiplicity Erased = M0
multiplicity (Used Once) = M1
multiplicity (Used Many) = Mw

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

%prefix_record_projections off

||| An entry the validation resolves (`site`): the entry, the definition
||| the registry names, as the registry writes it, for a message, and as
||| the context names it, interned once where the program is read, before
||| the context is frozen, and what the validation checks there.
public export
record RegistrySite where
  constructor MkRegistrySite
  entry : AnyEntry
  named : QName
  name : Name
  expected : SiteCheck

%prefix_record_projections on

||| Every entry the validation resolves, the name of its definition interned
||| once (`toName`): read where the program is read, before the context is
||| frozen, so the validation reads the frozen context alone.
export
registrySites : {auto c : Ref Ctxt Defs} -> Core (List RegistrySite)
registrySites = traverse named (mapMaybe (\e => (e,) <$> site e) entries)
  where
    named : (AnyEntry, QName, SiteCheck) -> Core RegistrySite
    named (e, q, expected) = (\n => MkRegistrySite e q n expected) <$> toName q

||| Every entry, resolved against the frozen context once per compilation,
||| before anything uses the registry, each type normalised in it. An entry
||| whose module the program does not load is not checked; one whose
||| definition is present must be what the entry expects. There is no
||| fallback: a mismatch stops the compilation. A test of the validation
||| gives it a program whose own module defines a keyed name at another
||| shape. The first entry that does not validate is refused where its
||| definition is, or, when the definition is missing, at `fallback`.
export
validate : Frozen -> List RegistrySite -> (fallback : NonEmptyFC) -> Core (Maybe Refusal)
validate frozen sites fallback = check sites
  where
    wrong : FC -> QName -> String -> Refusal
    wrong loc q msg = MkRefusal (Refusal HookShape) (fromMaybe fallback (isNonEmptyFC loc)) (show q ++ ": " ++ msg)

    loaded : List (List String)
    loaded = map (\l => modulePath l.ident) (defsOf frozen).allImported

    check : List RegistrySite -> Core (Maybe Refusal)
    check [] = pure Nothing
    check (s :: ss) = do
      let e = s.entry
      let q = s.named
      let DefinedAs _ _ def _ = definitionIn frozen s.name
        | NotDefined _ => if inModules loaded q then pure (Just (wrong EmptyFC q (mismatch e Missing)))
                          else check ss
      let declared = case (e.entry.key, definition def) of
                       (Foreign _, ForeignDef _ specs) => declares e specs
                       (Foreign _, _) => False
                       _ => True
      -- The definition's normalised shape where it does not conform to
      -- the one the entry expects.
      let unlike : Shape -> Core (Maybe Shape)
          unlike shape = do
            ty <- fullNamesIn frozen . (.value) <$> host.normalise frozen (!(host.typeOf def)).fst
            let found = shapeOf ty
            pure (if conforms shape found then Nothing else Just found)
      if not declared then pure (Just (wrong (location def) q (mismatch e Undeclared))) else
        case s.expected of
          -- A bodiless declaration is its own shape: there is nothing of
          -- its type to compare, only that no body gives it a second
          -- meaning.
          IsBodiless => case definition def of
            ExternDef _ => check ss
            _ => pure (Just (wrong (location def) q (mismatch e Bodied)))
          HasShape shape => case !(unlike shape) of
            Nothing => check ss
            Just found => pure (Just (wrong (location def) q (mismatch e (Found found))))
          -- A faster entry lowers a body that is the definition's meaning,
          -- which a build without the faster entries runs: a definition
          -- with no body would have no meaning there.
          WithBody shape => case (definition def, !(unlike shape)) of
            (PMDef {}, Nothing) => check ss
            (TCon _ _ _ _ _ (Just (_ :: _)) _, Nothing) => check ss
            (PMDef {}, Just found) => pure (Just (wrong (location def) q (mismatch e (Found found))))
            (TCon _ _ _ _ _ (Just (_ :: _)) _, Just found) =>
              pure (Just (wrong (location def) q (mismatch e (Found found))))
            _ => pure (Just (wrong (location def) q (mismatch e Unbodied)))
