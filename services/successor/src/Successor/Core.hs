-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Core
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Computes the successor of a natural number in the range
--                  of the AaaS addition from the answers of the digit
--                  services and the carry service.
-- Related Docs:    services/successor/docs/SERVICE_CHARTER.md, CLAUDE.md 1
--                  (rule 5), 3 (step 7) and 4.4, ADR-0016, ADR-0033

-- | The successor function @S(n) = n + 1@ of Peano arithmetic, without
-- the native @+@.
--
-- __Description:__ The domain is @0 .. 199 997@: the largest sum of two
-- operands is @99 999 + 99 999 = 199 998@, so no successor call of an
-- addition ever needs a larger argument. 'successorVia' takes the decimal
-- digits of @n@ ('toDigits'), asks the digit service of the units digit
-- for its successor and, when that digit wraps with a carry, hands the
-- digits to the carry service, which adds the carry at position 1 and
-- beyond. The digits are read and written as decimal text ('show' and
-- 'read'), so no arithmetic on @n@ happens in this service.
--
-- __Business Justification:__ An addition @a + b@ is @b@ applications of
-- this function to @a@ (CLAUDE.md 1, rule 5). It is the heart of the
-- product, and the digit services are its single source of truth.
--
-- __Thread Safety:__ pure; safe. 'successorVia' is as safe as the actions
-- it is given.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0 (digit services and carry since 0.2.0)
module Successor.Core
  ( maxArgument,
    NextError (..),
    checkArgument,
    DigitStep (..),
    toDigits,
    fromDigits,
    successorVia,
    describeError,
  )
where

