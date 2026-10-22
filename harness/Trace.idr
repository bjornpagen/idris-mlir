-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| LLVM's time traces summed: what a compilation of idris-mlir
||| (`--time-trace`) and a compilation of our C++
||| (clang's `-ftime-trace`) spent their time in, the baseline every
||| measurement of a change is taken against.
|||
|||     runtests --trace-totals <trace>         the twenty `Total` entries
|||                                             most time went to
|||     runtests --trace-units <trace>...       clang's traces of the units
|||                                             of a build, summed
|||
||| A trace is Chrome trace JSON: `traceEvents`, each event with its phase
||| `ph`, its `name`, its duration `dur` in microseconds, and its `args`. A
||| `Total <name>` event sums an entry's runs, `args.count` of them. Times
||| are integers of microseconds and are printed as milliseconds by integer
||| arithmetic, so both hosts print the same text.
module Trace

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.String
import System

import Files
import Json

%default covering

||| An event of the trace, as far as a sum reads it.
record Event where
  constructor MkEvent
  phase : String
  name : String
  micros : Integer
  count : Maybe Integer
  detail : Maybe String

text : JSON -> Maybe String
text (JString s) = Just s
text _ = Nothing

eventOf : JSON -> Maybe Event
eventOf e = do
  phase <- field "ph" e >>= text
  name <- field "name" e >>= text
  let micros = fromMaybe 0 (field "dur" e >>= integer)
  let args = field "args" e
  pure (MkEvent phase name micros (args >>= field "count" >>= integer) (args >>= field "detail" >>= text))

eventsOf : (path : String) -> IO (List Event)
eventsOf path = do
  contents <- readOrDie path
  let Right json = parse contents
    | Left why => die (path ++ ": " ++ why)
  case field "traceEvents" json of
    Just (JArray events) => pure (mapMaybe eventOf events)
    _ => die (path ++ ": no traceEvents")

||| Microseconds as milliseconds with two decimals.
millis : Integer -> String
millis us =
  let hundredths = us `div` 10
      whole = hundredths `div` 100
      part = hundredths `mod` 100
  in show whole ++ "." ++ (if part < 10 then "0" else "") ++ show part ++ " ms"

||| The `Total <name>` events, most time first, ties by name.
totals : List Event -> List Event
totals = sortBy (\a, b => compare (negate a.micros, a.name) (negate b.micros, b.name))
       . filter (\e => e.phase == "X" && isPrefixOf "Total " e.name)

||| `--trace-totals <trace>`.
export
traceTotals : String -> IO ()
traceTotals path = do
  events <- eventsOf path
  putStrLn "top entries by total time:"
  for_ (take 20 (totals events)) $ \e =>
    putStrLn ("  " ++ pack (drop 6 (unpack e.name)) ++ "  " ++ millis e.micros
              ++ "  x" ++ maybe "?" show e.count)

||| What a unit's trace is summed into: its totals by name, and its
||| instantiations' time by template.
record Sums where
  constructor MkSums
  byTotal : SortedMap String Integer
  byTemplate : SortedMap String Integer

add : String -> Integer -> SortedMap String Integer -> SortedMap String Integer
add k v m = insert k (v + fromMaybe 0 (lookup k m)) m

instantiation : String -> Bool
instantiation n = n == "InstantiateFunction" || n == "InstantiateClass"

sumEvent : Sums -> Event -> Sums
sumEvent s e =
  if e.phase /= "X" then s
  else if isPrefixOf "Total " e.name then { byTotal $= add (pack (drop 6 (unpack e.name))) e.micros } s
  else if instantiation e.name then { byTemplate $= add (fromMaybe "?" e.detail) e.micros } s
  else s

mostFirst : SortedMap String Integer -> List (String, Integer)
mostFirst m = sortBy (\(a, x), (b, y) => compare (negate x, a) (negate y, b)) (toList m)

||| `--trace-units <trace>...`: every unit's totals summed across the
||| units, then the twenty templates whose instantiation took longest.
export
traceUnits : List String -> IO ()
traceUnits paths = do
  sums <- foldlM (\s, p => foldl sumEvent s <$> eventsOf p) (MkSums empty empty) paths
  putStrLn ("units: " ++ show (length paths))
  for_ (mostFirst sums.byTotal) $ \(n, us) => putStrLn ("  " ++ n ++ "  " ++ millis us)
  putStrLn "templates by instantiation time:"
  for_ (take 20 (mostFirst sums.byTemplate)) $ \(n, us) => putStrLn ("  " ++ n ++ "  " ++ millis us)

||| How many times each zone of a compilation's trace ran, by its name: a
||| pass on an op, an analysis computed, a solve unit, each a count of the
||| compiler's work and never a time; the `Total` sums aside, which count
||| nothing a zone does not.
export
zoneCounts : (path : String) -> IO (SortedMap String Integer)
zoneCounts path = foldl ranOnce empty <$> eventsOf path
  where
    ranOnce : SortedMap String Integer -> Event -> SortedMap String Integer
    ranOnce m e = if e.phase == "X" && not (isPrefixOf "Total " e.name) then add e.name 1 m else m
