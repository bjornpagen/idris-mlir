module Main

import Control.Monad.State

-- StateT over StateT: the outer transformer's map, bind and pure call the
-- inner one's at the pair the outer state adds, through the dictionary
-- the outer one was given, and its Applicative's Functor parent is built
-- from its constraint's parent's parent. Each turn reads a strictly
-- smaller dictionary, which the two levels written here bound, so the
-- program compiles and runs.
tick : StateT Int (State Int) Int
tick = do
  a <- get
  b <- lift get
  put (a + 1)
  lift (put (b + 10))
  pure (a + b)

main : IO ()
main = printLn (evalState 100 (evalStateT 1 (map (* 2) (tick >>= \x => map (+ x) tick))))
