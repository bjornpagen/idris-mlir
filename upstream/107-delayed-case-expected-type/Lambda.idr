module Lambda

-- A pattern-matching lambda checked at a Lazy function type: maybe's
-- second argument is Lazy (a -> b). Upstream issue #3418. Stock Idris at
-- 89ba32eb rejects every one of these: "Can't solve constraint between:
-- String and ?caseTy".

first : Maybe (Nat, String) -> String
first x = maybe "" (\(n, m) => m ++ show n) x

second : Maybe (String, String) -> String
second x = maybe "" (\(n, m) => m) x

bar : Lazy (() -> ())
bar = \x => case x of () => ()

main : IO ()
main = do
  putStrLn (first (Just (7, "n=")))
  putStrLn (second (Just ("a", "b")))
