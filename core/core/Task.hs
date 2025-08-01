module Task (
  Task (..),
  yield,
  throw,
  map,
  apply,
  andThen,
  run,
  runOrPanic,
  mapError,
  fromFailableIO,
  fromIO,
  runMain,
  forEach,
  runNoErrors,
  mapArray,
  runResult,
  unless,
  when,
  recover,
  asResult,
  fromIOResult,
  forever,
) where

import Applicable (Applicative (pure))
import Applicable qualified
import Array (Array)
import Array qualified
import Basics
import Control.Exception (Exception)
import Control.Exception qualified as Exception
import Control.Monad qualified
import Control.Monad.IO.Class qualified as Monad
import Control.Monad.Trans.Except (ExceptT)
import Control.Monad.Trans.Except qualified as Except
import Data.Either qualified as Either
import Data.Foldable qualified
import Data.Text.IO qualified as GHCText
import IO (IO)
import IO qualified
import Main.Utf8 (withUtf8)
import Mappable (Functor)
import Mappable qualified
import Result (Result)
import Result qualified
import Text (Text)
import Thenable (Monad)
import ToText (Show, toPrettyText)
import Prelude qualified


newtype Task err value = Task
  {runTask :: (ExceptT err IO) value}
  deriving (Functor, Applicable.Applicative, Monad)


yield :: value -> Task _ value
yield value = Task (Applicable.pure value)
{-# INLINE yield #-}


throw :: err -> Task err _
throw err = Task (Except.throwE err)
{-# INLINE throw #-}


map :: (input -> output) -> Task err input -> Task err output
map f self = Task (Mappable.map f (runTask self))
{-# INLINE map #-}


mapError :: (err1 -> err2) -> Task err1 value -> Task err2 value
mapError f self =
  runTask self
    |> Except.withExceptT f
    |> Task
{-# INLINE mapError #-}


apply :: Task err (input -> output) -> Task err input -> Task err output
apply taskFunction self = Task (Applicable.apply (runTask taskFunction) (runTask self))
{-# INLINE apply #-}


recover :: (err -> Task err2 value) -> Task err value -> Task err2 value
recover f self = Task (Except.catchE (runTask self) (runTask <. f))
{-# INLINE recover #-}


asResult :: Task err value -> Task err2 (Result err value)
asResult task =
  runResult task
    |> fromIO
{-# INLINE asResult #-}


andThen :: (input -> Task err output) -> Task err input -> Task err output
andThen f self = Task do
  value <- runTask self
  runTask (f value)
{-# INLINE andThen #-}


-- TODO: Figure out the best API to ensure that the main function is just a Task that cannot fail and returns a unit

runResult :: Task err value -> IO (Result err value)
runResult task = do
  runTask task
    |> Except.runExceptT
    |> IO.map Result.fromEither
{-# INLINE runResult #-}


run :: (Result err value -> IO value) -> Task err value -> IO value
run reducer task = do
  runTask task
    |> Except.runExceptT
    |> IO.map Result.fromEither
    |> IO.andThen reducer
    |> withUtf8
{-# INLINE run #-}


runNoErrors :: Task Never value -> IO value
runNoErrors task = do
  let reducer (Result.Ok value) = IO.yield value
      reducer (Result.Err _) = panic "Task.runNoErrors: Impossible error in Task Never - this indicates a type system violation"
  runTask task
    |> Except.runExceptT
    |> IO.map Result.fromEither
    |> IO.andThen reducer
    |> withUtf8
{-# INLINE runNoErrors #-}


runOrPanic :: (HasCallStack, Show err) => Task err value -> IO value
runOrPanic task = do
  let reducer result = case result of
        Result.Ok value -> IO.yield value
        Result.Err err -> panic (toPrettyText err)
      {-# INLINE reducer #-}
  task
    |> run reducer
    |> withUtf8
{-# INLINE runOrPanic #-}


runMain :: Task Text Unit -> IO Unit
runMain task = do
  let reducer (Result.Ok _) = IO.yield ()
      reducer (Result.Err err) = GHCText.putStrLn err
  task
    |> run reducer
    |> withUtf8
{-# INLINE runMain #-}


-- fromFailableIO is the reverse of run
-- it receives an io, an exception catcher, and returns a task
-- the task will run the io and catch exceptions
-- if an exception is caught, it will be passed to the exception catcher
-- if no exception is caught, the result will be passed to the success handler
fromFailableIO ::
  forall exception result.
  (Exception exception) =>
  IO result ->
  Task exception result
fromFailableIO io = do
  result <- io |> Exception.try @exception |> Monad.liftIO |> Task
  case result of
    Either.Left exception -> throw exception
    Either.Right value -> yield value
{-# INLINE fromFailableIO #-}


fromIO :: IO value -> Task _ value
fromIO io =
  io
    |> Monad.liftIO
    |> Task
{-# INLINE fromIO #-}


fromIOResult :: (Show err) => IO (Result err value) -> Task err value
fromIOResult io =
  io
    |> Prelude.fmap Result.toEither
    |> Except.ExceptT
    |> Task
{-# INLINE fromIOResult #-}


forEach ::
  forall (element :: Type) (err :: Type).
  (element -> Task err Unit) ->
  Array element ->
  Task err Unit
forEach callback array =
  Data.Foldable.traverse_ callback (Array.unwrap array)
{-# INLINE forEach #-}


mapArray :: (element -> Task err output) -> Array element -> Task err (Array output)
mapArray f array =
  Array.unwrap array
    |> Control.Monad.mapM f
    |> Task.map Array.fromLegacy
{-# INLINE mapArray #-}


-- | Run a task if a condition is false
unless :: Bool -> Task err Unit -> Task err Unit
unless condition task =
  if condition
    then Applicable.pure unit
    else task
{-# INLINE unless #-}


-- | Run a task if a condition is true
when :: Bool -> Task err Unit -> Task err Unit
when condition task =
  if condition
    then task
    else Applicable.pure unit
{-# INLINE when #-}


-- | Run a task indefinitely until it throws an exception
-- The exception will be caught and returned as an error
forever :: Task err Unit -> Task err Unit
forever task = Task do
  let loop = do
        result <- Monad.liftIO (Except.runExceptT (runTask task))
        case result of
          Either.Left err -> Except.throwE err -- Propagate the error and exit the loop
          Either.Right _ -> loop -- Continue the loop
      {-# INLINE loop #-}
  loop
{-# INLINE forever #-}
