-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- meteor-contest (the Benchmarks Game, retired): every way to fill the
-- 50-cell hexagonal board with the ten pieces, counted up to the limit read
-- from stdin, and the smallest and largest solution, read as 50 digits in
-- cell order, printed as the game's pretty board.
--
-- A cell is row * 5 + column; odd rows sit half a cell to the right. A
-- piece is the path from one of its cells through the other four, in the
-- twelve directions of the game's C entry (even ones to a neighbour, odd
-- ones to the cell two steps away between two neighbours). Its placements
-- are every start cell under every rotation (direction + 2) and flip
-- (12 - direction), each a 50-bit mask, kept under its lowest cell. No
-- piece has a symmetry, so no two of a piece's placements are alike, and a
-- solution is found once. The search fills the lowest empty cell, found by
-- stepping on from the last one filled, with each unused piece placed
-- there, in the order of the pieces and then of the placements, and
-- backtracks.

import Prelude
import Data.Bits
import Data.List

pieces : List (List Int)
pieces =
  [ [0, 0, 0, 2], [2, 0, 10, 0], [0, 0, 2, 4], [0, 0, 4, 2], [2, 0, 10, 3]
  , [0, 0, 4, 0], [0, 2, 2, 10], [0, 2, 2, 6], [0, 2, 0, 0], [0, 0, 0, 4] ]

-- The twelve directions as steps of axial coordinates (q, r), where a cell
-- in row r and column c has q = c - r / 2.
dq : Int -> Int
dq d = case d of
  0 => 1; 1 => 1; 2 => 0; 3 => -1; 4 => -1; 5 => -2
  6 => -1; 7 => -1; 8 => 0; 9 => 1; 10 => 1; _ => 2

dr : Int -> Int
dr d = case d of
  0 => 0; 1 => 1; 2 => 1; 3 => 2; 4 => 1; 5 => 1
  6 => 0; 7 => -1; 8 => -1; 9 => -2; 10 => -1; _ => -1

-- The bit of cell (or piece) i.
bitOf : Int -> Bits64
bitOf i = if i <= 0 then 1 else shiftL (bitOf (i - 1)) 1

full : Bits64
full = bitOf 50 - 1

-- A placement: its piece, the piece's bit among the used ones, and the
-- cells it covers.
data Place = MkPlace Int Bits64 Bits64

