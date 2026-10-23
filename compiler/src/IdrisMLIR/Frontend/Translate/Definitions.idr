-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A definition's identity, its address in the context, and the index of
||| the context an address is. They sit below everything that keys by
||| address, the readings an instance is keyed by among them, which the
||| translation's state caches.
module IdrisMLIR.Frontend.Translate.Definitions

import Core.Context
import Core.Core
import Idris.Host

import IdrisMLIR.Frontend.Walk

import Data.Fin
import Data.Vect

%default total

||| A definition's identity: its address in the context (`Walk.addressOf`);
||| nothing for a name the context does not hold, which no table keeps.
||| For a site that needs the address alone; one that needs the definition
||| too reads it as it was read (`State.readOf`).
export
definitionAddress : Context -> Name -> Maybe Address
definitionAddress ctx n = addressOf <$> placementIn ctx n

||| A name the context resolves to an entry that is not negative has an
||| address, its placement's (`Walk.placedWhereResolved`).
export
0 addressedWhereResolved : {0 ctx : Context} -> {0 n : Name} -> {0 i : Int} ->
                           getNameID n ctx = Just i -> (i < 0) = False ->
                           (a : Address ** definitionAddress ctx n = Just a)
addressedWhereResolved resolved nonNegative = case placedWhereResolved resolved nonNegative of
  (p ** placed) => (addressOf p ** cong (map addressOf) placed)

||| A name the context gives no place has no address: the address is the
||| place's (`definitionAddress`).
export
0 unplacedUnaddressed : {0 ctx : Context} -> {0 n : Name} -> placementIn ctx n = Nothing -> definitionAddress ctx n = Nothing
unplacedUnaddressed none = cong (map addressOf) none

||| The address of the entry a name the frozen context defines is at, the
||| one `definitionIn` found: the entry is at a non-negative index
||| (`Host.resolvedPlaced`), placed as it is (`Walk.placementAt`), so the
||| name is not resolved again and no case is left for an entry without an
||| address.
export
definedAddress : (i : Int) -> (0 _ : Resolves ctx n i) -> (0 _ : Defines ctx n d) -> Address
definedAddress i resolved defines = addressOf (placementAt i (resolvedPlaced resolved defines))

||| The index of the context an address is (`Walk.addressOf`'s inverse): the
||| index whose eight bytes, the low byte first, it is.
export
addressIndex : Address -> Int
addressIndex a = cast (bytes a)
  where
    bytes : Vect k (Fin 256) -> Integer
    bytes [] = 0
    bytes (b :: bs) = cast (finToNat b) + 256 * bytes bs
