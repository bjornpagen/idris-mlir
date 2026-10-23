module CaseBlock

-- upstream/110-coverage-erased-index-first/CaseBlock.idr, importing the
-- Prelude, as every module of a program does.

import Prelude

%default total

data Why = Placeholder | Impossible | Dotted Nat

data Tm = Var Nat | Er Nat Why | App Tm Tm | Lam Tm

data Undotted : Why -> Type where
  IsPlaceholder : Undotted Placeholder
  IsImpossible : Undotted Impossible

data ErasedReduces : Why -> Why -> Type where
  APlaceholder : ErasedReduces Placeholder Placeholder
  AnImpossible : ErasedReduces Impossible Impossible
  ADotted : ErasedReduces (Dotted n) (Dotted n)

data Reduces : Tm -> Tm -> Type where
  Then : Reduces t u -> Reduces u v -> Reduces t v
  AVar : Reduces (Var i) (Var i)
  AnErased : ErasedReduces w w' -> Reduces (Er fc w) (Er fc' w')
  AnApp : Reduces f f' -> Reduces a a' -> Reduces (App f a) (App f' a')
  ALam : Reduces b b' -> Reduces (Lam b) (Lam b')

-- Covering: the case block's scrutinee, a reduction's result proved to
-- be `Er`, fixes the intermediate term, which its environment binds first.
0 erasedReduces : Undotted why -> Reduces (Er fc why) v -> (fc' : Nat ** v = Er fc' why)
erasedReduces u (Then r r') = case erasedReduces u r of
  (_ ** Refl) => erasedReduces u r'
erasedReduces IsPlaceholder (AnErased APlaceholder) = (_ ** Refl)
erasedReduces IsImpossible (AnErased AnImpossible) = (_ ** Refl)
