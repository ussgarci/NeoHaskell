-- | Fast immutable arrays. The elements in an array must have the same type.
module Array (
  -- * Arrays
  Array,

  -- * Creation
  empty,
  initialize,
  repeat,
  wrap,
  fromLinkedList,

  -- * Query
  isEmpty,
  length,
  indices,
  get,
  maximum,
  minimum,

  -- * Manipulate
  set,
  push,
  append,
  slice,

  -- * LinkedLists
  toLinkedList,
  toIndexedLinkedList,

  -- * Transform
  map,
  indexedMap,
  reduce,
  foldl,
  takeIf,
  dropIf,
  flatMap,
  foldM,
  dropWhile,
  takeWhile,
  take,
  drop,
  indexed,

  -- * Partitioning?
  partitionBy,
  splitFirst,
  any,

  -- * Compatibility
  unwrap,
  fromLegacy,
  last,
  zip,
  sumIntegers,
  reverse,
  flatten,
) where

import Basics
import Collection (Collection (..))
import Control.Monad qualified
import Data.Foldable qualified
import Data.Vector ((!?), (++), (//))
import Data.Vector qualified
import Function qualified
import GHC.IsList qualified as GHC
import IO (IO)
import LinkedList (LinkedList)
import LinkedList qualified
import Maybe (Maybe (..))
import Test.QuickCheck qualified as QuickCheck
import Tuple qualified
import Prelude qualified


-- | Representation of fast immutable arrays. You can create arrays of integers
-- (@Array Int@) or strings (@Array String@) or any other type of value you can
-- dream up.
newtype Array a = Array (Data.Vector.Vector a)
  deriving (Prelude.Eq, Prelude.Show, Prelude.Ord, Generic)


instance Collection Array where
  lengthImpl = length
  emptyImpl = empty
  isEmptyImpl = isEmpty
  getImpl = get
  setImpl = set
  appendImpl = append
  firstImpl = first
  lastImpl = last
  indicesImpl = indices
  mapImpl = map
  repeatImpl = repeat
  wrapImpl = wrap
  fromLinkedListImpl = fromLinkedList
  pushImpl = push
  toLinkedListImpl = toLinkedList
  toIndexedLinkedListImpl = toIndexedLinkedList
  reduceImpl = reduce
  foldlImpl = foldl
  takeIfImpl = takeIf
  dropIfImpl = dropIf
  indexedMapImpl = indexedMap
  sliceImpl = slice
  flatMapImpl = flatMap
  foldMImpl = foldM
  dropWhileImpl = dropWhile
  takeWhileImpl = takeWhile
  partitionByImpl = partitionBy
  splitFirstImpl = splitFirst
  anyImpl = any
  fromLegacyImpl = fromLegacy
  takeImpl = take
  dropImpl = drop
  indexedImpl = indexed
  zipImpl = zip
  sumIntegersImpl = sumIntegers
  reverseImpl = reverse


instance (QuickCheck.Arbitrary a) => QuickCheck.Arbitrary (Array a) where
  arbitrary = do
    list <- QuickCheck.arbitrary
    pure (fromLinkedList list)


instance GHC.IsList (Array a) where
  type Item (Array a) = a
  fromList = Basics.fromList
  toList = toLinkedList


-- | Helper function to unwrap an array
unwrap :: Array a -> Data.Vector.Vector a
unwrap (Array v) = v


-- | Return an empty array.
--
-- >>> empty :: Array Int
-- Array []
empty :: Array a
empty = Array Data.Vector.empty


-- | Determine if an array is empty.
--
-- >>> isEmpty empty
-- True
-- >>> isEmpty (Array.fromLinkedList ['a'])
-- False
-- >>> isEmpty (Array.fromLinkedList ['a', 'b', 'c'])
-- False
isEmpty :: Array a -> Bool
isEmpty = unwrap .> Data.Vector.null


-- | Return the length of an array.
--
-- >>> length (Array (Data.Vector.fromList [1,2,3] :: Data.Vector.Vector Int))
-- 3
-- >>> length empty
-- 0
length :: Array a -> Int
length = unwrap .> Data.Vector.length


-- | The indices that are valid for subscripting the collection, in ascending order.
--
-- >>> indices (Array (Data.Vector.fromList [1,2,3] :: Data.Vector.Vector Int))
-- Array [0,1,2]
-- >>> indices empty
-- Array []
indices :: Array a -> Array Int
indices =
  unwrap
    .> \v ->
      Array (Data.Vector.generate (Data.Vector.length v) Function.unchanged)


-- | Initialize an array. @initialize n f@ creates an array of length @n@ with
-- the element at index @i@ initialized to the result of @(f i)@.
--
-- >>> initialize 4 identity
-- Array [0,1,2,3]
-- >>> initialize 4 (\n -> n*n)
-- Array [0,1,4,9]
-- >>> initialize 4 (always (0 :: Int))
-- Array [0,0,0,0]
initialize :: Int -> (Int -> a) -> Array a
initialize n f =
  Array
    <| Data.Vector.generate
      (Prelude.fromIntegral n)
      (Prelude.fromIntegral .> f)


-- | Creates an array with a given length, filled with a default element.
--
-- >>> repeat 5 (0 :: Int)
-- Array [0,0,0,0,0]
-- >>> repeat 0 (0 :: Int)
-- Array []

-- Notice that @repeat 3 x@ is the same as @initialize 3 (always x)@.
repeat :: Int -> a -> Array a
repeat n element =
  Array
    <| Data.Vector.replicate (Prelude.fromIntegral n) element


-- | Wraps an element into an array
-- >>> wrap (0 :: Int)
-- Array [0]
wrap :: a -> Array a
wrap element = fromLinkedList [element]


-- | Create an array from a 'LinkedList'.
fromLinkedList :: LinkedList a -> Array a
fromLinkedList =
  Data.Vector.fromList .> Array


-- | Return @Just@ the element at the index or @Nothing@ if the index is out of range.
--
-- >>> get 0 (fromLinkedList [0,1,2] :: Array Int)
-- Just 0
-- >>> get 2   (fromLinkedList [0,1,2] :: Array Int)
-- Just 2
-- >>> get 5   (fromLinkedList [0,1,2] :: Array Int)
-- Nothing
-- >>> get (-1) (fromLinkedList [0,1,2] :: Array Int)
-- Nothing
get :: Int -> Array a -> Maybe a
get i array = unwrap array !? Prelude.fromIntegral i


-- | Return @Just@ the first element or @Nothing@ if the index is empty.
--
-- >>> first (fromLinkedList [0,1,2] :: Array Int)
-- Just 0
-- >>> first (fromLinkedList [] :: Array Int)
-- Nothing
first :: Array a -> Maybe a
first = get 0


-- | Set the element at a particular index. Returns an updated array.
--
-- If the index is out of range, the array is unaltered.
--
-- >>> set 1 7 (fromLinkedList [1,2,3] :: Array Int)
-- Array [1,7,3]
-- >>> set 3 7 (fromLinkedList [1,2,3] :: Array Int)
-- Array [1,2,3]
set :: Int -> a -> Array a -> Array a
set i value array = Array result
 where
  len = length array
  vector = unwrap array
  result
    | 0 <= i && i < len = vector Data.Vector.// [(Prelude.fromIntegral i, value)]
    | otherwise = vector


-- | Push an element onto the end of an array.
--
-- >>> push 3 (fromLinkedList [1,2] :: Array Int)
-- Array [1,2,3]
push :: a -> Array a -> Array a
push a (Array vector) =
  Array (Data.Vector.snoc vector a)


-- | Create a list of elements from an array.
--
-- >>> toLinkedList (fromLinkedList [3,5,8] :: Array Int)
-- [3,5,8]
toLinkedList :: Array a -> LinkedList a
toLinkedList = unwrap .> Data.Vector.toList


-- | Create an indexed list from an array. Each element of the array will be
-- paired with its index.
--
-- >>> toIndexedLinkedList (fromLinkedList [6,7] :: Array Int)
-- [(0,6),(1,7)]
toIndexedLinkedList :: Array a -> LinkedList (Int, a)
toIndexedLinkedList =
  unwrap
    .> Data.Vector.indexed
    .> Data.Vector.toList
    .> LinkedList.map (Tuple.mapFirst Prelude.fromIntegral)


-- | Reduce an array from the right. Read @reduce@ as fold from the right.
--
-- >>> reduce (+) 0 (repeat 3 5 :: Array Int)
-- 15
reduce :: (a -> b -> b) -> b -> Array a -> b
reduce f value array = Prelude.foldr f value (unwrap array)


-- | Reduce an array from the left. Read @foldl@ as fold from the left.
--
-- >>> (fromLinkedList [1,2,3] :: Array Int) |> foldl (+) 0
-- 6
foldl :: (a -> b -> b) -> b -> Array a -> b
foldl f value array =
  Data.Foldable.foldl' (\a b -> f b a) value (unwrap array)


-- | Keep elements that pass the test.
--
-- >>> takeIf Basics.isEven (fromLinkedList [1,2,3,4,5,6] :: Array Int)
-- Array [2,4,6]
takeIf :: (a -> Bool) -> Array a -> Array a
takeIf f (Array vector) =
  Array (Data.Vector.filter f vector)


-- | Drop elements that pass the test.
--
-- >>> dropIf Basics.isEven (fromLinkedList [1,2,3,4,5,6] :: Array Int)
-- Array [1,3,5]
dropIf :: (a -> Bool) -> Array a -> Array a
dropIf f (Array vector) =
  Array (Data.Vector.filter (f .> not) vector)


-- | Apply a function on every element in an array.
--
-- >>> map sqrt (fromLinkedList [1,4,9] :: Array Float)
-- Array [1.0,2.0,3.0]
map :: (a -> b) -> Array a -> Array b
map f (Array vector) =
  Array (Data.Vector.map f vector)


-- | Apply a function on every element with its index as first argument.
--
-- >>> indexedMap (*) (fromLinkedList [5,5,5] :: Array Int)
-- Array [0,5,10]
indexedMap :: (Int -> a -> b) -> Array a -> Array b
indexedMap f (Array vector) =
  Array (Data.Vector.imap (Prelude.fromIntegral .> f) vector)


-- | Append two arrays to a new one.
--
-- >>> append (repeat 2 42) (repeat 3 81) :: Array Int
-- Array [42,42,81,81,81]
append :: Array a -> Array a -> Array a
append (Array first) (Array second) =
  Array (first ++ second)


-- | Get a sub-section of an array: @(slice start end array)@. The @start@ is a
-- zero-based index where we will start our slice. The @end@ is a zero-based index
-- that indicates the end of the slice. The slice extracts up to but not including
-- @end@.
--
-- >>> slice  0  3 (fromLinkedList [0,1,2,3,4] :: Array Int)
-- Array [0,1,2]
-- >>> slice  1  4 (fromLinkedList [0,1,2,3,4] :: Array Int)
-- Array [1,2,3]
--
-- Both the @start@ and @end@ indexes can be negative, indicating an offset from
-- the end of the array.
--
-- >>> slice  1    (-1) (fromLinkedList [0,1,2,3,4] :: Array Int)
-- Array [1,2,3]
-- >>> slice  (-2) 5    (fromLinkedList [0,1,2,3,4] :: Array Int)
-- Array [3,4]
--
-- This makes it pretty easy to @pop@ the last element off of an array:
-- @slice 0 -1 array@
slice :: Int -> Int -> Array a -> Array a
slice from to (Array vector)
  | sliceLen <= 0 = empty
  | otherwise = Array <| Data.Vector.slice from' sliceLen vector
 where
  len = Data.Vector.length vector
  handleNegative value
    | value < 0 = len + value
    | otherwise = value
  normalize =
    Prelude.fromIntegral
      .> handleNegative
      .> clamp 0 len
  from' = normalize from
  to' = normalize to
  sliceLen = to' - from'


-- | Applies a function to each element of an array and flattens the resulting arrays into a single array.
--
-- This function takes a function `f` and an array `array`. It applies `f` to each element of `array` and
-- collects the resulting arrays into a single array. The resulting array is then returned.
--
-- The function `f` should take an element of type `a` and return an array of type `Array b`.
--
-- The `flatMap` function is implemented using the `map` and `reduce` functions. First, it applies `f` to each
-- element of `array` using the `map` function. Then, it flattens the resulting arrays into a single array
-- using the `reduce` function with the `append` function as the folding operation and `empty` as the initial
-- value. The resulting array is then returned.

-- This function is commonly used in functional programming to apply a function to each element of a nested
-- data structure and flatten the resulting structure into a single level.
-- >>> flatMap (\n -> fromLinkedList [n, n]) (fromLinkedList [1, 2, 3] :: Array Int)
-- Array [1,1,2,2,3,3]
-- >>> flatMap (\n -> if n > 1 then fromLinkedList [show n] else empty) (fromLinkedList [0, 1, 2, 3] :: Array Int)
-- Array ["2","3"]
-- >>> flatMap (\s -> fromLinkedList [s, s]) (empty :: Array String)
-- Array []
flatMap ::
  -- | The function to apply to each element of the array.
  (a -> Array b) ->
  -- | The input array.
  Array a ->
  -- | The resulting flattened array.
  Array b
flatMap f array =
  array
    |> map f
    |> reduce append empty


-- >>> foldM (\acc x -> do { putStrLn ("Adding " ++ show x ++ " to " ++ show acc); pure (acc + x) }) 0 (fromLinkedList [10, 5, 2] :: Array Int)
-- Adding 10 to 0
-- Adding 5 to 10
-- Adding 2 to 15
-- 17

-- | TODO: Find a better name for this function.
foldM :: forall (a :: Type) (b :: Type). (b -> a -> IO b) -> b -> Array a -> IO b
foldM f initial self =
  unwrap self
    |> Data.Foldable.foldlM f initial


-- | Drop elements from the beginning of an array until the given predicate
-- returns false.
-- >>> dropWhile (< 3) (fromLinkedList [1,2,3,4,1] :: Array Int)
-- Array [3,4,1]
-- >>> dropWhile (< 9) (fromLinkedList [1,2,3] :: Array Int)
-- Array []
dropWhile :: forall (value :: Type). (value -> Bool) -> Array value -> Array value
dropWhile predicate (Array vector) = Array (Data.Vector.dropWhile predicate vector)


-- | Keep elements from the beginning of an array until the given predicate
-- returns false.
-- >>> takeWhile (< 3) (fromLinkedList [1,2,3,4,1] :: Array Int)
-- Array [1,2]
-- >>> takeWhile (< 0) (fromLinkedList [1,2,3] :: Array Int)
-- Array []
takeWhile :: forall (value :: Type). (value -> Bool) -> Array value -> Array value
takeWhile predicate (Array vector) = Array (Data.Vector.takeWhile predicate vector)


-- | Partition an array into two subarrays based on a predicate.
-- The first array contains elements that satisfy the predicate,
-- while the second contains elements that do not.
--
-- >>> partitionBy Basics.isEven (fromLinkedList [1,2,3,4,5,6] :: Array Int)
-- (Array [2,4,6],Array [1,3,5])
partitionBy :: forall (value :: Type). (value -> Bool) -> Array value -> (Array value, Array value)
partitionBy predicate (Array vector) = do
  let (matching, nonMatching) = Data.Vector.partition predicate vector
  (Array matching, Array nonMatching)


-- | Split an array into its first element and the remaining elements.
-- If the array is empty, return `Nothing`.
--
-- >>> splitFirst (fromLinkedList [1,2,3] :: Array Int)
-- Just (1,Array [2,3])
splitFirst :: forall (value :: Type). Array value -> Maybe (value, Array value)
splitFirst (Array vector) = do
  case Data.Vector.uncons vector of
    Nothing -> Nothing
    Just (first, rest) -> Just (first, Array rest)


-- | Checks if any element in an array satisfies a given predicate.
-- Returns `True` if at least one element matches, otherwise `False`.
--
-- >>> any Basics.isEven (fromLinkedList [1,3,5,6] :: Array Int)
-- True
-- >>> any Basics.isEven (fromLinkedList [1,3,5] :: Array Int)
-- False
any :: forall (value :: Type). (value -> Bool) -> Array value -> Bool
any predicate (Array vector) = Data.Vector.any predicate vector


-- | Returns the last element in the array.
-- If the array is empty, returns `Nothing`.
-- >>> last (fromLinkedList [0,1,2] :: Array Int)
-- Just 2
-- >>> last (fromLinkedList [] :: Array Int)
-- Nothing
last :: forall (value :: Type). Array value -> Maybe value
last (Array vector) = do
  let len = Data.Vector.length vector
  vector Data.Vector.!? (len - 1)


-- | Convert a Haskell Vector to a NeoHaskell Array.
-- Only use this for compatibility with legacy code.
-- >>> fromLegacy (Data.Vector.fromList [1,2,3] :: Data.Vector.Vector Int)
-- Array [1,2,3]
fromLegacy :: Data.Vector.Vector a -> Array a
fromLegacy = Array


-- | Take the first n elements of an array.
-- >>> take 2 (fromLinkedList [1,2,3] :: Array Int)
-- Array [1,2]
-- >>> take 0 (fromLinkedList [1,2,3] :: Array Int)
-- Array []
take :: Int -> Array a -> Array a
take n (Array vector) = Array (Data.Vector.take n vector)


-- | Drop the first n elements of an array.
-- >>> drop 2 (fromLinkedList [1,2,3] :: Array Int)
-- Array [3]
-- >>> drop 0 (fromLinkedList [1,2,3] :: Array Int)
-- Array [1,2,3]
drop :: Int -> Array a -> Array a
drop n (Array vector) = Array (Data.Vector.drop n vector)


-- | Convert an array into an array of tuples, where the first element of the tuple is the index of the element.
-- >>> indexed (fromLinkedList [1,2,3] :: Array Int)
-- Array [(0,1),(1,2),(2,3)]
-- >>> indexed (fromLinkedList [] :: Array Int)
-- Array []
indexed :: Array a -> Array (Int, a)
indexed (Array vector) = Array (Data.Vector.indexed vector)


-- | Zip two arrays into a new array of tuples.
-- >>> (fromLinkedList [1,2,3] :: Array Int) |> zip (fromLinkedList [4,5,6] :: Array Int)
-- Array [(1,4),(2,5),(3,6)]
-- >>> (fromLinkedList [] :: Array Int) |> zip (fromLinkedList [] :: Array Int)
-- Array []
zip :: Array b -> Array a -> Array (a, b)
zip (Array second) (Array first) = Array (Data.Vector.zip first second)


-- | Adds up all the integers in an array.
-- >>> sumIntegers (fromLinkedList [1,2,3] :: Array Int)
-- 6
-- >>> sumIntegers (fromLinkedList [] :: Array Int)
-- 0
sumIntegers :: Array Int -> Int
sumIntegers (Array vector) = Data.Vector.sum vector


-- | Reverse an array.
-- >>> reverse (fromLinkedList [1,2,3] :: Array Int)
-- Array [3,2,1]
-- >>> reverse (fromLinkedList [] :: Array Int)
-- Array []
reverse :: Array a -> Array a
reverse (Array vector) = Array (Data.Vector.reverse vector)


-- | Flatten an array of arrays into a single array.
-- >>> flatten (fromLinkedList [ (fromLinkedList [1,2] :: Array Int), (fromLinkedList [3] :: Array Int) ])
-- Array [1,2,3]
-- >>> flatten (fromLinkedList [] :: Array (Array Int))
-- Array []
flatten :: Array (Array a) -> Array a
flatten (Array vector) = Array (Control.Monad.join (Data.Vector.map unwrap vector))


-- | Find the maximum element in an array.
-- If the array is empty, returns `Nothing`.
-- >>> maximum (fromLinkedList [1,2,3] :: Array Int)
-- Just 3
-- >>> maximum (fromLinkedList [] :: Array Int)
-- Nothing
maximum :: forall (value :: Type). (Ord value) => Array value -> Maybe value
maximum (Array vector) =
  if Data.Vector.null vector
    then Nothing
    else Just (Data.Vector.maximum vector)


-- | Find the minimum element in an array.
-- If the array is empty, returns `Nothing`.
-- >>> minimum (fromLinkedList [1,2,3] :: Array Int)
-- Just 1
-- >>> minimum (fromLinkedList [] :: Array Int)
-- Nothing
minimum :: forall (value :: Type). (Ord value) => Array value -> Maybe value
minimum (Array vector) =
  if Data.Vector.null vector
    then Nothing
    else Just (Data.Vector.minimum vector)
