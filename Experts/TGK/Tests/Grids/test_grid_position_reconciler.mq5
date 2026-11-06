#property strict
#property version "1.00"
#property description "Tests for Grid position ownership and close reconciliation policy; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridPositionReconciler.mqh>

CTGKTestRunner Tests;

int OnInit()
{
  Tests.BeginSuite("TGK Grid Position Reconciler");

  Tests.BeginTest("Ownership requires both exact symbol and Magic Number");
  CTGKGridPositionReconciler ownership;
  Tests.AssertTrue(
    "matching symbol and magic is owned",
    ownership.IsOwnedPosition("XAUUSD", 710901, "XAUUSD", 710901));
  Tests.AssertFalse(
    "different symbol is foreign",
    ownership.IsOwnedPosition("XAUUSD", 710901, "EURUSD", 710901));
  Tests.AssertFalse(
    "different magic is foreign",
    ownership.IsOwnedPosition("XAUUSD", 710901, "XAUUSD", 710902));
  Tests.AssertFalse(
    "empty expected symbol is invalid",
    ownership.IsOwnedPosition("", 710901, "XAUUSD", 710901));
  Tests.AssertFalse(
    "non-positive expected magic is invalid",
    ownership.IsOwnedPosition("XAUUSD", 0, "XAUUSD", 0));
  Tests.EndTest();

  Tests.BeginTest("Count only positions owned by this Grid Instance");
  STGKGridPositionRecord positions[];
  ArrayResize(positions, 5);

  positions[0].ticket = 1001;
  positions[0].symbol = "XAUUSD";
  positions[0].magic_number = 710901;

  positions[1].ticket = 1002;
  positions[1].symbol = "XAUUSD";
  positions[1].magic_number = 710902;

  positions[2].ticket = 1003;
  positions[2].symbol = "EURUSD";
  positions[2].magic_number = 710901;

  positions[3].ticket = 1004;
  positions[3].symbol = "XAUUSD";
  positions[3].magic_number = 710901;

  positions[4].ticket = 1005;
  positions[4].symbol = "GBPUSD";
  positions[4].magic_number = 710903;

  Tests.AssertEqualInt(
    "count matches symbol and magic only",
    ownership.CountOwnedPositions(positions, "XAUUSD", 710901),
    2);
  Tests.AssertEqualInt(
    "no positions owned by another instance",
    ownership.CountOwnedPositions(positions, "XAUUSD", 710999),
    0);
  Tests.AssertEqualInt(
    "invalid ownership filter is reported as an error",
    ownership.CountOwnedPositions(positions, "", 710901),
    -1);
  Tests.AssertEqualInt(
    "invalid live scan filter is reported as an error",
    ownership.CountLiveOwnedPositions("XAUUSD", 0),
    -1);
  Tests.EndTest();

  Tests.BeginTest("Accepted close request waits for fresh account reconciliation");
  CTGKGridPositionReconciler pending;
  Tests.AssertEqualInt(
    "existing positions require a close attempt",
    (int)pending.Reconcile(3),
    (int)TGK_GRID_RECONCILE_RETRY_REQUIRED);
  Tests.AssertEqualInt(
    "accepted request is pending, not confirmed closed",
    (int)pending.RecordCloseAttempt(TGK_GRID_CLOSE_ATTEMPT_ACCEPTED),
    (int)TGK_GRID_RECONCILE_WAITING);
  Tests.AssertEqualInt(
    "first fresh observation waits for close completion",
    (int)pending.Reconcile(2),
    (int)TGK_GRID_RECONCILE_WAITING);
  Tests.AssertEqualInt(
    "positions still present on next observation require retry",
    (int)pending.Reconcile(2),
    (int)TGK_GRID_RECONCILE_RETRY_REQUIRED);
  Tests.AssertEqualInt(
    "zero observed positions confirms completion",
    (int)pending.Reconcile(0),
    (int)TGK_GRID_RECONCILE_COMPLETE);
  Tests.EndTest();

  Tests.BeginTest("Market closed or failed close request remains retryable");
  CTGKGridPositionReconciler market_closed;
  market_closed.RecordCloseAttempt(TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED);
  Tests.AssertEqualInt(
    "market closed requires retry",
    (int)market_closed.Reconcile(2),
    (int)TGK_GRID_RECONCILE_RETRY_REQUIRED);

  CTGKGridPositionReconciler failed;
  failed.RecordCloseAttempt(TGK_GRID_CLOSE_ATTEMPT_FAILED);
  Tests.AssertEqualInt(
    "failed request requires retry",
    (int)failed.Reconcile(1),
    (int)TGK_GRID_RECONCILE_RETRY_REQUIRED);
  Tests.EndTest();

  Tests.BeginTest("Restart does not assume an earlier close request is still pending");
  CTGKGridPositionReconciler restarted;
  Tests.AssertEqualInt(
    "fresh reconciler rechecks positions and requests retry",
    (int)restarted.Reconcile(1),
    (int)TGK_GRID_RECONCILE_RETRY_REQUIRED);
  Tests.AssertEqualInt(
    "fresh reconciler can record a new accepted request",
    (int)restarted.RecordCloseAttempt(TGK_GRID_CLOSE_ATTEMPT_ACCEPTED),
    (int)TGK_GRID_RECONCILE_WAITING);
  Tests.EndTest();

  Tests.BeginTest("Invalid position count enters recovery error");
  CTGKGridPositionReconciler invalid;
  Tests.AssertEqualInt(
    "negative count is rejected",
    (int)invalid.Reconcile(-1),
    (int)TGK_GRID_RECONCILE_ERROR);
  Tests.AssertEqualInt(
    "recovery error blocks further reconciliation",
    (int)invalid.Reconcile(0),
    (int)TGK_GRID_RECONCILE_ERROR);
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
