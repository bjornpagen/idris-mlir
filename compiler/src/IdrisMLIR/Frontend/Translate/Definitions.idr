-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A definition's identity, its address in the context, and the way back
||| from an address to the definition. They sit below everything that keys
||| or reads by address, the readings an instance is keyed by among them,
||| which the translation's state caches.
module IdrisMLIR.Frontend.Translate.Definitions

import Core.Context
import Core.Core

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

||| The index of the context an address is (`Walk.addressOf`'s inverse): the
||| index whose eight bytes, the low byte first, it is.
export
addressIndex : Address -> Int
addressIndex a = cast (bytes a)
  where
    bytes : Vect k (Fin 256) -> Integer
    bytes [] = 0
    bytes (b :: bs) = cast (finToNat b) + 256 * bytes bs

||| The name a definition's address stands for (`addressOf`'s inverse): the
||| context's entry at that index, for a message to print (`toFullNames`);
||| nothing for bytes no entry of the context has.
export
nameAt : Context -> Address -> Maybe Name
nameAt ctx a = let i = addressIndex a in
               if i < nextEntry ctx then Just (Resolved i) else Nothing

||| The definition at an address, as the context holds it; nothing at bytes
||| no entry of the context has. The one reading of a definition by its
||| address.
export
definitionAt : {auto c : Ref Ctxt Defs} -> Address -> Core (Maybe GlobalDef)
definitionAt a = do
  defs <- get Ctxt
  case nameAt (gamma defs) a of
    Just n => lookupCtxtExact n (gamma defs)
    Nothing => pure Nothing
