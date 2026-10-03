module Main

-- A loop decided by a string literal, which goes round again passing one
-- value as two arguments and ends returning its string unchanged: the loop
-- whose condition forwards one result of the decision twice
-- (upstream/while-move-if-down-duplicates). The second argument decides
-- what the next string is, so a wrong value there changes the output.

import Prelude

step : String -> Int -> Int -> String
step s a b = case s of
  "go" => step (if b < 5 then "go" else show (a * 10 + b)) (a + 1) (a + 1)
  _ => s

main : IO ()
main = do
  line <- getLine
  putStrLn (step line 0 0)
  putStrLn (step "stay" 0 0)
