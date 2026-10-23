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

import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Core.Rules

import Data.List.Elem
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Types

import Data.DPair
import Data.Fin
import Data.List
import Data.List1
import Data.Maybe
import Data.String
import Decidable.Equality

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
export
homeOf : Found -> Home
homeOf InBuild = Project
homeOf (InPackage p) = Installed p.name
homeOf (InExtraDir _) = Elsewhere

||| The source of a module of the project: the file its path names. The
||| session names every module as its path names it, the main module among
||| them, whatever namespace its header gives, so the main file is found as
||| every other module's is.
export
moduleSource : {auto c : Ref Ctxt Defs} -> FC -> ModuleIdent -> Core (Maybe String)
moduleSource fc ident = catch (Just <$> nsToSource fc ident) (\_ => pure Nothing)

||| Every checked module the session loaded, by name, each with where Idris
||| found it and its checked file (`allImported`), the main module among
||| them: the modules a term of the program can be located in, since Idris
||| locates a term in the module it elaborated it in, and records each
||| module under the name its terms' locations give.
export
loadedModules : {auto c : Ref Ctxt Defs} -> Core (List (ModuleIdent, Home, String))
loadedModules = do
  defs <- get Ctxt
  pure (map (\l => (l.ident, homeOf l.foundIn, l.file)) defs.allImported)

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
||| none. Those that lower its calls to an operation on its operands the
||| boundary reads once against its type (`rowOf`), and a call reads them
||| as that read them.
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
            ty <- fullNamesIn frozen . (.value) <$> host.normalise frozen (!(readTypeOf def)).fst
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

------------------------------------------------------------------------------
-- A hook read against the definition it lowers
------------------------------------------------------------------------------

||| A definition's parameters, up to the arity its calls are translated
||| at, as a hook that lowers them takes them: each an operand, a value
||| the call gives at run time, or no operand, a binder of quantity 0.
||| `count` is how many operands there are, so a hook indexed by its own
||| operand count takes exactly these.
public export
data Operands : (arity : Nat) -> (count : Nat) -> Type where
  NoParameter : Operands 0 0
  Operand : Operands n k -> Operands (S n) (S k)
  NoOperand : Operands n k -> Operands (S n) k

||| The position of the last operand among the parameters, of a row that
||| has one.
export
lastOperand : Operands n (S k) -> Fin n
lastOperand (Operand ops) = maybe FZ FS (lastIn ops)
  where
    lastIn : Operands m j -> Maybe (Fin m)
    lastIn NoParameter = Nothing
    lastIn (Operand rest) = Just (maybe FZ FS (lastIn rest))
    lastIn (NoOperand rest) = FS <$> lastIn rest
lastOperand (NoOperand ops) = FS (lastOperand ops)

%prefix_record_projections off

||| A library function a hook names, read against its definition where the
||| boundary reads the row (`Translate.Boundary`): the function, every
||| binder its type in normal form shows (`operandsOf`), and which of them
||| are values at run time, `arity` of them (`Operands`), the count the
||| hook's lowering gives it. What a function takes is its type's, which no
||| clause changes; its case tree takes as many as its clauses do, which
||| eta-reduction changes, and its calls read those where they are made
||| (`Terms.libraryCall`). A row whose function takes another number is
||| refused there, once.
public export
record CheckedLibrary (arity : Nat) where
  constructor MkCheckedLibrary
  library : LibraryFunction
  {params : Nat}
  operands : Operands params arity

%prefix_record_projections on

