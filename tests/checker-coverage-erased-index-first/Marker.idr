module Marker

-- upstream/110-coverage-erased-index-first/Marker.idr, importing the
-- Prelude, as every module of a program does.

import Prelude

%default total

data Tm = Loc Nat | Nm Bool String | App Tm Tm | Hole | Prim Int | Ty | Susp Tm

-- A term and its image under a substitution: a marker, `Nm True s`,
-- stands for any term at all.
data Mapped : Tm -> Tm -> Type where
  MLoc : Mapped (Loc n) (Loc m)
  MMarker : Mapped (Nm True s) t'
  MNm : Mapped (Nm b s) (Nm b s)
  MApp : Mapped f f' -> Mapped a a' -> Mapped (App f a) (App f' a')
  MHole : Mapped Hole Hole
  MPrim : Mapped (Prim i) (Prim i)
  MTy : Mapped Ty Ty
  MSusp : Mapped t t' -> Mapped (Susp t) (Susp t')

-- A head that drops the arguments it is applied to.
data Drops : Tm -> Type where
  DHole : Drops Hole
  DPrim : Drops (Prim i)
  DTy : Drops Ty
  DSusp : Drops (Susp t)

-- Covering: an image that is neither Hole, Prim, Ty nor Susp comes from a
-- term of the same head or from a marker, and Drops holds of neither.
0 mappedDrops : Mapped f f' -> Drops f -> Drops f'
mappedDrops MHole DHole = DHole
mappedDrops MPrim DPrim = DPrim
mappedDrops MTy DTy = DTy
mappedDrops (MSusp _) DSusp = DSusp
