module _ where

open import Data.List
open import Data.Empty
open import Relation.Nullary
open import Relation.Binary
open import Relation.Binary.PropositionalEquality as P

module _ {ℓ} {A : Set} {_≤_ : Rel A ℓ}
         {isDecPartialOrder : IsDecPartialOrder _≡_ _≤_} where

  open IsDecPartialOrder isDecPartialOrder

  swap : List A → List A
  swap [] = []
  swap (x₁ ∷ []) = x₁ ∷ []
  swap (x₁ ∷ x₂ ∷ xs) with x₁ ≤? x₂
  ... | yes p = x₂ ∷ x₁ ∷ xs
  ... | no ¬p = x₁ ∷ x₂ ∷ xs

  swap_idemp : ∀ xs → swap (swap xs) ≡ swap xs
  swap_idemp [] = P.refl
  swap_idemp (x₁ ∷ []) = P.refl
  swap_idemp (x₁ ∷ x₂ ∷ xs) with x₁ ≤? x₂
  swap_idemp (x₁ ∷ x₂ ∷ xs) | yes p with x₂ ≤? x₁
  ... | yes q rewrite antisym p q = P.refl
  ... | no ¬q = P.refl
  swap_idemp (x₁ ∷ x₂ ∷ xs) | no ¬p with x₁ ≤? x₂
  ... | yes q = ⊥-elim (¬p q)
  ... | no ¬q = P.refl