||| What a hook lowers a call to, on as many operands as its index, the
||| registry's row checked against the definition's type once: a function
||| on naturals as primitives on their representation (`NatMeaning`), a
||| library function it calls (`lib`) indexed by the values it takes at
||| run time, as many as the lowering gives it;
||| a string built from the one list it takes (`Builds`); a function of
||| the array language, as many as its operation takes; the identity on
||| the last of its operands; a pure primitive on the operands and the
||| literals the call does not supply; an IO primitive on those and then
||| the world; an array access at the rank its count of operands gives,
||| then the world; and a foreign definition's primitive on the operands
||| and its literals.
public export
data Lowering : (lib : Nat -> Type) -> (count : Nat) -> Type where
  NatPrimitive : Prim k -> Lowering lib k
  NatClamped : Prim k -> Lowering lib k
  ||| The comparison of the two operands, as the library function of one
  ||| value that makes a `Bool` of an `Int` gives it.
  NatTested : Prim 2 -> lib 1 -> Lowering lib 2
  ||| The library function on the operands' integers, of as many values.
  NatOnIntegers : lib k -> Lowering lib k
  Builder : (p : PureOp) -> (0 fits : p.arity = k) -> Lowering lib k
  ArrayOperation : (g : ArrayPrim) -> Lowering lib (generatedOperands g)
  IdentityOnLast : Lowering lib (S k)
  PureOperation : (p : PureOp) -> (lits : List Lit) -> (0 fits : k + length lits = p.arity) -> Lowering lib k
  IOOperation : {o : Nat} -> (lits : List Lit) -> IOAction (k + length lits) o -> Lowering lib (S k)
  AccessOperation : (access : ArrayAccess) -> (rank : Nat) -> Lowering lib (S (accessOperands access rank))
  PrimOperation : (lits : List Lit) -> Prim (k + length lits) -> Lowering lib k

%prefix_record_projections off

||| A hook that lowers a definition's calls, read against the definition's
||| type once, where the boundary reads it: the arity its calls are
||| translated at, its operands among those parameters, and the lowering,
||| indexed by as many operands as the type gives. A call reads its
||| operands by position, so no call can give a hook another number.
public export
record Lowered (lib : Nat -> Type) where
  constructor MkLowered
  {arity : Nat}
  {count : Nat}
  operands : Operands arity count
  lowering : Lowering lib count

%prefix_record_projections on

||| The operands of every binder a type in normal form shows: one at each
||| binder of nonzero quantity, as a hook takes them (`Operands`). What a
||| definition takes is its type's, whatever its clauses take, so a hook's
||| row (`rowOf`) and a library function's definition (`CheckedLibrary`)
||| are read by it.
export
operandsOf : Term vs -> (n : Nat ** k : Nat ** Operands n k)
operandsOf (Bind _ _ (Pi _ rig _ _) sc) =
  let (n ** k ** ops) = operandsOf sc in
  case use rig of
    Erased => (S n ** k ** NoOperand ops)
    Used _ => (S n ** S k ** Operand ops)
operandsOf _ = (0 ** 0 ** NoParameter)

||| The operands among the first `arity` binders of a type in normal form:
||| one at each binder of nonzero quantity. Nothing for a type that shows
||| fewer binders. A hook's row reads by it what the binders of its type as
||| written take (`rowOf`).
export
operandsUpTo : (arity : Nat) -> Term vs -> Maybe (k ** Operands arity k)
operandsUpTo Z _ = Just (0 ** NoParameter)
operandsUpTo (S n) (Bind _ _ (Pi _ rig _ _) sc) = do
  (k ** ops) <- operandsUpTo n sc
  pure (case use rig of
          Erased => (k ** NoOperand ops)
          Used _ => (S k ** Operand ops))
operandsUpTo (S n) _ = Nothing

||| The row of a definition whose calls a hook lowers, read off its type in
||| normal form (`normal`): at the operands of every binder that type shows
||| (`typed`, `operandsOf`), what the definition takes, a definition with
||| clauses as a bodiless declaration, whatever its clauses take; or, for a
||| function of the array language and an identity, at the binders its
||| type shows as written (`shown`), which say what it takes. The hooks are
||| taken in the order a call of it tries them. What the row and the type
||| disagree on is the message of the refusal: the boundary refuses it
||| once, where it reads the definition, and nothing after can meet it.
export
rowOf : {arity : Nat} -> (typed : (k ** Operands arity k)) -> (shown : Nat) -> (normal : Term vs) -> Hooks lib ->
        Either String (Maybe (Lowered (const lib)))
