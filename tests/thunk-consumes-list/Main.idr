module Main

-- A suspension that consumes a list of a million cells, passed down a loop
-- whose length is read at run time, so that its force does not meet it
-- where it is made. Forcing it moves the list out of the suspension's
-- cell to the walk that adds one to each element, which rebuilds the list
-- in its own cells: no second list is live beside the first at any time.

import Prelude

build : Int -> List Int -> List Int
build 0 acc = acc
build n acc = build (n - 1) (n :: acc)

-- Each element plus one, onto the accumulator: every cell taken apart is
-- the cell built.
bumpOnto : List Int -> List Int -> List Int
bumpOnto [] acc = acc
bumpOnto (x :: xs) acc = bumpOnto xs ((x + 1) :: acc)

sumOnto : List Int -> Int -> Int
sumOnto [] acc = acc
sumOnto (x :: xs) acc = sumOnto xs (acc + x)

after : Int -> Lazy (List Int) -> Int
after 0 later = sumOnto (force later) 0
after k later = after (k - 1) later

main : IO ()
main = do
  c <- getChar
  let k : Int = cast (ord c - ord '0')
  let xs = build (1000000 + k) []
  printLn (after k (Delay (bumpOnto xs [])))
