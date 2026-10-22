-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What an entry of the registry is: the
||| key the compiler knows a library definition by, the shape it expects
||| the definition to have, and the hook, what the compiler does with it.
module IdrisMLIR.Registry.Entry

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Registry.Name
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Spec.Ops.Comparisons
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.String

%default total

------------------------------------------------------------------------------
-- Keys
------------------------------------------------------------------------------

||| A `%foreign` spec as a library declares it for backends: a calling
||| convention and the function it names, `C:idris2_putStr`. The spec is the
||| backend contract; the Idris name and type that declare it are its shape.
public export
record Spec where
  constructor MkSpec
  convention : String
  function : String

export
Show Spec where
  show s = s.convention ++ ":" ++ s.function

||| One of the specs Idris records for a `%foreign` definition, as written:
||| `C:idris2_putStr, libidris2_support, idris_support.h` is the convention
||| `C` and the function `idris2_putStr`.
export
parseSpec : String -> Maybe Spec
parseSpec s = case break (== ':') (unpack s) of
  (conv@(_ :: _), _ :: rest) =>
    let fn = pack (stripped (takeWhile (/= ',') rest)) in
    if fn == "" then Nothing else Just (MkSpec (pack conv) fn)
  _ => Nothing
  where
    -- The whitespace around the function dropped, from its characters:
    -- base's `trim` sees a string through `strM`, whose `believe_me` this
    -- compiler refuses wherever a program reaches it.
    stripped : List Char -> List Char
    stripped = reverse . dropWhile isSpace . reverse . dropWhile isSpace

||| How the compiler names library knowledge.
public export
data Key
  = ||| An Idris definition.
    Def QName
  | ||| A `%foreign` spec (Idris's own builtins are the closed type `PrimFn`
    ||| and need no key).
    Foreign Spec
  | ||| A spelling in source, checked before TT exists: elaboration can
    ||| erase what it names from TT.
    Spelling String

export
Eq Key where
  Def a == Def b = a == b
  Foreign a == Foreign b = a.convention == b.convention && a.function == b.function
  Spelling a == Spelling b = a == b
  _ == _ = False

export
Show Key where
  show (Def q) = show q
  show (Foreign s) = show s
  show (Spelling s) = s

------------------------------------------------------------------------------
-- Shapes
------------------------------------------------------------------------------

||| Idris's primitive types, as a shape names them.
public export
data PrimTy = IntP IntTy | IntegerP | CharP | DoubleP | StringP | WorldP

export
Eq PrimTy where
  IntP a == IntP b = a == b
  IntegerP == IntegerP = True
  CharP == CharP = True
  DoubleP == DoubleP = True
  StringP == StringP = True
  WorldP == WorldP = True
  _ == _ = False

export
Show PrimTy where
  show (IntP t) = show t
  show IntegerP = "Integer"
  show CharP = "Char"
  show DoubleP = "Double"
  show StringP = "String"
  show WorldP = "%World"

||| How often Idris's type lets a definition use an argument: never at
||| runtime (0), exactly once (1), or any number of times (ω). The
||| registry compares a definition's type with this, which is Idris's own
||| multiplicity and not the dialect's quantity: the dialect has no
||| quantity 0, since nothing it holds is erased.
public export
data Multiplicity = M0 | M1 | Mw

export
Eq Multiplicity where
  M0 == M0 = True
  M1 == M1 = True
  Mw == Mw = True
  _ == _ = False

||| What an entry expects a definition's type to be, compared structurally
||| with its normalised checked type (a fingerprint could not explain a
||| mismatch). Arity, quantities and heads are exact. `Hole` stands for a
||| part the hook does not depend on, such as an implicit argument's type;
||| in a shape found, it stands for a part no shape describes, such as a
||| variable.
public export
data Shape
  = Pi Multiplicity Shape Shape
  | Head Key (List Shape)
  | Prim PrimTy
  | TypeOfTypes
  | Hole

mutual
  ||| Does a shape found conform to the shape expected?
  export
  conforms : (expected : Shape) -> (found : Shape) -> Bool
  conforms Hole _ = True
  conforms (Pi q a b) (Pi r c d) = q == r && conforms a c && conforms b d
  conforms (Head k as) (Head l bs) = k == l && conformsAll as bs
  conforms (Prim p) (Prim r) = p == r
  conforms TypeOfTypes TypeOfTypes = True
  conforms _ _ = False

  conformsAll : List Shape -> List Shape -> Bool
  conformsAll [] [] = True
  conformsAll (a :: as) (b :: bs) = conforms a b && conformsAll as bs
  conformsAll _ _ = False

