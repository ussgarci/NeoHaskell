{-# OPTIONS_GHC -F -pgmF hspec-discover #-}

import Core
import Test.DocTest


main :: IO ()
main =
  doctest
    [ "-isrc",
      "core/Array.hs"
    ]
