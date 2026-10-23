-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The exponent of the constant part of one computation's growth
||| (`Proof.Requests.grown`), held behind its name.
|||
||| The type checker computes naturals in unary, so a type that held 2^1024
||| would have it build that number wherever the type is normalised or
||| compared. Exported by name alone, the exponent unfolds nowhere outside
||| this module, so `power 2 widestExponent` is stuck in every type there,
||| and what the proofs need of it, that it is at least each exponent a
||| primitive's bound names, is stated here, where it is the small number
||| it is. A program computes it as any other number.
|||
||| Every proof is erased and total.
module IdrisMLIR.Proof.Widest

import Data.Nat

%default total

||| 1024: the exponent of a cast to Integer's bound on a character's code
||| and a finite double's integer part, the largest constant exponent a
||| primitive's bound names (`Idris.Host.boundOf`).
export
widestExponent : Nat
widestExponent = 1024

||| Every exponent up to 1024 is at most the widest: a fixed width's 64, a
||| double's text's 49, a cast's own 1024.
export
0 withinWidest : (e : Nat) -> LTE e 1024 -> LTE e widestExponent
withinWidest e le = le
