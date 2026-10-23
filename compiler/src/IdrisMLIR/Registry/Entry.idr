-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What an entry of the registry is: the
||| key the compiler knows a library definition by, the shape it expects
||| the definition to have, and the hook, what the compiler does with it.
module IdrisMLIR.Registry.Entry

import IdrisMLIR.Registry.Name
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Spec.Core.Op as Spec
import IdrisMLIR.Spec.Ops.Values
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
||| give the Prelude's `Nat` functions instead of their unary recursions. A
||| library function it names is a `lib`: the registry writes one by its
||| name (`QName`), and a reader that has read it holds it as it read it.
public export
data NatMeaning : (lib : Type) -> Type where
  ||| The primitive of the arguments: `plus` is `Op BigAdd NatT`, whose sum
  ||| of naturals is a natural.
  Primitive : {k : Nat} -> Prim k -> NatMeaning lib
  ||| The primitive of the arguments' Integers, then the natural of its
  ||| Integer: `minus` is the difference, clamped at 0.
  Clamped : {k : Nat} -> Prim k -> NatMeaning lib
  ||| The comparison of the arguments, as the library function that makes
  ||| a `Bool` of an `Int` gives it: `equalNat` is `intToBool` of `NatCompare
  ||| Eq`.
  Tested : Comparison -> lib -> NatMeaning lib
  ||| The library function on Integers, of the arguments' Integers:
  ||| `compareNat` is `compareInteger`.
  OnIntegers : lib -> NatMeaning lib

||| A function of the array language's generating set, or of `LArray`'s
||| operations, by what its calls are (`Frontend.Translate.Terms`).
public export
data ArrayPrim
  = AShape | ATabulate | AIndex | AUpdate | AFoldLast | AScanLast
  | AReshape | ATranspose | ATake | ADrop | AConcat | APad | AMerge
  | AWithArray | ARead | AWrite | AThaw | ALShape | AGrow | ATabulateIO

||| How many values a function of the array language takes at run time:
||| its operation's operands, which its definition's type must give as
||| many of (`Frontend.Resolve.rowOf`).
public export
generatedOperands : ArrayPrim -> Nat
generatedOperands AShape = 1
generatedOperands ATabulate = 2
generatedOperands AIndex = 2
generatedOperands AUpdate = 3
generatedOperands AFoldLast = 3
generatedOperands AScanLast = 3
generatedOperands AReshape = 2
generatedOperands ATranspose = 1
generatedOperands ATake = 2
generatedOperands ADrop = 2
generatedOperands AConcat = 2
generatedOperands APad = 4
generatedOperands AMerge = 2
generatedOperands AWithArray = 3
generatedOperands ARead = 2
generatedOperands AWrite = 3
generatedOperands AThaw = 2
generatedOperands ALShape = 1
generatedOperands AGrow = 3
generatedOperands ATabulateIO = 2

||| A string `System.Info` substitutes from the compiler. `TargetOs` is the
||| operating system the target triple names. `BackendName` is the name this
||| backend is registered under.
public export
data SystemFact = TargetOs | BackendName

||| A pure op of the dialect as a registry row names it: the
||| specification's op, of one result and no attribute, with its arity, so
||| its operands are counted from the op itself.
public export
record PureOp where
  constructor MkPureOp
  {arity : Nat}
  op : Spec.Op arity 1 0 0

||| Where a refusal the registry makes applies: wherever the program
||| reaches the definition, its use by a trusted library included (threads,
||| finalizers, raw memory, signals, processes: what the language this
||| compiler implements does not have); or only where the user's code names
||| it (the world's operations, which the program's root uses, and the
||| escape hatches a trusted library may hold).
public export
data Reached = WhereverReached | WhereUserCodeNames

||| The kinds of entry. A contract is the one meaning of a definition whose
||| body is no meaning (an external type, an `%extern`, a builtin, a body
||| that only coerces): Idris's backend contract, which every backend
||| implements. A faster entry lowers a definition with a body to another
||| form of the same meaning; a stricter one adds a refusal. Removing a
||| faster or stricter entry may change speed or which programs are
||| refused, never a program's result, so a build without the faster
||| entries runs every program the same; a contract is never removed.
public export
data Kind = Contract | Faster | Stricter

export
Eq Kind where
  Contract == Contract = True
  Faster == Faster = True
  Stricter == Stricter = True
  _ == _ = False

