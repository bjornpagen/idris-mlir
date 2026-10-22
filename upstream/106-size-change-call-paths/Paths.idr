module Paths

-- A hub and twenty-two spokes, mutually recursive on a Nat that shrinks
-- through every cycle: total, and the size-change closure has few graphs,
-- but each composed graph's call path is its parts' appended.
%default total
mutual
  hub : Nat -> Nat
  hub m = spoke0 m + spoke1 m + spoke2 m + spoke3 m + spoke4 m + spoke5 m + spoke6 m + spoke7 m + spoke8 m + spoke9 m + spoke10 m + spoke11 m + spoke12 m + spoke13 m + spoke14 m + spoke15 m + spoke16 m + spoke17 m + spoke18 m + spoke19 m + spoke20 m + spoke21 m + spoke22 m
  spoke0 : Nat -> Nat
  spoke0 Z = 0
  spoke0 (S m) = hub m
  spoke1 : Nat -> Nat
  spoke1 Z = 1
  spoke1 (S m) = back1 m
  spoke2 : Nat -> Nat
  spoke2 Z = 2
  spoke2 (S m) = back2 m
  spoke3 : Nat -> Nat
  spoke3 Z = 3
  spoke3 (S m) = back3 m
  spoke4 : Nat -> Nat
  spoke4 Z = 4
  spoke4 (S m) = back4 m
  spoke5 : Nat -> Nat
  spoke5 Z = 5
  spoke5 (S m) = back5 m
  spoke6 : Nat -> Nat
  spoke6 Z = 6
  spoke6 (S m) = back6 m
  spoke7 : Nat -> Nat
  spoke7 Z = 7
  spoke7 (S m) = back7 m
  spoke8 : Nat -> Nat
  spoke8 Z = 8
  spoke8 (S m) = back8 m
  spoke9 : Nat -> Nat
  spoke9 Z = 9
  spoke9 (S m) = back9 m
  spoke10 : Nat -> Nat
  spoke10 Z = 10
  spoke10 (S m) = back10 m
  spoke11 : Nat -> Nat
  spoke11 Z = 11
  spoke11 (S m) = back11 m
  spoke12 : Nat -> Nat
  spoke12 Z = 12
  spoke12 (S m) = back12 m
  spoke13 : Nat -> Nat
  spoke13 Z = 13
  spoke13 (S m) = back13 m
  spoke14 : Nat -> Nat
  spoke14 Z = 14
  spoke14 (S m) = back14 m
  spoke15 : Nat -> Nat
  spoke15 Z = 15
  spoke15 (S m) = back15 m
  spoke16 : Nat -> Nat
  spoke16 Z = 16
  spoke16 (S m) = back16 m
  spoke17 : Nat -> Nat
  spoke17 Z = 17
  spoke17 (S m) = back17 m
  spoke18 : Nat -> Nat
  spoke18 Z = 18
  spoke18 (S m) = back18 m
  spoke19 : Nat -> Nat
  spoke19 Z = 19
  spoke19 (S m) = back19 m
  spoke20 : Nat -> Nat
  spoke20 Z = 20
  spoke20 (S m) = back20 m
  spoke21 : Nat -> Nat
  spoke21 Z = 21
  spoke21 (S m) = back21 m
  spoke22 : Nat -> Nat
  spoke22 Z = 22
  spoke22 (S m) = back22 m
  back1 : Nat -> Nat
  back1 m = spoke0 m
  back2 : Nat -> Nat
  back2 m = spoke0 m
  back3 : Nat -> Nat
  back3 m = spoke0 m
  back4 : Nat -> Nat
  back4 m = spoke0 m
  back5 : Nat -> Nat
  back5 m = spoke0 m
  back6 : Nat -> Nat
  back6 m = spoke0 m
  back7 : Nat -> Nat
  back7 m = spoke0 m
  back8 : Nat -> Nat
  back8 m = spoke0 m
  back9 : Nat -> Nat
  back9 m = spoke0 m
  back10 : Nat -> Nat
  back10 m = spoke0 m
  back11 : Nat -> Nat
  back11 m = spoke0 m
  back12 : Nat -> Nat
  back12 m = spoke0 m
  back13 : Nat -> Nat
  back13 m = spoke0 m
  back14 : Nat -> Nat
  back14 m = spoke0 m
  back15 : Nat -> Nat
  back15 m = spoke0 m
  back16 : Nat -> Nat
  back16 m = spoke0 m
  back17 : Nat -> Nat
  back17 m = spoke0 m
  back18 : Nat -> Nat
  back18 m = spoke0 m
  back19 : Nat -> Nat
  back19 m = spoke0 m
  back20 : Nat -> Nat
  back20 m = spoke0 m
  back21 : Nat -> Nat
  back21 m = spoke0 m
  back22 : Nat -> Nat
  back22 m = spoke0 m
