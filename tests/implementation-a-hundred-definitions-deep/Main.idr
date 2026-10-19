module Main

-- An implementation the program names through a chain of definitions,
-- each the one before it, the last the named implementation.
-- Which implementation a method call takes is decided at compile time, so
-- the chain is reduced there to the implementation's constructor: each
-- step unfolds a definition not yet on the path it is reducing, which
-- terminates however long the chain is, and no count of steps refuses the
-- program. The run script writes the chain where the line `-- CHAIN` is,
-- a hundred deep and a thousand, past the 64 steps a count once allowed,
-- and names its last step where main names step100.

import Prelude

data Colour = Red | Green

[named] Show Colour where
  show Red = "red"
  show Green = "green"

step0 : Show Colour
step0 = named

-- CHAIN

main : IO ()
main = do
  c <- getChar
  putStrLn (show @{step100} (if c == 'g' then Green else Red))