export
Show Kind where
  show Contract = "contract"
  show Faster = "faster"
  show Stricter = "stricter"

||| The kinds a hook that lowers a definition may have: the contract of a
||| definition with no body of its own, or a faster form of one with a body.
public export
data Lowers : Kind -> Type where
  LowersContract : Lowers Contract
  LowersFaster : Lowers Faster

||| What the compiler does with a definition it knows: one constructor per
||| behaviour. Passes match on hooks, never on names, and each hook's
||| handler lives with the pass that meets it.
public export
data Hook : Kind -> Type where
  ||| A pure primitive of Idris's backend contract: its calls are the op of
  ||| this primitive on the call's arguments, then the literals listed, the
  ||| operands the call does not supply. A handle's test for null is one.
  ||| Handler: `Frontend.Translate.application`.
  PureCall : {auto 0 lowers : Lowers kd} -> {i : Nat} -> Spec.Op i 1 0 0 -> List Lit -> Hook kd
  ||| An IO primitive of Idris's backend contract: its calls are an effect
  ||| ordered by the effects its op declares, the action named at the types
  ||| the call fixes (a buffer's word) on the call's arguments, then the
  ||| literals listed (a new buffer's zero byte).
  ||| Handler: `Frontend.Translate.application`.
  IOCall : {auto 0 lowers : Lowers kd} -> {i, o : Nat} -> IOAction i o -> List Lit -> Hook kd
  ||| An array primitive of the backend contract, polymorphic in its
  ||| element: its calls are the access named at the element type the call
  ||| fixes, one size or index per dimension of the array a world orders
  ||| its types name: an IORef's primitives are the accesses of its `Mut`,
  ||| of no dimension, with none. Handler: `Frontend.Translate.application`.
  ArrayCall : {auto 0 lowers : Lowers kd} -> ArrayAccess -> Hook kd
  ||| An external type that is an array a world orders: `ArrayData a` and
  ||| `Buffer` a run of elements, an IORef's `Mut a` one cell; of the
  ||| element its type argument names (`Nothing`), or of the one given
  ||| (`Buffer`'s byte). Handler: `Frontend.Translate.Types.coreType`.
  OrderedArrayType : {auto 0 lowers : Lowers kd} -> Ordered -> Maybe Ty -> Hook kd
  ||| The type of the array language that is a value, `Array s a`: a
  ||| tensor. Opaque: no constructor of it is matched or applied. Handler:
  ||| `Frontend.Translate.Types.coreType`.
  ArrayValueType : {auto 0 lowers : Lowers kd} -> Hook kd
  ||| A function of the array language whose calls are the operation its
  ||| `ArrayPrim` names, in their sequential meaning; its body is not
  ||| translated. Handler: `Frontend.Translate.Terms.application`.
  Generating : {auto 0 lowers : Lowers kd} -> ArrayPrim -> Hook kd
  ||| Base's list. Its nil (its constructor of no field) and cons (its
  ||| constructor of two), which the string builders take apart, are read
  ||| off its family's declaration by the dialect (`ListShape`), never from
  ||| this entry, which no handler reads.
  ListType : {auto 0 lowers : Lowers kd} -> Hook kd
  ||| A data type whose cells every program is checked to rebuild in place
  ||| and hold exclusive, which only a type with exactly one constructor
  ||| that holds fields can keep. Handler:
  ||| `Frontend.Translate.Types.familyIn`.
  InPlaceType : Hook Stricter
  ||| Idris's equality, `Builtin.Equal`: a match on an erased proof of it
  ||| (`Refl`, which `replace` and `rewrite` match) holds where its two
  ||| sides are equal, on Idris's word alone. Handler:
  ||| `Frontend.Translate.Cases.tree`.
  EqualityType : Hook Contract
  ||| A `%foreign` definition whose calls are this primitive, pure, on the
  ||| call's runtime arguments: a buffer's size (`ArrayLength` of bytes).
  ||| Handler: `Frontend.Translate.application`.
  PrimCall : {auto 0 lowers : Lowers kd} -> {n : Nat} -> Prim n -> List Lit -> Hook kd
  ||| A handle that is a foreign constant, as the literal it is: 0 for
  ||| input, 1 for output, 2 for errors, all ones for null, the one
  ||| meaning this compiler's runtime gives a pointer. Handler:
  ||| `Frontend.Translate.application`.
  Handle : {auto 0 lowers : Lowers kd} -> Lit -> Hook kd
  ||| An external type that is a machine word: `AnyPtr` and `Ptr t`, which
  ||| only the runtime's handles inhabit (`t` names what a handle holds,
  ||| not how it is represented), and `OSClock`, a clock reading. Handler:
  ||| `Frontend.Translate.Types.coreType`.
  WordType : {auto 0 lowers : Lowers kd} -> Hook kd
  ||| A function whose calls build a string from a list once, by the
  ||| primitive named: the Prelude's `pack` and `fastPack` over a
  ||| `List Char` (`StrPack`), its `fastConcat` over a `List String`
  ||| (`StrConcat`), which the Prelude's own `%transform` rules make one at
  ||| runtime. Handler: `Frontend.Translate.application`.
  Builds : {auto 0 lowers : Lowers kd} -> {i : Nat} -> Spec.Op i 1 0 0 -> Hook kd
  ||| A `%foreign` definition that stands for a library function of the
  ||| same type and meaning (`fastUnpack` for `unpack`): its calls are
  ||| calls of that function. Handler: `Frontend.Translate.application`.
  Alias : {auto 0 lowers : Lowers kd} -> QName -> Hook kd
  ||| The identity on its last runtime argument, wherever it stands among
  ||| the proofs and types (a pointer cast's follows its erased type); a
  ||| runtime argument before it is not read (`nest`'s cell form). Handler:
  ||| `Frontend.Translate.application`.
  IdentityOnLastArgument : {auto 0 lowers : Lowers kd} -> Hook kd
  ||| A function on naturals whose calls compute what it means on the
  ||| representation of `Nat`, in constant time and stack, instead of its
  ||| unary recursion. Handler: `Frontend.Translate.application`.
  NatOperation : {auto 0 lowers : Lowers kd} -> NatMeaning QName -> Hook kd
  ||| A library function whose calls end the program with a status, after
  ||| which nothing runs (`ub.unreachable`). `System.exitWith` is one: its
  ||| body gives the `PrimIO ()` of `prim__exit` any result type by
  ||| `believe_me`, an escape hatch, sound only because the action does not
  ||| return. Handler: `Frontend.Translate.application`.
  Exits : {auto 0 lowers : Lowers kd} -> Hook kd
  ||| A string `System.Info` takes from the compiler: the target's
  ||| operating system, or this backend's name. Handler:
  ||| `Frontend.Translate.application`.
  SystemInfo : {auto 0 lowers : Lowers kd} -> SystemFact -> Hook kd
  ||| Refused under the rule named, where the hook says: wherever the
  ||| program reaches the definition, or only where the user's code names
  ||| it (a definition the user's definitions refer to, or a spelling in
  ||| the user's source). Handler: `Frontend.Profile.checkReachable`,
  ||| `Frontend.Profile.checkPragmas`.
  Forbidden : Reached -> SomeRule -> Hook Stricter
  ||| A deprecated name. The text names the replacement, and a program that
  ||| calls the name is rejected. Handler: `Frontend.Profile.checkReachable`.
  Deprecated : String -> Hook Stricter
  ||| A trusted library's crash of a string (`idris_crash`): its body ends
  ||| the program with that string. A user's call stays rejected. Handler:
  ||| `Frontend.Profile.checkReachable`, `Frontend.Translate.primitive`.
  LibraryCrash : {auto 0 lowers : Lowers kd} -> Hook kd

||| What sum a data type is, by the registry: base's list, a type whose
||| cells are rebuilt in place, or Idris's equality. One field holds them,
||| so a type cannot be two.
public export
data SumHook = IsList | IsInPlace | IsEquality

||| What the registry says of one definition: one field per kind of hook,
||| each the hook of the first entry of that kind that names it. A reader
||| asks the field it handles, so a new kind of hook is one field. A library
||| function a hook names is a `lib`, as `NatMeaning`'s is: the registry's
||| hooks name each by its `QName`, and a reader's hold it as read.
public export
record Hooks (lib : Type) where
  constructor MkHooks
  pureCall : Maybe (PureOp, List Lit)
  ioCall : Maybe (SomeAction, List Lit)
  arrayCall : Maybe ArrayAccess
  orderedArray : Maybe (Ordered, Maybe Ty)
  valueArray : Bool
  generating : Maybe ArrayPrim
  sumShape : Maybe SumHook
  primCall : Maybe ((k ** Prim k), List Lit)
  handle : Maybe Lit
  wordType : Bool
  builds : Maybe PureOp
  alias : Maybe lib
  identityOnLast : Bool
  natOperation : Maybe (NatMeaning lib)
  exits : Bool
  systemInfo : Maybe SystemFact
  forbidden : Maybe (Reached, SomeRule)
  deprecated : Maybe String
  libraryCrash : Bool

||| A definition no entry names.
export
noHooks : Hooks lib
noHooks = MkHooks Nothing Nothing Nothing Nothing False Nothing Nothing Nothing Nothing False Nothing Nothing
                  False Nothing False Nothing Nothing Nothing False

||| The hooks with one more entry's, after those already there: an earlier
||| entry of the same kind stays.
export
withHook : Hooks QName -> Hook kd -> Hooks QName
withHook hs h = case h of
  PureCall p ls => { pureCall $= keep (MkPureOp p, ls) } hs
  IOCall a ls => { ioCall $= keep (MkSomeAction a, ls) } hs
  ArrayCall p => { arrayCall $= keep p } hs
  OrderedArrayType o e => { orderedArray $= keep (o, e) } hs
  ArrayValueType => { valueArray := True } hs
  Generating g => { generating $= keep g } hs
  ListType => { sumShape $= keep IsList } hs
  InPlaceType => { sumShape $= keep IsInPlace } hs
  EqualityType => { sumShape $= keep IsEquality } hs
  PrimCall p ls => { primCall $= keep ((_ ** p), ls) } hs
  Handle l => { handle $= keep l } hs
  WordType => { wordType := True } hs
  Builds p => { builds $= keep (MkPureOp p) } hs
  Alias q => { alias $= keep q } hs
  IdentityOnLastArgument => { identityOnLast := True } hs
  NatOperation m => { natOperation $= keep m } hs
  Exits => { exits := True } hs
  SystemInfo f => { systemInfo $= keep f } hs
  Forbidden at r => { forbidden $= keep (at, r) } hs
  Deprecated m => { deprecated $= keep m } hs
  LibraryCrash => { libraryCrash := True } hs
  where
    keep : a -> Maybe a -> Maybe a
    keep x Nothing = Just x
    keep _ y = y

||| The hooks with each library function they name read by `readOne`, as a
||| reader that resolves the registry's names holds them; every other hook
||| as it is.
export
readLibraries : Applicative m => (readOne : a -> m b) -> Hooks a -> m (Hooks b)
readLibraries readOne hs =
  (\al, nat => MkHooks hs.pureCall hs.ioCall hs.arrayCall hs.orderedArray hs.valueArray hs.generating
                       hs.sumShape hs.primCall hs.handle hs.wordType hs.builds al hs.identityOnLast
                       nat hs.exits hs.systemInfo hs.forbidden hs.deprecated hs.libraryCrash)
    <$> traverse readOne hs.alias <*> traverse natural hs.natOperation
  where
    natural : NatMeaning a -> m (NatMeaning b)
    natural (Primitive p) = pure (Primitive p)
    natural (Clamped p) = pure (Clamped p)
    natural (Tested c q) = Tested c <$> readOne q
    natural (OnIntegers q) = OnIntegers <$> readOne q

||| The library functions hooks name.
export
libraries : Hooks lib -> List lib
libraries hs = toList hs.alias ++ maybe [] named hs.natOperation
  where
    named : NatMeaning lib -> List lib
    named (Tested _ q) = [q]
    named (OnIntegers q) = [q]
    named _ = []

||| Does the registry give a bodiless `%extern` its meaning: its calls are a
||| primitive, an array operation, a string of `System.Info`, or the
||| identity on its last runtime argument? Any other `%extern` is outside
||| the language.
export
meansExtern : Hooks lib -> Bool
meansExtern hs = isJust hs.pureCall || isJust hs.ioCall || isJust hs.arrayCall || isJust hs.systemInfo ||
                 isJust hs.generating || hs.identityOnLast

------------------------------------------------------------------------------
-- Entries
------------------------------------------------------------------------------

||| What an entry expects to find, by its kind and the kind of its key. A
||| faster entry is on a definition with a body, which is its meaning, so
||| a faster hook on a definition without one is not written: `Typed` is
||| the only form of that kind.
public export
data Expect : Kind -> Key -> Type where
  ||| A definition with a body, at the key's name, whose type has this
  ||| shape: the body is its meaning, which the hook computes another way.
  Typed : Shape -> Expect Faster (Def q)
  ||| A definition at the key's name, of this shape, body or not, which the
  ||| hook refuses.
  Ruled : Shape -> Expect Stricter (Def q)
  ||| A definition with no body of its own at the key's name (an external
  ||| type, a builtin), whose type has this shape: the hook is its meaning.
  External : Shape -> Expect Contract (Def q)
  ||| A definition at the key's name whose body only coerces
  ||| (`believe_me`), whose type has this shape: the hook is the meaning the
  ||| coercion claims, which the backend contract gives.
  Coerced : Shape -> Expect Contract (Def q)
  ||| A bodiless `%extern` declaration at the key's name: its own type is
  ||| what its calls take and give, their arity, quantities and erasure,
  ||| so the entry states none of it again.
  Bodiless : Expect Contract (Def q)
  ||| A definition, at this name, that declares the key's spec and whose type
  ||| has this shape.
  Declared : QName -> Shape -> Expect Contract (Foreign s)
  ||| A definition, at this name, that declares the key's spec and whose type
  ||| has this shape, which the program may no longer use.
  Retired : QName -> Shape -> Expect Stricter (Foreign s)
  ||| Nothing: a spelling has no definition to resolve.
  Written : Expect Stricter (Spelling s)

||| One entry of a table, of its kind: what the compiler knows a definition
||| by, what it expects it to be, and what it does with it.
public export
record Entry (kd : Kind) where
  constructor MkEntry
  key : Key
  expect : Expect kd key
  hook : Hook kd

||| An entry of any kind, as the registry's one table holds them.
public export
record AnyEntry where
  constructor Kinded
  {kind : Kind}
  entry : Entry kind

||| An entry, of the kind its expectation fixes, as a table of entries of
||| every kind holds it. The table holds the kind as a value, and each
||| entry's expectation fixes it where the entry is written, so it is
||| passed as that constant.
export
entry : {kd : Kind} -> (key : Key) -> Expect kd key -> Hook kd -> AnyEntry
entry key expect hook = Kinded (MkEntry key expect hook)

||| What validation checks of the definition an entry resolves to: that its
||| type has a shape and, for a faster or stricter hook on a definition,
||| that it has a body to be the meaning (`Bodied`); that its type has a
||| shape, whatever its body; or that it is a bodiless `%extern`, whose
||| type is its own.
public export
data SiteCheck = WithBody Shape | HasShape Shape | IsBodiless

||| Where validation resolves an entry, and what it checks there; a
||| spelling is not resolved.
export
site : AnyEntry -> Maybe (QName, SiteCheck)
site (Kinded e) = at e.key e.expect
  where
    at : (k : Key) -> Expect kd k -> Maybe (QName, SiteCheck)
    at (Def q) (Typed s) = Just (q, WithBody s)
    at (Def q) (Ruled s) = Just (q, HasShape s)
    at (Def q) (External s) = Just (q, HasShape s)
    at (Def q) (Coerced s) = Just (q, HasShape s)
    at (Def q) Bodiless = Just (q, IsBodiless)
    at (Foreign _) (Declared q s) = Just (q, HasShape s)
    at (Foreign _) (Retired q s) = Just (q, HasShape s)
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
  | ||| A definition with no body, where the entry's hook needs one to be
    ||| the definition's meaning.
    Unbodied

||| The message of a shape mismatch: the entry, what it expects and what was
||| found, through one printer.
export
mismatch : AnyEntry -> Mismatch -> String
mismatch e m =
  "the registry's entry " ++ show e.entry.key ++ " (" ++ show e.kind ++ ") expects " ++ expected ++
  ", but found " ++ found m
  where
    declaring : String
    declaring = case e.entry.key of
      Foreign s => ", declared %foreign " ++ show s
      _ => ""
    expected : String
    expected = case site e of
      Just (q, WithBody s) => show q ++ " : " ++ showShape s ++ ", with a body"
      Just (q, HasShape s) => show q ++ " : " ++ showShape s ++ declaring
      Just (q, IsBodiless) => "%extern " ++ show q
      Nothing => show e.entry.key
    found : Mismatch -> String
    found Missing = "no such definition in its module"
    found Undeclared = "a definition that does not declare it"
    found (DeclaredBy q) = "it declared by " ++ show q
    found (Found s) = showShape s
    found Bodied = "a definition with a body"
    found Unbodied = "a definition with no body"
