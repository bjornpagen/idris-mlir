-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| LLVM's time trace of a compilation of idris-mlir (`--time-trace`),
||| read for how many times each zone ran.
|||
||| A trace is Chrome trace JSON: `traceEvents`, each event with its phase
||| `ph` and its `name`. A `Total <name>` event sums an entry's runs.
module Trace

import Data.Maybe
import Data.SortedMap
import Data.String
import System

import Files
import Json

%default covering

||| An event of the trace, as far as a count reads it.
record Event where
  constructor MkEvent
  phase : String
  name : String

text : JSON -> Maybe String
text (JString s) = Just s
text _ = Nothing

eventOf : JSON -> Maybe Event
eventOf e = do
  phase <- field "ph" e >>= text
  name <- field "name" e >>= text
  pure (MkEvent phase name)

eventsOf : (path : String) -> IO (List Event)
eventsOf path = do
  contents <- readOrDie path
  let Right json = parse contents
    | Left why => die (path ++ ": " ++ why)
  case field "traceEvents" json of
    Just (JArray events) => pure (mapMaybe eventOf events)
    _ => die (path ++ ": no traceEvents")

add : String -> Integer -> SortedMap String Integer -> SortedMap String Integer
add k v m = insert k (v + fromMaybe 0 (lookup k m)) m

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