rowOf typed shown normal hs = traverse id $
      map (\m => natural m typed) hs.natOperation
  <|> map (\p => builder p typed) hs.builds
  <|> map (\g => written >>= generated g) hs.generating
  <|> (if hs.identityOnLast then Just (written >>= identity) else Nothing)
  <|> map (\(p, lits) => pureOp p lits typed) hs.pureCall
  <|> map (\(a, lits) => action a lits typed) hs.ioCall
  <|> map (\a => access a typed) hs.arrayCall
  <|> map (\(p, lits) => primOp p lits typed) hs.primCall
  where
    written : Either String (k ** Operands shown k)
    written = maybe (Left ("its type as written shows " ++ show shown ++ " binders, which its normal form does not")) Right
                    (operandsUpTo shown normal)

    takes : Nat -> String
    takes k = ", and the definition takes " ++ show k ++ " values at run time"

    -- A lowering holds the arity its operands are read at, so each reading
    -- below takes the one its operands were read at.
    natural : {n : Nat} -> NatMeaning lib -> (k ** Operands n k) -> Either String (Lowered (const lib))
    natural (Primitive {k = pk} p) (k ** ops) = case decEq k pk of
      Yes Refl => Right (MkLowered ops (NatPrimitive p))
      No _ => Left ("the registry's natural operation of " ++ show pk ++ " operands" ++ takes k)
    natural (Clamped {k = pk} p) (k ** ops) = case decEq k pk of
      Yes Refl => Right (MkLowered ops (NatClamped p))
      No _ => Left ("the registry's natural operation of " ++ show pk ++ " operands" ++ takes k)
    natural (Tested c toBool) (k ** ops) = case decEq k 2 of
      Yes Refl => Right (MkLowered ops (NatTested (NatCompare c) toBool))
      No _ => Left ("the registry's comparison of two naturals" ++ takes k)
    natural (OnIntegers onIntegers) (k ** ops) = Right (MkLowered ops (NatOnIntegers onIntegers))

    builder : {n : Nat} -> PureOp -> (k ** Operands n k) -> Either String (Lowered (const lib))
    builder p (k ** ops) = case decEq p.arity k of
      Yes fits => Right (MkLowered ops (Builder p fits))
      No _ => Left ("the registry's string builder of " ++ show p.arity ++ " operands" ++ takes k)

    generated : {n : Nat} -> ArrayPrim -> (k ** Operands n k) -> Either String (Lowered (const lib))
    generated g (k ** ops) = case decEq k (generatedOperands g) of
      Yes Refl => Right (MkLowered ops (ArrayOperation g))
      No _ => Left ("the array language's operation of " ++ show (generatedOperands g) ++ " operands" ++ takes k)

    identity : {n : Nat} -> (k ** Operands n k) -> Either String (Lowered (const lib))
    identity (S j ** ops) = Right (MkLowered ops IdentityOnLast)
    identity (Z ** _) = Left "the registry names an identity on its last runtime parameter, and it has none"

    pureOp : {n : Nat} -> PureOp -> List Lit -> (k ** Operands n k) -> Either String (Lowered (const lib))
    pureOp p lits (k ** ops) = case decEq (k + length lits) p.arity of
      Yes fits => Right (MkLowered ops (PureOperation p lits fits))
      No _ => Left ("the registry's primitive of " ++ show p.arity ++ " operands, " ++ show (length lits) ++
                    " of them literals" ++ takes k)

    -- The world is an IO primitive's last value.
    action : {n : Nat} -> SomeAction -> List Lit -> (k ** Operands n k) -> Either String (Lowered (const lib))
    action (MkSomeAction {operands} a) lits (S j ** ops) = case decEq (j + length lits) operands of
      Yes Refl => Right (MkLowered ops (IOOperation lits a))
      No _ => Left ("the registry's IO primitive of " ++ show operands ++ " operands and the world, " ++
                    show (length lits) ++ " of them literals" ++ takes (S j))
    action (MkSomeAction {operands} a) lits (Z ** _) =
      Left ("the registry's IO primitive of " ++ show operands ++ " operands and the world" ++ takes Z)

    access : {n : Nat} -> ArrayAccess -> (k ** Operands n k) -> Either String (Lowered (const lib))
    access acc (S j ** ops) = case accessRank acc j of
      Just (rank ** Refl) => Right (MkLowered ops (AccessOperation acc rank))
      Nothing => Left ("the registry's array access, which no rank of an array takes" ++ takes (S j))
    access acc (Z ** _) = Left ("the registry's array access, which takes the world" ++ takes Z)

    primOp : {n : Nat} -> (k ** Prim k) -> List Lit -> (k ** Operands n k) -> Either String (Lowered (const lib))
    primOp (pk ** p) lits (k ** ops) = case decEq (k + length lits) pk of
      Yes Refl => Right (MkLowered ops (PrimOperation lits p))
      No _ => Left ("the registry's primitive of " ++ show pk ++ " operands, " ++ show (length lits) ++
                    " of them literals" ++ takes k)
