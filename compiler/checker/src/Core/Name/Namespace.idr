-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Name.Namespace

import public Core.Name.Ident

import Data.List
import Data.String
import Libraries.Data.String.Extra
import Libraries.Text.PrettyPrint.Prettyprinter
import Libraries.Utils.Path

%default total

-------------------------------------------------------------------------------------
-- TYPES
-------------------------------------------------------------------------------------

||| Nested namespaces are stored in reverse order.
||| i.e. `X.Y.Z.foo` will be represented as `NS [Z,Y,X] foo`
||| As a consequence we hide the representation behind an opaque type alias
||| and force users to manufacture and manipulate namespaces via the safe
||| functions we provide.
export
data Namespace : Type where
  MkNS : List Ident -> Namespace

%name Namespace ns

||| A Module Identifier is, similarly to a namespace, stored inside out.
export
data ModuleIdent : Type where
  MkMI : List Ident -> ModuleIdent

%name Namespace mi

||| Sometimes we need to convert a module identifier to the corresponding
||| namespace. It is still useful to have them as distinct types as it
||| clarifies the distinct roles of X.Y.Z as a module name vs. S.T.U as a
||| namespace in `import X.Y.Z as S.T.U`.
export
miAsNamespace : ModuleIdent -> Namespace
miAsNamespace (MkMI mi) = MkNS mi

||| Sometimes we need to convert a namespace to the corresponding
||| module identifier. It is still useful to have them as distinct types as
||| it clarifies the distinct roles of X.Y.Z as a module name vs. S.T.U as a
||| namespace in `import X.Y.Z as S.T.U`.
export
nsAsModuleIdent : Namespace -> ModuleIdent
nsAsModuleIdent (MkNS ns) = MkMI ns

-------------------------------------------------------------------------------------
-- SMART CONSTRUCTORS
-------------------------------------------------------------------------------------

||| The namespace of these parts, outermost first, as it is written:
||| `nsOf [a, b]` is `a.b`. A namespace spelled as text is made by the
||| session's table of identifiers (`Core.Context.internNamespace`).
export
nsOf : List Ident -> Namespace
nsOf parts = MkNS (reverse parts)

export
mkNestedNamespace : Maybe Namespace -> Ident -> Namespace
mkNestedNamespace Nothing n = MkNS [n]
mkNestedNamespace (Just (MkNS ns)) n = MkNS (n :: ns)

export
mkModuleIdent : Maybe Namespace -> Ident -> ModuleIdent
mkModuleIdent Nothing n = MkMI [n]
mkModuleIdent (Just (MkNS ns)) n = MkMI (n :: ns)

-------------------------------------------------------------------------------------
-- MANIPULATING NAMESPACES
-------------------------------------------------------------------------------------

||| Extend an existing namespace with additional name parts to form a more local one.
||| e.g. `X.Y.Z <.> S.T.U` to get `X.Y.Z.S.T.U`.
export
(<.>) : (existing, local : Namespace) -> Namespace
(MkNS existing) <.> (MkNS local)
   -- The namespaces are stored in reverse order so the local should end up at
   -- the front of the existing one
   = MkNS (local ++ existing)

export
replace : (old : ModuleIdent) -> (new, ns : Namespace) -> Namespace
replace (MkMI old) (MkNS new) (MkNS ns) = MkNS (go ns) where

  go : List Ident -> List Ident
  go [] = []
  go (m :: ms)
        = if old == (m :: ms)
             then new
             else m :: go ms

||| Use at your own risks!
export
unsafeUnfoldNamespace : Namespace -> List Ident
unsafeUnfoldNamespace (MkNS ns) = ns

export
unsafeFoldNamespace : List Ident -> Namespace
unsafeFoldNamespace = MkNS

export
unsafeUnfoldModuleIdent : ModuleIdent -> List Ident
unsafeUnfoldModuleIdent (MkMI ns) = ns

export
unsafeFoldModuleIdent : List Ident -> ModuleIdent
unsafeFoldModuleIdent = MkMI

namespace ModuleIdent
  ||| A.B.C -> "A/B/C"
  export
  toPath : ModuleIdent -> String
  toPath = joinPath . reverse . map (.text) . unsafeUnfoldModuleIdent

  export
  parent : ModuleIdent -> Maybe ModuleIdent
  parent (MkMI (_::rest)) = Just $ MkMI rest
  parent _ = Nothing

-------------------------------------------------------------------------------------
-- HIERARCHICAL STRUCTURE
-------------------------------------------------------------------------------------

-- We don't use the prefix/suffix terminology as it is confusing: are we talking
-- about the namespaces or their representation? Instead our library is structured
-- around the parent/child relation induced by nested namespaces.