import Data.Char (digitToInt, intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text

-- | Largest argument accepted by 'checkArgument'.
--
-- __Description:__ @199 997@, so that the result never exceeds the largest
-- possible sum, @199 998@ (the @sum@ definition of the event envelope).
--
-- __Business Justification:__ A call outside the range of an addition is
-- a defect of the caller and is reported instead of computed.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- >>> maxArgument
-- 199997
maxArgument :: Integer
maxArgument = 199997

-- | Why a successor cannot be computed.
--
-- __Description:__ 'Negative' for @n < 0@ (not a natural number);
-- 'AboveRange' for @n > 'maxArgument'@.
--
-- __Business Justification:__ Distinct reasons in the problem detail of
-- the HTTP API and the message of the gRPC status.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data NextError
  = -- | The argument is below zero.
    Negative Integer
  | -- | The argument is above 'maxArgument'.
    AboveRange Integer
  deriving stock (Eq, Show)

-- | Checks that an argument is in the domain.
--
-- __Description:__ Comparisons only; the argument is returned unchanged.
--
-- __Business Justification:__ Nothing is asked of the digit services for
-- a call that is not part of an addition.
--
-- __Parameters:__
--
-- * @n@: the argument.
--
-- __Returns:__ @Right n@ for @n@ in @[0, 199997]@.
--
-- __Errors:__ @Left ('Negative' n)@ or @Left ('AboveRange' n)@ outside the
-- domain.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(1) time and memory.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__
--
-- >>> checkArgument 199
-- Right 199
-- >>> checkArgument 199998
-- Left (AboveRange 199998)
--
-- __See Also:__ 'successorVia'.
checkArgument :: Integer -> Either NextError Integer
checkArgument n
  | n < 0 = Left (Negative n)
  | n > maxArgument = Left (AboveRange n)
  | otherwise = Right n

-- | The answer of a digit service to @GET /next@.
--
-- __Description:__ The successor digit and whether it wrapped
-- (CLAUDE.md 4.4): @DigitStep 8 False@ from @digit-7@, @DigitStep 0 True@
-- from @digit-9@.
--
-- __Business Justification:__ The only arithmetic fact the successor
-- needs, owned by the digit services.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
data DigitStep = DigitStep
  { -- | The successor digit, @0..9@.
    stepNext :: Int,
    -- | Whether the digit wrapped and a carry goes to the next position.
    stepCarry :: Bool
  }
  deriving stock (Eq, Show)

-- | The decimal digits of a natural number, least significant first.
--
-- __Description:__ Read from the decimal text of @n@ ('show'), reversed;
-- @0@ has the single digit @0@. This is the digit order of the carry
-- contract (@contracts/proto/aaas/carry/v1@).
--
-- __Business Justification:__ The digit services and the carry service
-- work on digits, not numbers.
--
-- __Parameters:__
--
-- * @n@: natural number (the caller checked the domain).
--
-- __Returns:__ the digits, each in @0..9@, least significant first.
--
-- __Errors:__ None for a natural number.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(d) time and memory, @d@ the number of digits.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__
--
-- >>> toDigits 1209
-- [9,0,2,1]
-- >>> toDigits 0
-- [0]
--
-- __See Also:__ 'fromDigits'.
toDigits :: Integer -> [Int]
toDigits n = map digitToInt (reverse (show n))

-- | The natural number of a list of decimal digits, least significant first.
--
-- __Description:__ The inverse of 'toDigits': the digits are written as
-- decimal text, most significant first, and read back ('read').
--
-- __Business Justification:__ The answer of the carry service is a list
-- of digits; the successor answers a number.
--
-- __Parameters:__
--
-- * @digits@: non-empty, each in @0..9@ (checked by the caller).
--
-- __Returns:__ the number.
--
-- __Errors:__ None for valid digits.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(d) time and memory.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__
--
-- >>> fromDigits [0,0,0,1]
-- 1000
--
-- __See Also:__ 'toDigits'.
fromDigits :: [Int] -> Integer
fromDigits digits = read (map intToDigit (reverse digits))

-- | Computes @n + 1@ from the digit services and the carry service.
--
-- __Description:__ Asks @askDigit@ for the successor of the units digit of
-- @n@. Without a carry, the units digit is replaced and the other digits
-- are kept. With a carry (the units digit was 9), the units digit becomes
-- the answer (0) and @propagate digits 1@ asks the carry service to add
-- the carry at position 1 and beyond; its digits are the result. Each
-- action is called at most once, and the first failure is returned as is.
--
-- __Business Justification:__ The Peano step of CLAUDE.md 3 (step 7),
-- computed by the services that own the digits.
--
-- __Parameters:__
--
-- * @askDigit@: the successor of one digit (@digit-d@, @GET /next@).
-- * @propagate@: the carry service: digits (least significant first) and
--   the position that receives the carry; returns the new digits.
-- * @n@: natural number in @[0, 199997]@ ('checkArgument').
--
-- __Returns:__ @Right (n + 1)@, or the first failure of an action.
--
-- __Errors:__ the @Left@ of @askDigit@ or @propagate@.
--
-- __Side Effects:__ those of the actions: one digit call, and one carry
-- call when the units digit is 9.
--
-- __Complexity:__ O(d) time and memory plus at most two calls.
--
-- __Thread Safety:__ as safe as the actions.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ With a digit table and a carry that appends a 1 (enough for
-- a units digit 9 followed by no other digit):
--
-- >>> let table = zip [0 .. 9] (map (\d -> DigitStep d (d == 0)) ([1 .. 9] ++ [0]))
-- >>> let ask d = pure (maybe (Left "no digit") Right (lookup d table)) :: Maybe (Either String DigitStep)
-- >>> successorVia ask (\_ _ -> pure (Right [0, 1])) 9
-- Just (Right 10)
-- >>> successorVia ask (\_ _ -> pure (Left "carry down")) 1208
-- Just (Right 1209)
--
-- __See Also:__ 'Successor.Digits.askNext', 'Successor.Carry.propagate',
-- CLAUDE.md 4.3 (@Next@, @Propagate@).
successorVia ::
  (Monad m) =>
  (Int -> m (Either e DigitStep)) ->
  ([Int] -> Int -> m (Either e [Int])) ->
  Integer ->
  m (Either e Integer)
successorVia askDigit propagate n =
  askDigit units >>= \case
    Left err -> pure (Left err)
    Right (DigitStep digit False) -> pure (Right (fromDigits (digit : higher)))
    Right (DigitStep digit True) -> fmap fromDigits <$> propagate (digit : higher) 1
  where
    -- toDigits never returns an empty list for a natural number.
    (units, higher) = case toDigits n of
      u : h -> (u, h)
      [] -> (0, [])

-- | Human-readable description of a 'NextError'.
--
-- __Description:__ One English sentence fragment naming the argument and
-- the domain.
--
-- __Business Justification:__ The @detail@ of the RFC 9457 problem and the
-- message of the gRPC status.
--
-- __Parameters:__
--
-- * @err@: the error.
--
-- __Returns:__ the description.
--
-- __Errors:__ None.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> describeError (Negative (-1))
-- "n = -1 is not a natural number"
--
-- __See Also:__ 'checkArgument'.
describeError :: NextError -> Text
describeError = \case
  Negative n -> "n = " <> tshow n <> " is not a natural number"
  AboveRange n ->
    "n = "
      <> tshow n
      <> " is above "
      <> tshow maxArgument
      <> ", the largest argument of an addition"
  where
    tshow = Text.pack . show
