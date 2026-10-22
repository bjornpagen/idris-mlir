-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Parser.Rule.Package

import public Parser.Lexer.Package

import Data.List1

%default total

||| A grammar of a package description, at bound `n`, run below it if
||| `r`, that reads a token wherever it succeeds.
public export
Rule : (n : Nat) -> (r : Bool) -> Type -> Type
Rule n r = Grammar () Token n r True

||| A grammar of a package description that may succeed reading nothing.
public export
EmptyRule : (n : Nat) -> (r : Bool) -> Type -> Type
EmptyRule n r = Grammar () Token n r False

export
equals : Rule n r ()
equals = terminal "Expected equals" $
                  \case
                    Equals => Just ()
                    _ => Nothing

export
lte : Rule n r ()
lte = terminal "Expected <=" $
               \case
                 LTE => Just ()
                 _ => Nothing

export
gte : Rule n r ()
gte = terminal "Expected >=" $
               \case
                 GTE => Just ()
                 _ => Nothing

export
lt : Rule n r ()
lt = terminal "Expected <=" $
              \case
                LT => Just ()
                _ => Nothing

export
gt : Rule n r ()
gt = terminal "Expected >=" $
              \case
                GT => Just ()
                _ => Nothing

export
eqop : Rule n r ()
eqop = terminal "Expected ==" $
                \case
                  EqOp => Just ()
                  _ => Nothing

export
andop : Rule n r ()
andop = terminal "Expected &&" $
                 \case
                   AndOp => Just ()
                   _ => Nothing

export
eoi : Rule n r ()
eoi = terminal "Expected end of input" $
               \case
                 EndOfInput => Just ()
                 _ => Nothing

-- A property is spelled as one part, with no namespace.
isProperty : String -> Token -> Maybe String
isProperty p (DotSepIdent [] p') = if p == p' then Just p else Nothing
isProperty _ _ = Nothing

export
exactProperty : String -> Rule n r String
exactProperty p = terminal ("Expected property " ++ p) (isProperty p)

export
stringLit : Rule n r String
stringLit = terminal "Expected string" $
                     \case
                       StringLit str => Just str
                       _ => Nothing

export
integerLit : Rule n r Integer
integerLit = terminal "Expected integer" $
                      \case
                        IntegerLit i => Just i
                        _ => Nothing

export
namespacedIdent : Rule n r (List String, String)
namespacedIdent = terminal "Expected namespaced identifier" $
                           \case
                             DotSepIdent ns n => Just (ns, n)
                             _ => Nothing

||| A module's identifier as written, its parts outermost first. It is text
||| here, where nothing can intern it, and becomes a `ModuleIdent` where the
||| package description is read.
export
moduleIdent : Rule n r (List1 String)
moduleIdent = terminal "Expected module identifier" $
                       \case
                         DotSepIdent ns m => Just (lappend ns (m ::: []))
                         _ => Nothing

-- A package's name is spelled as one part, with no namespace.
isPackageName : Token -> Maybe String
isPackageName (DotSepIdent [] str)
    = if isIdent AllowDashes str then Just str else Nothing
isPackageName _ = Nothing

export
packageName : Rule n r String
packageName = terminal "Expected package name" isPackageName

export
dot' : Rule n r ()
dot' = terminal "Expected dot" $
                \case
                  Dot => Just ()
                  _ => Nothing

sep' : Rule n r ()
sep' = terminal "Expected separator" $
                \case
                  Separator => Just ()
                  _ => Nothing

export
sep : Rule n r t -> Rule n r (List t)
sep rule = forget <$> sepBy1 sep' rule
