module Main

import Prelude

-- A table's entry holds a definition, and a constructor's definition holds
-- an optional pair, as Idris's own context does (`Maybe ContextEntry`,
-- whose definitions hold a `Maybe (Bool, Nat)`). Maybe is needed at Entry
-- and, inside Entry's fields, at (Bool, Nat): a larger type, written once
-- and never grown again, so its instances are those two.

data Def = Con Int (Maybe (Bool, Nat)) | Fun String

data Entry = Coded String | Decoded Def

describe : Maybe Entry -> String
describe Nothing = "none"
describe (Just (Coded s)) = "coded " ++ s
describe (Just (Decoded (Fun n))) = "function " ++ n
describe (Just (Decoded (Con t Nothing))) = "constructor " ++ show t
describe (Just (Decoded (Con t (Just (b, k))))) = "constructor " ++ show t ++ " " ++ show b ++ " " ++ show k

entryAt : Int -> Maybe Entry
entryAt 0 = Just (Decoded (Con 2 (Just (True, 1))))
entryAt 1 = Just (Decoded (Fun "main"))
entryAt 2 = Just (Coded "x")
entryAt _ = Nothing

main : IO ()
main = do
  putStrLn (describe (entryAt 0))
  putStrLn (describe (entryAt 1))
  putStrLn (describe (entryAt 2))
  putStrLn (describe (entryAt 3))
