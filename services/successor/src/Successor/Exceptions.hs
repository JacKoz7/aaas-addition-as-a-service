-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Exceptions
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Catches the synchronous exceptions of a dependency call
--                  and lets asynchronous ones (timeouts, cancellation) pass.
-- Related Docs:    services/successor/README.md, ADR-0033

-- | Exception handling of dependency calls.
--
-- __Description:__ 'trySync' is 'Control.Exception.try' at
-- 'SomeException' for synchronous exceptions only. An asynchronous
-- exception (the 'System.Timeout.timeout' of a deadline, a cancelled
-- thread at shutdown) is rethrown, so that a deadline around a call with
-- retries is never mistaken for a failed attempt.
--
-- __Business Justification:__ The 2 s deadline of a carry call
-- (ADR-0033) must end the call, not be swallowed by its retry loop.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
module Successor.Exceptions
  ( trySync,
  )
where

import Control.Exception (SomeAsyncException, SomeException, fromException, throwIO, try)

-- | Runs an action and returns its synchronous exception, if any.
--
-- __Description:__ See the module documentation.
--
-- __Business Justification:__ One rule for every dependency call.
--
-- __Parameters:__
--
-- * @action@: the call.
--
-- __Returns:__ @Right@ the result, or @Left@ a synchronous exception.
--
-- __Errors:__ rethrows asynchronous exceptions.
--
-- __Side Effects:__ those of the action.
--
-- __Complexity:__ that of the action.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__
--
-- >>> either (const False) (const True) <$> trySync (ioError (userError "down"))
-- False
--
-- __See Also:__ 'Successor.Carry.propagate', 'Successor.Digits.askNext'.
trySync :: IO a -> IO (Either SomeException a)
trySync action = do
  result <- try action
  case result of
    Left e | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
    other -> pure other
