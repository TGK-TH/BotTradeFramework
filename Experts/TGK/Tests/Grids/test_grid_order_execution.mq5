#property strict
#property version "1.00"
#property description "Grid order execution policy tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridOrderExecutionAdapter.mqh>

CTGKTestRunner Tests;

void SetClosePositions(
  STGKGridPositionRecord &positions[],
  string symbol,
  long magic_number
)
{
  ArrayResize(positions, 5);

  positions[0].ticket = 1001;
  positions[0].symbol = symbol;
  positions[0].magic_number = magic_number;

  positions[1].ticket = 1002;
  positions[1].symbol = symbol;
  positions[1].magic_number = magic_number;

  positions[2].ticket = 2001;
  positions[2].symbol = symbol;
  positions[2].magic_number = magic_number + 1;

  positions[3].ticket = 3001;
  positions[3].symbol = symbol + "_OTHER";
  positions[3].magic_number = magic_number;

  positions[4].ticket = 3002;
  positions[4].symbol = symbol + "_OTHER";
  positions[4].magic_number = magic_number + 1;
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Order Execution Policy");

  CTGKGridOrderExecutionPolicy policy;
  STGKGridPositionRecord positions[];
  ulong tickets[];

  Tests.BeginTest("Batch contains only exact Symbol and Magic Number ownership");
  SetClosePositions(positions, _Symbol, 712001);
  Tests.AssertTrue(
    "build close batch when close is required",
    policy.BuildCloseBatch(
      TGK_GRID_RUNTIME_CLOSE_REQUIRED,
      positions,
      _Symbol,
      712001,
      tickets));
  Tests.AssertEqualInt(
    "batch contains both owned positions",
    ArraySize(tickets),
    2);
  if(ArraySize(tickets) == 2)
  {
    Tests.AssertEqualLong(
      "first owned ticket retained",
      (long)tickets[0],
      1001);
    Tests.AssertEqualLong(
      "second owned ticket retained",
      (long)tickets[1],
      1002);
  }
  Tests.EndTest();

  Tests.BeginTest("No close batch is produced outside CLOSE_REQUIRED");
  Tests.AssertFalse(
    "ACTIVE status cannot create close batch",
    policy.BuildCloseBatch(
      TGK_GRID_RUNTIME_ACTIVE,
      positions,
      _Symbol,
      712001,
      tickets));
  Tests.AssertFalse(
    "WAIT_CLOSE_CONFIRMATION cannot create close batch",
    policy.BuildCloseBatch(
      TGK_GRID_RUNTIME_WAIT_CLOSE_CONFIRMATION,
      positions,
      _Symbol,
      712001,
      tickets));
  Tests.AssertEqualInt(
    "blocked request leaves no tickets",
    ArraySize(tickets),
    0);
  Tests.EndTest();

  Tests.BeginTest("Invalid ownership identity is rejected");
  Tests.AssertFalse(
    "empty symbol rejected",
    policy.BuildCloseBatch(
      TGK_GRID_RUNTIME_CLOSE_REQUIRED,
      positions,
      "",
      712001,
      tickets));
  Tests.AssertFalse(
    "non-positive magic rejected",
    policy.BuildCloseBatch(
      TGK_GRID_RUNTIME_CLOSE_REQUIRED,
      positions,
      _Symbol,
      0,
      tickets));
  Tests.EndTest();

  Tests.BeginTest("Trade retcodes are classified conservatively");
  Tests.AssertEqualInt(
    "DONE is accepted",
    (int)policy.ClassifyCloseResult(true, TRADE_RETCODE_DONE),
    (int)TGK_GRID_CLOSE_ATTEMPT_ACCEPTED);
  Tests.AssertEqualInt(
    "DONE_PARTIAL is accepted for reconciliation",
    (int)policy.ClassifyCloseResult(true, TRADE_RETCODE_DONE_PARTIAL),
    (int)TGK_GRID_CLOSE_ATTEMPT_ACCEPTED);
  Tests.AssertEqualInt(
    "PLACED is accepted but not completed",
    (int)policy.ClassifyCloseResult(true, TRADE_RETCODE_PLACED),
    (int)TGK_GRID_CLOSE_ATTEMPT_ACCEPTED);
  Tests.AssertEqualInt(
    "market closed is retryable",
    (int)policy.ClassifyCloseResult(true, TRADE_RETCODE_MARKET_CLOSED),
    (int)TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED);
  Tests.AssertEqualInt(
    "request not sent is failed",
    (int)policy.ClassifyCloseResult(false, TRADE_RETCODE_DONE),
    (int)TGK_GRID_CLOSE_ATTEMPT_FAILED);
  Tests.EndTest();

  Tests.BeginTest("Batch outcome preserves partial failure for retry");
  ENUM_TGK_GRID_CLOSE_ATTEMPT_RESULT outcomes[];
  ArrayResize(outcomes, 3);
  outcomes[0] = TGK_GRID_CLOSE_ATTEMPT_ACCEPTED;
  outcomes[1] = TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED;
  outcomes[2] = TGK_GRID_CLOSE_ATTEMPT_ACCEPTED;

  Tests.AssertEqualInt(
    "market closed dominates accepted requests",
    (int)policy.CombineCloseResults(outcomes),
    (int)TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED);

  outcomes[1] = TGK_GRID_CLOSE_ATTEMPT_FAILED;
  Tests.AssertEqualInt(
    "failed request dominates batch result",
    (int)policy.CombineCloseResults(outcomes),
    (int)TGK_GRID_CLOSE_ATTEMPT_FAILED);

  ArrayResize(outcomes, 2);
  outcomes[0] = TGK_GRID_CLOSE_ATTEMPT_ACCEPTED;
  outcomes[1] = TGK_GRID_CLOSE_ATTEMPT_ACCEPTED;
  Tests.AssertEqualInt(
    "all accepted remains pending reconciliation",
    (int)policy.CombineCloseResults(outcomes),
    (int)TGK_GRID_CLOSE_ATTEMPT_ACCEPTED);

  ArrayResize(outcomes, 0);
  Tests.AssertEqualInt(
    "empty batch is failed rather than accepted",
    (int)policy.CombineCloseResults(outcomes),
    (int)TGK_GRID_CLOSE_ATTEMPT_FAILED);
  Tests.EndTest();

  Tests.BeginTest("Live adapter validates identity and blocks non-close runtime states");
  CTGKGridOrderExecutionAdapter adapter;
  CTGKGridRuntimeOrchestrator runtime;
  CTrade trader;

  Tests.AssertFalse(
    "adapter rejects empty symbol",
    adapter.Initialize("", 712001));
  Tests.AssertFalse(
    "adapter rejects non-positive magic",
    adapter.Initialize(_Symbol, 0));
  Tests.AssertTrue(
    "adapter accepts valid identity",
    adapter.Initialize(_Symbol, 712001));
  Tests.AssertEqualInt(
    "ACTIVE status exits without sending close requests",
    (int)adapter.ExecuteCloseIfRequired(
      TGK_GRID_RUNTIME_ACTIVE,
      runtime,
      trader),
    (int)TGK_GRID_EXECUTION_NO_ACTION);

  string runtime_id = StringFormat(
    "OE%I64d_%d",
    (long)TimeLocal(),
    (int)(GetTickCount() % 100000));
  STGKGridPositionRecord no_positions[];
  ArrayResize(no_positions, 0);
  Tests.AssertTrue(
    "initialize runtime identity for mismatch guard",
    runtime.InitializeFromSnapshot(
      runtime_id,
      _Symbol,
      712002,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      no_positions));
  Tests.AssertEqualInt(
    "adapter refuses a different runtime identity",
    (int)adapter.ExecuteCloseIfRequired(
      TGK_GRID_RUNTIME_CLOSE_REQUIRED,
      runtime,
      trader),
    (int)TGK_GRID_EXECUTION_INVALID_IDENTITY);
  Tests.EndTest();

  Tests.EndSuite();

  CTGKGridPersistence cleanup;
  if(cleanup.Initialize(_Symbol, runtime_id))
    cleanup.DeleteState(10);
  GlobalVariablesFlush();

  return INIT_SUCCEEDED;
}

void OnTick()
{
}
