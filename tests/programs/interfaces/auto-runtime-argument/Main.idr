module Main

-- Only a value of an interface's type is an implementation, a compile-time
-- value. An auto-implicit argument of any other type is an ordinary
-- argument, which the program may choose at runtime: a context record, as
-- the fork of Idris's compiler passes `{auto c : Ref Ctxt Defs}` along,
-- and a type that asks for the unique search an interface's record has.

import Prelude

record Config where
  constructor MkConfig
  greeting : String
  times : Int

greet : {auto c : Config} -> String -> String
greet name = c.greeting ++ ", " ++ name

-- The where function gets the context as an explicit argument.
repeat : {auto c : Config} -> String -> String
repeat s = go c.times
  where
    go : Int -> String
    go n = if n <= 0 then "" else s ++ go (n - 1)

data Width : Type where
  [uniqueSearch]
  MkWidth : Int -> Width

pad : {auto w : Width} -> String -> String
pad {w = MkWidth n} s = if n <= 0 then s else pad {w = MkWidth (n - 1)} (s ++ ".")

main : IO ()
main = do
  line <- getLine
  let n = the Int (cast line)
  let c = MkConfig (if n > 2 then "Hello" else "Hi") n
  putStrLn (greet "world")
  putStrLn (repeat "ab")
  let w = MkWidth (n * 2)
  putStrLn (pad "x")
