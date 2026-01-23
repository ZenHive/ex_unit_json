# This file simulates a project that logs during test setup
# (like ccxt_ex logging credential registration)
require Logger

Logger.info("✓ Test setup message from test_helper.exs")
Logger.info("This should NOT appear when --quiet is used")

ExUnit.start()
