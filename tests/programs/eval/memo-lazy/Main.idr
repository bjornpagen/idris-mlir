module Main

import Prelude

-- The shape of upstream allschemes/memo002: a Lazy Nat made by adding the
-- previous constant to itself ten times, twenty deep. Forcing the last is
-- two hundred additions when each constant is forced once.

l0 : Lazy Nat
l0 = 1

l1 : Lazy Nat
l1 = l0 + l0 + l0 + l0 + l0 + l0 + l0 + l0 + l0 + l0

l2 : Lazy Nat
l2 = l1 + l1 + l1 + l1 + l1 + l1 + l1 + l1 + l1 + l1

l3 : Lazy Nat
l3 = l2 + l2 + l2 + l2 + l2 + l2 + l2 + l2 + l2 + l2

l4 : Lazy Nat
l4 = l3 + l3 + l3 + l3 + l3 + l3 + l3 + l3 + l3 + l3

l5 : Lazy Nat
l5 = l4 + l4 + l4 + l4 + l4 + l4 + l4 + l4 + l4 + l4

l6 : Lazy Nat
l6 = l5 + l5 + l5 + l5 + l5 + l5 + l5 + l5 + l5 + l5

l7 : Lazy Nat
l7 = l6 + l6 + l6 + l6 + l6 + l6 + l6 + l6 + l6 + l6

l8 : Lazy Nat
l8 = l7 + l7 + l7 + l7 + l7 + l7 + l7 + l7 + l7 + l7

l9 : Lazy Nat
l9 = l8 + l8 + l8 + l8 + l8 + l8 + l8 + l8 + l8 + l8

l10 : Lazy Nat
l10 = l9 + l9 + l9 + l9 + l9 + l9 + l9 + l9 + l9 + l9

l11 : Lazy Nat
l11 = l10 + l10 + l10 + l10 + l10 + l10 + l10 + l10 + l10 + l10

l12 : Lazy Nat
l12 = l11 + l11 + l11 + l11 + l11 + l11 + l11 + l11 + l11 + l11

l13 : Lazy Nat
l13 = l12 + l12 + l12 + l12 + l12 + l12 + l12 + l12 + l12 + l12

l14 : Lazy Nat
l14 = l13 + l13 + l13 + l13 + l13 + l13 + l13 + l13 + l13 + l13

l15 : Lazy Nat
l15 = l14 + l14 + l14 + l14 + l14 + l14 + l14 + l14 + l14 + l14

l16 : Lazy Nat
l16 = l15 + l15 + l15 + l15 + l15 + l15 + l15 + l15 + l15 + l15

l17 : Lazy Nat
l17 = l16 + l16 + l16 + l16 + l16 + l16 + l16 + l16 + l16 + l16

l18 : Lazy Nat
l18 = l17 + l17 + l17 + l17 + l17 + l17 + l17 + l17 + l17 + l17

l19 : Lazy Nat
l19 = l18 + l18 + l18 + l18 + l18 + l18 + l18 + l18 + l18 + l18

l20 : Lazy Nat
l20 = l19 + l19 + l19 + l19 + l19 + l19 + l19 + l19 + l19 + l19

main : IO ()
main = printLn (the Nat (force l20 + force l20))
