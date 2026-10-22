module Retry
%default total
export infixr 1 :&
data Got : Type -> Type -> Type where
  (:&) : (1 r : res) -> (x : a) -> Got res a
interface Machine (0 v : Type -> Type) (0 b : Type -> Type) (0 m : Type -> Type) | m where
  bind1 : (1 _ : m a) -> (1 _ : (1 _ : a) -> m c) -> m c
  pure1 : (1 _ : a) -> m a
  load  : (1 _ : b e) -> m (Got (b e) (v e))
namespace L
  export
  (>>=) : Machine v b m => (1 _ : m a) -> (1 _ : (1 _ : a) -> m c) -> m c
  (>>=) = bind1
f : Machine v b m => (1 src : b Nat) -> m (Got (b Nat) (v Nat))
f src = L.do
  (src :& b) <- load src
  (src :& x1) <- load src
  (src :& x2) <- load src
  (src :& x3) <- load src
  (src :& x4) <- load src
  (src :& x5) <- load src
  (src :& x6) <- load src
  (src :& x7) <- load src
  (src :& x8) <- load src
  (src :& x9) <- load src
  (src :& x10) <- load src
  (src :& x11) <- load src
  pure1 (the (Got (b Nat) (v Nat)) (src :& b))
