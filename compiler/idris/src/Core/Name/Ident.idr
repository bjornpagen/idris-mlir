-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| An identifier, interned: a session holds one table of every text it has
||| met as an identifier, each once, at its own id, so two identifiers are
||| equal exactly when their ids are, and nothing compares their text to
||| decide it. The text is the identifier's own, kept with its id for
||| printing: it is the one string the table holds, not a copy of it.
|||
||| Only the table makes an identifier, so none holds an id the table gives
||| another text. Its first ids are the known vocabulary's
||| (`Core.Name.Known`), each at its ordinal: an identifier the compiler's
||| code spells is a constant, `known k`, and never needs the table.
module Core.Name.Ident

import public Core.Name.Known

import Libraries.Data.StringMap
import Libraries.Text.PrettyPrint.Prettyprinter

%default total

export
record Ident where
  constructor MkIdent
  index : Int
  spelled : String

||| How the identifier is spelled, for a human.
export
(.text) : Ident -> String
(.text) i = i.spelled

export
Eq Ident where
  a == b = a.index == b.index

||| Two identifiers in the order of their text. Anything written from a map
||| or a sort keyed by identifiers is then in an order of its content, the
||| same in every session, whichever identifier the session met first.
export
Ord Ident where
  compare a b = if a.index == b.index then EQ else compare a.spelled b.spelled

export
Show Ident where
  show = spelled

export
Pretty Void Ident where
  pretty = pretty . spelled

||| The known identifier: its ordinal is its id in every session's table.
export
known : Known -> Ident
known k = MkIdent (ordinal k) (spelling k)

||| Which known identifier this is, if it is one.
export
knownOf : Ident -> Maybe Known
knownOf i = fromOrdinal i.index

||| Every identifier the session has met, by its text, and the id the next
||| new text gets.
export
record Idents where
  constructor MkIdents
  byText : StringMap Ident
  next : Int

||| The table of a new session: the known vocabulary, each identifier at its
||| ordinal, and every later text at an id after them. Every ordinal is
||| under `knownCount` and found again by `fromOrdinal` (`below`,
||| `roundTrip`), so walking the ids under it seeds every known identifier.
export
seeded : Idents
seeded = MkIdents (seed (cast knownCount) empty) knownCount
  where
    seed : Nat -> StringMap Ident -> StringMap Ident
    seed Z m = m
    seed (S n) m
        = seed n $ case fromOrdinal (cast n) of
                        Just k => insert (spelling k) (known k) m
                        Nothing => m

||| The identifier spelled so: the table's, or a new one at the next id,
||| with the table that holds it.
export
internIn : String -> Idents -> (Ident, Idents)
internIn s t
    = case lookup s t.byText of
           Just i => (i, t)
           Nothing => let i = MkIdent t.next s in
                          (i, MkIdents (insert s i t.byText) (t.next + 1))

||| The label of a session's table of identifiers.
export
data Interned : Type where
