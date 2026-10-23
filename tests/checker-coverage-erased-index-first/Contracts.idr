module Contracts

-- upstream/110-coverage-erased-index-first/Contracts.idr, importing the
-- Prelude, as every module of a program does.

import Prelude

%default total

data Tm = Var Nat | Mark String | Lam Tm | Let Tm Tm | App Tm Tm
        | Susp Tm | Frc Tm | Asp Tm Tm | Hole | Prim Int | Ty

-- A term and its image under a substitution: a marker stands for any term.
data Mapped : Tm -> Tm -> Type where
  MVar : Mapped (Var i) (Var j)
  MMark : Mapped (Mark s) t'
  MLam : Mapped b b' -> Mapped (Lam b) (Lam b')
  MLet : Mapped v v' -> Mapped b b' -> Mapped (Let v b) (Let v' b')
  MApp : Mapped f f' -> Mapped a a' -> Mapped (App f a) (App f' a')
  MSusp : Mapped t t' -> Mapped (Susp t) (Susp t')
  MFrc : Mapped t t' -> Mapped (Frc t) (Frc t')
  MAsp : Mapped a a' -> Mapped t t' -> Mapped (Asp a t) (Asp a' t')
  MHole : Mapped Hole Hole
  MPrim : Mapped (Prim k) (Prim k)
  MTy : Mapped Ty Ty

-- One contraction step.
data Contracts : Tm -> Tm -> Type where
  Beta : Contracts (App (Lam b) a) b
  Zeta : Contracts (Let v b) b
  FrcSusp : Contracts (Frc (Susp t)) t
  RemoveAsp : Contracts (Asp a t) t
  FloatAsp : Contracts (App (Asp a t) x) (Asp (App a x) (App t x))
  FloatLet : Contracts (App (Let v b) x) (Let v (App b x))
  FloatSusp : Contracts (App (Susp t) x) (Susp (App t x))
  DropHole : Contracts (App Hole x) Hole
  DropPrim : Contracts (App (Prim k) x) (Prim k)
  DropTy : Contracts (App Ty x) Ty

0 mappedContracts : Mapped t t' -> Contracts t u -> (u' ** (Mapped u u', Contracts t' u'))
mappedContracts (MApp (MLam mb) ma) Beta = (_ ** (mb, Beta))
mappedContracts (MLet _ mb) Zeta = (_ ** (mb, Zeta))
mappedContracts (MFrc (MSusp mt)) FrcSusp = (_ ** (mt, FrcSusp))
mappedContracts (MAsp _ mt) RemoveAsp = (_ ** (mt, RemoveAsp))
mappedContracts (MApp (MAsp ma mt) mx) FloatAsp = (_ ** (MAsp (MApp ma mx) (MApp mt mx), FloatAsp))
mappedContracts (MApp (MLet mv mb) mx) FloatLet = (_ ** (MLet mv (MApp mb mx), FloatLet))
mappedContracts (MApp (MSusp mt) mx) FloatSusp = (_ ** (MSusp (MApp mt mx), FloatSusp))
mappedContracts (MApp MHole _) DropHole = (_ ** (MHole, DropHole))
mappedContracts (MApp MPrim _) DropPrim = (_ ** (MPrim, DropPrim))
mappedContracts (MApp MTy _) DropTy = (_ ** (MTy, DropTy))