-- The cells the rest of a path visits from (q, r), in an orientation, or
-- nothing when one of them is off the board.
walk : Bool -> Int -> Int -> Int -> List Int -> Maybe (List Int)
walk flipped orient q r [] = Just []
walk flipped orient q r (d :: ds) =
  let mirrored : Int = if flipped then (12 - d) `mod` 12 else d
      d' = (mirrored + 2 * orient) `mod` 12
      q' = q + dq d'
      r' = r + dr d'
      c = q' + r' `div` 2
  in if r' < 0 || r' >= 10 || c < 0 || c >= 5
        then Nothing
        else map ((r' * 5 + c) ::) (walk flipped orient q' r' ds)

-- Every placement with its lowest cell, in the order of the pieces, the
-- flips, the rotations and the start cells.
placements : List (Int, Place)
placements = byPiece 0 pieces
  where
    starts : Int -> List Int -> Bool -> Int -> Int -> List (Int, Place)
    starts p def flipped orient start =
      if start >= 50 then []
      else
        let rest = starts p def flipped orient (start + 1) in
        case walk flipped orient (start `mod` 5 - start `div` 10) (start `div` 5) def of
          Nothing => rest
          Just cells =>
            let covered = start :: cells in
            (foldl min start cells, MkPlace p (bitOf p) (foldl (\m, c => m .|. bitOf c) 0 covered)) :: rest

    orients : Int -> List Int -> Bool -> Int -> List (Int, Place)
    orients p def flipped orient =
      if orient >= 6 then [] else starts p def flipped orient 0 ++ orients p def flipped (orient + 1)

    byPiece : Int -> List (List Int) -> List (Int, Place)
    byPiece p [] = []
    byPiece p (def :: defs) = orients p def False 0 ++ orients p def True 0 ++ byPiece (p + 1) defs

-- The placements whose lowest cell is cell, in order.
at : Int -> List Place
at cell = go placements
  where
    go : List (Int, Place) -> List Place
    go [] = []
    go ((lo, pl) :: rest) = if lo == cell then pl :: go rest else go rest

-- One table per cell, from cell 0 on.
table : List (List Place)
table = go 0
  where
    go : Int -> List (List Place)
    go cell = if cell >= 50 then [] else at cell :: go (cell + 1)

-- A solution read as its 50 digits in cell order, ten to a word (two rows
-- of the board, as many as an Int holds), so that one key is before
-- another when its digits are.
data Key = MkKey Int Int Int Int Int

before : Key -> Key -> Bool
before (MkKey a0 a1 a2 a3 a4) (MkKey b0 b1 b2 b3 b4) =
  if a0 /= b0 then a0 < b0
  else if a1 /= b1 then a1 < b1
  else if a2 /= b2 then a2 < b2
  else if a3 /= b3 then a3 < b3
  else a4 < b4

-- The key of the chosen placements: the piece at every cell.
keyOf : List (Int, Bits64) -> Key
keyOf chosen = MkKey (word 0) (word 10) (word 20) (word 30) (word 40)
  where
    owner : Bits64 -> List (Int, Bits64) -> Int
    owner probe [] = 0
    owner probe ((p, m) :: rest) = if m .&. probe /= 0 then p else owner probe rest

    digits : Int -> Bits64 -> Int -> Int
    digits k probe acc = if k >= 10 then acc else digits (k + 1) (shiftL probe 1) (acc * 10 + owner probe chosen)

    word : Int -> Int
    word cell = digits 0 (bitOf cell) 0

-- The solutions so far: none yet, or how many, the smallest and the
-- largest.
data Found = None | Some Int Key Key

countOf : Found -> Int
countOf None = 0
countOf (Some n _ _) = n

note : List (Int, Bits64) -> Found -> Found
note chosen None = let k = keyOf chosen in Some 1 k k
note chosen (Some n best worst) =
  let k = keyOf chosen in
  Some (n + 1) (if before k best then k else best) (if before worst k then k else worst)

-- The search at the cell probe marks, whose table is here and the
-- following cells' are later: when the cell is filled, from the next one;
-- otherwise each placement of todo, the rest of here, while the limit is
-- not reached.
search : Int -> Bits64 -> Bits64 -> Bits64 -> List Place -> List (List Place) -> List Place -> List (Int, Bits64) -> Found -> Found
search limit board used probe here later todo chosen found =
  if board .&. probe /= 0
     then case later of
       [] => found
       next :: rest => search limit board used (shiftL probe 1) next rest next chosen found
     else case todo of
       [] => found
       MkPlace p b m :: more =>
         if countOf found >= limit then found
         else
           let board' = board .|. m
               chosen' = (p, m) :: chosen
               found' = if used .&. b /= 0 || board .&. m /= 0 then found
                        else if board' == full then note chosen' found
                        else search limit board' (used .|. b) probe here later here chosen' found in
           search limit board used probe here later more chosen found'

-- The board as the game prints it: odd rows indented by one, every digit
-- followed by a space, and a blank line after.
pretty : Key -> IO ()
pretty (MkKey w0 w1 w2 w3 w4) = do
  rows w0
  rows w1
  rows w2
  rows w3
  rows w4
  putStr "\n"
  where
    -- The ten digits of a word, the first one first.
    digits : Int -> Int -> List Char -> List Char
    digits k w acc = if k >= 10 then acc else digits (k + 1) (w `div` 10) (chr (ord '0' + w `mod` 10) :: acc)

    row : List Char -> String
    row ds = pack (concatMap (\d => [d, ' ']) ds) ++ "\n"

    rows : Int -> IO ()
    rows w = do
      let ds = digits 0 w []
      putStr (row (take 5 ds))
      putStr (" " ++ row (drop 5 ds))

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  limit <- readInt
  case table of
    [] => pure ()
    here :: later => case search limit 0 0 1 here later here [] None of
      None => putStr "0 solutions found\n\n"
      Some n best worst => do
        putStr (show n ++ " solutions found\n\n")
        pretty best
        pretty worst