mutual
  ||| A shape, in parentheses when it is an argument and needs them.
  showAt : (argument : Bool) -> Shape -> String
  showAt arg (Pi q a b) = parens arg ("(" ++ quantity q ++ "_ : " ++ showAt False a ++ ") -> " ++ showAt False b)
    where
      quantity : Multiplicity -> String
      quantity Mw = ""
      quantity M0 = "0 "
      quantity M1 = "1 "
  showAt arg (Head k []) = show k
  showAt arg (Head k as@(_ :: _)) = parens arg (show k ++ showArguments as)
  showAt arg (Prim p) = show p
  showAt arg TypeOfTypes = "Type"
  showAt arg Hole = "_"

  showArguments : List Shape -> String
  showArguments [] = ""
  showArguments (a :: as) = " " ++ showAt True a ++ showArguments as

  parens : Bool -> String -> String
  parens True s = "(" ++ s ++ ")"
  parens False s = s

||| The one printer of shapes, expected and found alike, in
||| Idris's notation with every binder written: `(0 _ : Type) -> (_ :
||| PrimIO.IO _) -> _`.
export
showShape : Shape -> String
showShape = showAt False

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

||| What a function on naturals computes, as primitives on the representation
||| of `Nat`, a big that is never negative: the meaning Idris's own backends
||| give the Prelude's `Nat` functions instead of their unary recursions.
public export
data NatMeaning : Type where
  ||| The primitive of the arguments: `plus` is `Op BigAdd NatT`, whose sum
  ||| of naturals is a natural.
  Primitive : {k : Nat} -> Prim k -> NatMeaning
  ||| The primitive of the arguments' Integers, then the natural of its
  ||| Integer: `minus` is the difference, clamped at 0.
  Clamped : {k : Nat} -> Prim k -> NatMeaning
  ||| The comparison of the arguments, as the library function that makes
  ||| a `Bool` of an `Int` gives it: `equalNat` is `intToBool` of `NatCompare
  ||| Eq`.
  Tested : CmpPredicate -> QName -> NatMeaning
  ||| The library function on Integers, of the arguments' Integers:
  ||| `compareNat` is `compareInteger`.
  OnIntegers : QName -> NatMeaning

||| A function of the array language's generating set, or of `LArray`'s
||| operations, by what its calls are (`Frontend.Translate.Terms`).
public export
data ArrayPrim
  = AShape | ATabulate | AIndex | AUpdate | AFoldLast | AScanLast
  | AReshape | ATranspose | ATake | ADrop | AConcat | APad
  | AWithArray | ARead | AWrite | AThaw | ALShape | AGrow | ATabulateIO

||| A string `System.Info` substitutes from the compiler. `TargetOs` is the
||| operating system the target triple names. `BackendName` is the name this
||| backend is registered under.
public export
data SystemFact = TargetOs | BackendName

||| What the compiler does with a definition it knows: one constructor per
||| behaviour. Passes match on hooks, never on names, and each hook's
||| handler lives with the pass that meets it.
public export
data Hook : Type where
  ||| A pure primitive of Idris's backend contract: its calls are the op of
  ||| this primitive on the call's arguments, then the literals listed, the
  ||| operands the call does not supply. A handle's test for null is one.
  ||| Handler: `Frontend.Translate.application`.
  PureCall : PurePrim -> List Lit -> Hook
  ||| An IO primitive of Idris's backend contract: its calls are an effect
  ||| in the world's order, the op of this primitive at the types the call
  ||| fixes (a buffer's word) on the call's arguments, then the literals
  ||| listed (a new buffer's zero byte), then the world.
  ||| Handler: `Frontend.Translate.application`.
  IOCall : IOPrim -> List Lit -> Hook
  ||| An array primitive of the backend contract, polymorphic in its
  ||| element: its calls are the op of this primitive (`ArrayNew`,
  ||| `ArrayGet`, `ArraySet`) at the element type the call fixes, one size
  ||| or index per dimension of the array a world orders its types name:
  ||| an IORef's primitives are the array ops on its `Mut`, of no
  ||| dimension, with none. Handler: `Frontend.Translate.application`.
  ArrayCall : IOPrim -> Hook
  ||| An external type that is an array a world orders: `ArrayData a` and
  ||| `Buffer` a run of elements, an IORef's `Mut a` one cell; of the
  ||| element its type argument names (`Nothing`), or of the one given
  ||| (`Buffer`'s byte). Handler: `Frontend.Translate.Types.coreType`.
  OrderedArrayType : Ordered -> Maybe Ty -> Hook
  ||| A type of the array language that is a value, `Array s a` or
  ||| `LArray s a`: a tensor. Opaque: no constructor of it is matched or
  ||| applied. Handler: `Frontend.Translate.Types.coreType`.
  ArrayValueType : Hook
  ||| A function of the array language whose calls are the operation its
  ||| `ArrayPrim` names, in their sequential meaning; its body is not
  ||| translated. Handler: `Frontend.Translate.Terms.application`.
  Generating : ArrayPrim -> Hook
  ||| Base's list, a sum whose nil (its constructor of no field) and cons
  ||| (its constructor of two) the string builders take apart (`Term.DataShape`'s
  ||| `BaseListSum`). Handler: `Frontend.Translate.Types.dataInstance`.
  ListType : Hook
  ||| A data type whose cells every program is checked to rebuild in place
  ||| and hold exclusive (`Term.DataShape`'s `InPlaceSum`). Handler:
  ||| `Frontend.Translate.Types.dataInstance`.
  InPlaceType : Hook
  ||| A `%foreign` definition whose calls are this primitive, pure, on the
  ||| call's runtime arguments: a buffer's size (`ArrayLength` of bytes).
  ||| Handler: `Frontend.Translate.application`.
  PrimCall : {k : Nat} -> Prim k -> Hook
  ||| A handle that is a foreign constant, as the literal it is: 0 for
  ||| input, 1 for output, 2 for errors, all ones for null, the one
  ||| meaning this compiler's runtime gives a pointer. Handler:
  ||| `Frontend.Translate.application`.
  Handle : Lit -> Hook
  ||| An external type that is a machine word: `AnyPtr` and `Ptr t`, which
  ||| only the runtime's handles inhabit (`t` names what a handle holds,
  ||| not how it is represented), and `OSClock`, a clock reading. Handler:
  ||| `Frontend.Translate.Types.coreType`.
  WordType : Hook
  ||| A function whose calls build a string from a list once, by the
  ||| primitive named: the Prelude's `pack` and `fastPack` over a
  ||| `List Char` (`StrPack`), its `fastConcat` over a `List String`
  ||| (`StrConcat`), which the Prelude's own `%transform` rules make one at
  ||| runtime. Handler: `Frontend.Translate.application`.
  Builds : PurePrim -> Hook
  ||| A `%foreign` definition that stands for a library function of the
  ||| same type and meaning (`fastUnpack` for `unpack`): its calls are
  ||| calls of that function. Handler: `Frontend.Translate.application`.
  Alias : QName -> Hook
  ||| The identity on its last runtime argument, wherever it stands among
  ||| the proofs and types (`natToFinLT`'s precedes two erased ones); a
  ||| runtime argument before it is not read (`nest`'s cell form,
  ||| `merge`'s extents). Handler: `Frontend.Translate.application`.
  IdentityOnLastArgument : Hook
  ||| The head of a program's root, `unsafePerformIO main`, which the
  ||| compiler writes as world-passing code. Handler:
  ||| `Frontend.Translate.Programs.translateIOProgram`.
  ProgramRoot : Hook
  ||| A function on naturals whose calls compute what it means on the
  ||| representation of `Nat`, in constant time and stack, instead of its
  ||| unary recursion. Handler: `Frontend.Translate.application`.
  NatOperation : NatMeaning -> Hook
  ||| A library function whose calls end the program with a status: the
  ||| IO primitive named, after which nothing runs (`ub.unreachable`).
  ||| `System.exitWith` is one: its body gives the `PrimIO ()` of
  ||| `prim__exit` any result type by `believe_me`, an escape hatch, sound
  ||| only because the action does not return. Handler:
  ||| `Frontend.Translate.application`.
  Exits : IOPrim -> Hook
  ||| A string `System.Info` takes from the compiler: the target's
  ||| operating system, or this backend's name. Handler:
  ||| `Frontend.Translate.application`.
  SystemInfo : SystemFact -> Hook
  ||| Rejected where the user's code uses it, under the rule named:
  ||| a definition the user's definitions refer to, or a spelling in the
  ||| user's source. Handler:
  ||| `Frontend.Profile.checkReachable`, `Frontend.Profile.checkPragmas`.
  Forbidden : SomeRule -> Hook
  ||| A deprecated name. The text names the replacement, and a program that
  ||| calls the name is rejected. Handler: `Frontend.Profile.checkReachable`.
  Deprecated : String -> Hook
  ||| A trusted library's crash of a string (`idris_crash`): its body ends
  ||| the program with that string. A user's call stays rejected. Handler:
  ||| `Frontend.Profile.checkReachable`, `Frontend.Translate.primitive`.
  LibraryCrash : Hook

||| The only kinds of hook. A `faster` hook is another lowering with the same
||| meaning; a `stricter` hook adds a rejection. Removing a hook may change
||| speed or which programs are rejected, never a program's result.
public export
data Kind = Faster | Stricter

export
Show Kind where
  show Faster = "faster"
  show Stricter = "stricter"

||| Every hook has exactly one kind, by construction.
export
kind : Hook -> Kind
kind (PureCall _ _) = Faster
kind (IOCall _ _) = Faster
kind (ArrayCall _) = Faster
kind (OrderedArrayType _ _) = Faster
kind ArrayValueType = Faster
kind (Generating _) = Faster
kind ListType = Faster
kind InPlaceType = Stricter
kind (PrimCall _) = Faster
kind (Handle _) = Faster
kind (Builds _) = Faster
kind (Alias _) = Faster
kind WordType = Faster
kind IdentityOnLastArgument = Faster
kind ProgramRoot = Faster
kind (NatOperation _) = Faster
kind (Exits _) = Faster
kind (SystemInfo _) = Faster
kind (Forbidden _) = Stricter
kind (Deprecated _) = Stricter
kind LibraryCrash = Faster

||| What sum a data type is, by the registry: base's list, or a type whose
||| cells are rebuilt in place. One field holds both, so a type cannot be
||| both.
public export
data SumHook = IsList | IsInPlace

||| What the registry says of one definition: one field per kind of hook,
||| each the hook of the first entry of that kind that names it. A reader
||| asks the field it handles, so a new kind of hook is one field.
public export
record Hooks where
  constructor MkHooks
  pureCall : Maybe (PurePrim, List Lit)
  ioCall : Maybe (IOPrim, List Lit)
  arrayCall : Maybe IOPrim
  orderedArray : Maybe (Ordered, Maybe Ty)
  valueArray : Bool
  generating : Maybe ArrayPrim
  sumShape : Maybe SumHook
  primCall : Maybe (k ** Prim k)
  handle : Maybe Lit
  wordType : Bool
  builds : Maybe PurePrim
  alias : Maybe QName
  identityOnLast : Bool
  programRoot : Bool
  natOperation : Maybe NatMeaning
  exits : Maybe IOPrim
  systemInfo : Maybe SystemFact
  forbidden : Maybe SomeRule
  deprecated : Maybe String
  libraryCrash : Bool

||| A definition no entry names.
export
noHooks : Hooks
noHooks = MkHooks Nothing Nothing Nothing Nothing False Nothing Nothing Nothing Nothing False Nothing Nothing
                  False False Nothing Nothing Nothing Nothing Nothing False

||| The hooks with one more entry's, after those already there: an earlier
||| entry of the same kind stays.
export
withHook : Hooks -> Hook -> Hooks
withHook hs h = case h of
  PureCall p ls => { pureCall $= keep (p, ls) } hs
  IOCall p ls => { ioCall $= keep (p, ls) } hs
  ArrayCall p => { arrayCall $= keep p } hs
  OrderedArrayType o e => { orderedArray $= keep (o, e) } hs
  ArrayValueType => { valueArray := True } hs
  Generating g => { generating $= keep g } hs
  ListType => { sumShape $= keep IsList } hs
  InPlaceType => { sumShape $= keep IsInPlace } hs
  PrimCall p => { primCall $= keep (_ ** p) } hs
  Handle l => { handle $= keep l } hs
  WordType => { wordType := True } hs
  Builds p => { builds $= keep p } hs
  Alias q => { alias $= keep q } hs
  IdentityOnLastArgument => { identityOnLast := True } hs
  ProgramRoot => { programRoot := True } hs
  NatOperation m => { natOperation $= keep m } hs
  Exits p => { exits $= keep p } hs
  SystemInfo f => { systemInfo $= keep f } hs
  Forbidden r => { forbidden $= keep r } hs
  Deprecated m => { deprecated $= keep m } hs
  LibraryCrash => { libraryCrash := True } hs
  where
    keep : a -> Maybe a -> Maybe a
    keep x Nothing = Just x
    keep _ y = y

||| Does the registry give a bodiless `%extern` its meaning: its calls are a
||| primitive, an array operation, a string of `System.Info`, or the
||| identity on its last runtime argument? Any other `%extern` is outside
||| the language.
export
meansExtern : Hooks -> Bool
meansExtern hs = isJust hs.pureCall || isJust hs.ioCall || isJust hs.arrayCall || isJust hs.systemInfo ||
                 isJust hs.generating || hs.identityOnLast

------------------------------------------------------------------------------
-- Entries
------------------------------------------------------------------------------

||| What an entry expects to find, by the kind of its key.
public export
data Expect : Key -> Type where
  ||| A definition, at the key's name, whose type has this shape.
  Typed : Shape -> Expect (Def q)
  ||| A bodiless `%extern` declaration at the key's name: its own type is
  ||| what its calls take and give, their arity, quantities and erasure,
  ||| so the entry states none of it again.
  Bodiless : Expect (Def q)
  ||| A definition, at this name, that declares the key's spec and whose type
  ||| has this shape.
  Declared : QName -> Shape -> Expect (Foreign s)
  ||| Nothing: a spelling has no definition to resolve.
  Written : Expect (Spelling s)

||| One entry of a table: what the compiler knows a definition by, what it
||| expects it to be, and what it does with it.
public export
record Entry where
  constructor MkEntry
  key : Key
  expect : Expect key
  hook : Hook

||| What validation checks of the definition an entry resolves to: that its
||| type has a shape, or that it is a bodiless `%extern`, whose type is
||| its own.
public export
data SiteCheck = HasShape Shape | IsBodiless

||| Where validation resolves an entry, and what it checks there; a
||| spelling is not resolved.
export
site : Entry -> Maybe (QName, SiteCheck)
site e = at e.key e.expect
  where
    at : (k : Key) -> Expect k -> Maybe (QName, SiteCheck)
    at (Def q) (Typed s) = Just (q, HasShape s)
    at (Def q) Bodiless = Just (q, IsBodiless)
    at (Foreign _) (Declared q s) = Just (q, HasShape s)
    at (Spelling _) Written = Nothing

||| What validation finds wrong with an entry whose definition is present.
public export
data Mismatch
  = ||| The definition's module is loaded, and the definition is not in it.
    Missing
  | ||| The definition does not declare the entry's spec.
    Undeclared
  | ||| Another definition declares the entry's spec.
    DeclaredBy QName
  | ||| The definition's normalised type, which does not conform.
    Found Shape
  | ||| A definition with a body, where the entry expects a bodiless
    ||| `%extern`.
    Bodied

||| The message of a shape mismatch: the entry, what it expects and what was
||| found, through one printer.
export
mismatch : Entry -> Mismatch -> String
mismatch e m =
  "the registry's entry " ++ show e.key ++ " (" ++ show (kind e.hook) ++ ") expects " ++ expected ++
  ", but found " ++ found m
  where
    declaring : String
    declaring = case e.key of
      Foreign s => ", declared %foreign " ++ show s
      _ => ""
    expected : String
    expected = case site e of
      Just (q, HasShape s) => show q ++ " : " ++ showShape s ++ declaring
      Just (q, IsBodiless) => "%extern " ++ show q
      Nothing => show e.key
    found : Mismatch -> String
    found Missing = "no such definition in its module"
    found Undeclared = "a definition that does not declare it"
    found (DeclaredBy q) = "it declared by " ++ show q
    found (Found s) = showShape s
    found Bodied = "a definition with a body"