||| Nested namespaces naturally give rise to a hierarchical structure. In particular
||| from a given namespace we can compute all of the parent (aka englobing) ones.
||| For instance `allParents Data.List.Properties` should yield a set containing
||| both `Data.List` and `Data` (no guarantee is given on the order).
export
allParents : Namespace -> List Namespace
allParents (MkNS ns) = go ns where

  go : List Ident -> List Namespace
  go [] = []
  go (n :: ns) = MkNS (n :: ns) :: go ns

||| We can check whether a given namespace is a parent (aka englobing) namespace
||| of a candidate namespace.
||| We expect that `all (\ p => isParentOf p ns) (allParents ns)` holds true.
export
isParentOf : (given, candidate : Namespace) -> Bool
isParentOf (MkNS ms) (MkNS ns)
  -- This is not a typo: namespaces are stored in reverse order so a namespace is
  -- a prefix of another if its reversed list of identifiers is a suffix of that
  -- other's list of identifiers: what is left of it once its extra identifiers
  -- are dropped. (`isSuffixOf` would reverse both lists, on every call, and
  -- the elaborator asks for each name it resolves against every namespace in
  -- scope.)
  = let lm = length ms
        ln = length ns in
        lm <= ln && drop (ln `minus` lm) ns == ms

||| When writing qualified names users often do not want to spell out the full
||| namespace, rightly considering that an unambiguous segment should be enough.
||| This function checks whether a candidate is an approximation of a given
||| namespace.
||| We expect `isApproximationOf List.Properties Data.List.Properties` to hold true
||| while `isApproximationOf Data.List Data.List.Properties` should not.
export
isApproximationOf : (given, candidate : Namespace) -> Bool
isApproximationOf (MkNS ms) (MkNS ns)
  -- This is not a typo: namespaces are stored in reverse order so a namespace matches
  -- the end of another if its representation as a list of identifiers is a prefix of
  -- the other's.
  = isPrefixOf ms ns

||| We can check whether a given identifier is in the path of a given
||| namespace.
export
isInPathOf : (i : Ident) -> (candidate : Namespace) -> Bool
isInPathOf i (MkNS ns) = i `elem` ns

-------------------------------------------------------------------------------------
-- INSTANCES
-------------------------------------------------------------------------------------

export
Eq Namespace where
  (MkNS ms) == (MkNS ns) = ms == ns

export
Eq ModuleIdent where
  (MkMI ms) == (MkMI ns) = ms == ns

export
Ord Namespace where
    compare (MkNS ms) (MkNS ns) = compare ms ns

export
Ord ModuleIdent where
    compare (MkMI ms) (MkMI ns) = compare ms ns

-- TODO: move somewhere more appropriate
export
showSep : String -> List String -> String
showSep sep = Libraries.Data.String.Extra.join sep

export
showNSWithSep : String -> Namespace -> String
showNSWithSep sep (MkNS ns) = showSep sep (reverse (map (.text) ns))

export
Show Namespace where
  show = showNSWithSep "."

export
Show ModuleIdent where
  show = showNSWithSep "." . miAsNamespace

export
Pretty Void Namespace where
  pretty (MkNS ns) = concatWith (surround dot) (pretty <$> reverse ns)

export
Pretty Void ModuleIdent where
  pretty = pretty . miAsNamespace


-------------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------------

||| This is used when evaluating things in the REPL
export
emptyNS : Namespace
emptyNS = MkNS []

export
mainNS : Namespace
mainNS = nsOf [known KMain]

export
partialEvalNS : Namespace
partialEvalNS = nsOf [known K_PE]

export
builtinNS : Namespace
builtinNS = nsOf [known KBuiltin]

export
preludeNS : Namespace
preludeNS = nsOf [known KPrelude]

export
numNS : Namespace
numNS = nsOf [known KPrelude, known KNum]

export
typesNS : Namespace
typesNS = nsOf [known KPrelude, known KTypes]

export
basicsNS : Namespace
basicsNS = nsOf [known KPrelude, known KBasics]

export
eqOrdNS : Namespace
eqOrdNS = nsOf [known KPrelude, known KEqOrd]

export
primIONS : Namespace
primIONS = nsOf [known KPrimIO]

export
ioNS : Namespace
ioNS = nsOf [known KPrelude, known KIO]

export
reflectionNS : Namespace
reflectionNS = nsOf [known KLanguage, known KReflection]

export
reflectionTTNS : Namespace
reflectionTTNS = nsOf [known KLanguage, known KReflection, known KTT]

export
reflectionTTImpNS : Namespace
reflectionTTImpNS = nsOf [known KLanguage, known KReflection, known KTTImp]

export
dpairNS : Namespace
dpairNS = nsOf [known KBuiltin, known KDPair]

export
natNS : Namespace
natNS = nsOf [known KData, known KNat]

export
list1NS : Namespace
list1NS = nsOf [known KData, known KList1]
