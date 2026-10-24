-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Data.List.Thin

import Libraries.Data.NatSet

%default total

-- TODO implement:
-- Guillaume Allais: Builtin Types Viewed as Inductive Families
-- https://doi.org/10.48550/arXiv.2301.02194
public export
data Thin : List a -> List a -> Type where
  Refl : Thin xs xs
  Drop : Thin xs ys -> Thin xs (y :: ys)
  Keep : Thin xs ys -> Thin (x :: xs) (x :: ys)

export
none : {xs : List a} -> Thin [] xs
none {xs = []} = Refl
none {xs = _ :: _} = Drop none

||| Smart constructor. We should use this to maximise the length
||| of the Refl segment thus getting more short-circuiting behaviours
export
keep : Thin xs ys -> Thin (x :: xs) (x :: ys)
keep Refl = Refl
keep p = Keep p

export
keeps : (args : List a) -> Thin xs ys -> Thin (args ++ xs) (args ++ ys)
keeps [] th = th
keeps (x :: xs) th = Keep (keeps xs th)

||| One thinning after another.
export
chain : Thin xs ys -> Thin ys zs -> Thin xs zs
chain p Refl = p
chain p (Drop q) = Drop (chain p q)
chain Refl (Keep q) = Keep q
chain (Drop p) (Keep q) = Drop (chain p q)
chain (Keep p) (Keep q) = Keep (chain p q)

||| The least thinning that keeps what each of two keeps, and how each sits
||| in it.
export
keepBoth : {zs : List a} -> Thin xs zs -> Thin ys zs ->
           (us : List a ** (Thin us zs, Thin xs us, Thin ys us))
keepBoth Refl q = (zs ** (Refl, Refl, q))
keepBoth p Refl = (zs ** (Refl, p, Refl))
keepBoth {zs = _ :: _} (Drop p) (Drop q)
    = let (us ** (u, l, r)) = keepBoth p q in (us ** (Drop u, l, r))
keepBoth {zs = z :: _} (Drop p) (Keep q)
    = let (us ** (u, l, r)) = keepBoth p q in (z :: us ** (Keep u, Drop l, Keep r))
keepBoth {zs = z :: _} (Keep p) (Drop q)
    = let (us ** (u, l, r)) = keepBoth p q in (z :: us ** (Keep u, Keep l, Drop r))
keepBoth {zs = z :: _} (Keep p) (Keep q)
    = let (us ** (u, l, r)) = keepBoth p q in (z :: us ** (Keep u, Keep l, Keep r))
