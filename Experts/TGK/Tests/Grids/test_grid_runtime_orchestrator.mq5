#property strict
#property version "1.00"
#property description "Grid runtime orchestration tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridRuntimeOrchestrator.mqh>

CTGKTestRunner Tests;

string NewRuntimeInstanceId(string suffix)
{
  return StringFormat(
    "RT%I64d_%d%s",
    (long)TimeLocal(),
    (int)(GetTickCount() % 100000),
    suffix);
}

void CleanupRuntimeInstance(string instance_id)
{
  CTGKGridPersistence cleanup;
  if(cleanup.Initialize(_Symbol, instance_id))
    cleanup.DeleteState(10);
}

void SetPositions(
  STGKGridPositionRecord &positions[],
  string expected_symbol,
  long magic_number,
  int owned_count,
  int foreign_count
)
{
  ArrayResize(positions, owned_count + foreign_count);

  for(int i = 0; i < owned_count; i++)
  {
    positions[i].ticket = (ulong)(2000 + i);
    positions[i].symbol = expected_symbol;
    positions[i].magic_number = magic_number;
  }

  for(int i = 0; i < foreign_count; i++)
  {
    int index = owned_count + i;
    positions[index].ticket = (ulong)(3000 + i);
    positions[index].symbol = expected_symbol + "_OTHER";
    positions[index].magic_number = 711001;
  }
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Runtime Orchestrator");

  string fresh_id = NewRuntimeInstanceId("F");
  Tests.BeginTest("Fresh instance initializes lifecycle and reports readiness");
  CTGKGridRuntimeOrchestrator fresh;
  STGKGridPositionRecord no_positions[];
  ArrayResize(no_positions, 0);

  Tests.AssertTrue(
    "initialize from empty snapshot",
    fresh.InitializeFromSnapshot(
      fresh_id,
      _Symbol,
      711001,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      no_positions));
  Tests.AssertEqualInt(
    "fresh instance waits for initial entry",
    (int)fresh.UpdateFromSnapshot(no_positions),
    (int)TGK_GRID_RUNTIME_WAIT_INITIAL_ENTRY);
  Tests.AssertTrue(
    "record actual initial fill",
    fresh.RecordInitialFill(2650.37));
  Tests.AssertEqualInt(
    "filled instance becomes active",
    (int)fresh.UpdateFromSnapshot(no_positions),
    (int)TGK_GRID_RUNTIME_ACTIVE);
  Tests.EndTest();

  string reset_id = NewRuntimeInstanceId("R");
  Tests.BeginTest("Reset orchestration signals close, reconciles, then rebuilds");
  CTGKGridRuntimeOrchestrator resetting;
  Tests.AssertTrue(
    "initialize reset instance",
    resetting.InitializeFromSnapshot(
      reset_id,
      _Symbol,
      711002,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      no_positions));
  Tests.AssertTrue(
    "record initial fill",
    resetting.RecordInitialFill(2650.37));
  Tests.AssertTrue(
    "request mode reset",
    resetting.RequestConfiguration(
      TGK_GRID_MODE_SELL,
      2.5));

  STGKGridPositionRecord positions[];
  SetPositions(positions, _Symbol, 711002, 2, 2);
  Tests.AssertEqualInt(
    "owned positions require close action",
    (int)resetting.UpdateFromSnapshot(positions),
    (int)TGK_GRID_RUNTIME_CLOSE_REQUIRED);
  Tests.AssertEqualInt(
    "accepted close request waits for fresh account state",
    (int)resetting.RecordCloseAttempt(
      TGK_GRID_CLOSE_ATTEMPT_ACCEPTED),
    (int)TGK_GRID_RECONCILE_WAITING);
  Tests.AssertEqualInt(
    "first fresh observation waits",
    (int)resetting.UpdateFromSnapshot(positions),
    (int)TGK_GRID_RUNTIME_WAIT_CLOSE_CONFIRMATION);
  Tests.AssertEqualInt(
    "remaining positions signal retry",
    (int)resetting.UpdateFromSnapshot(positions),
    (int)TGK_GRID_RUNTIME_CLOSE_REQUIRED);

  ArrayResize(positions, 0);
  Tests.AssertEqualInt(
    "zero owned positions completes reset",
    (int)resetting.UpdateFromSnapshot(positions),
    (int)TGK_GRID_RUNTIME_WAIT_INITIAL_ENTRY);

  STGKGridInstanceData reset_data;
  bool reset_data_ok = resetting.GetData(reset_data);
  Tests.AssertTrue("reset data available", reset_data_ok);
  if(reset_data_ok)
  {
    Tests.AssertEqualInt(
      "new mode applied",
      (int)reset_data.mode,
      (int)TGK_GRID_MODE_SELL);
    Tests.AssertEqualDouble(
      "mode reset clears anchor",
      reset_data.anchor_price,
      0.0,
      0.000001);
  }
  Tests.EndTest();

  string restart_id = NewRuntimeInstanceId("S");
  Tests.BeginTest("Restart restores pending reset and requires fresh reconciliation");
  CTGKGridRuntimeOrchestrator before_restart;
  Tests.AssertTrue(
    "initialize before restart",
    before_restart.InitializeFromSnapshot(
      restart_id,
      _Symbol,
      711003,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      no_positions));
  Tests.AssertTrue(
    "record anchor before restart",
    before_restart.RecordInitialFill(2650.37));
  Tests.AssertTrue(
    "persist pending reset",
    before_restart.RequestConfiguration(
      TGK_GRID_MODE_SELL,
      2.5));

  SetPositions(positions, _Symbol, 711003, 1, 1);
  CTGKGridRuntimeOrchestrator after_restart;
  Tests.AssertTrue(
    "restore same instance with pending configuration",
    after_restart.InitializeFromSnapshot(
      restart_id,
      _Symbol,
      711003,
      TGK_GRID_MODE_SELL,
      2.5,
      0.01,
      positions));
  Tests.AssertEqualInt(
    "restart requires close action based on fresh positions",
    (int)after_restart.UpdateFromSnapshot(positions),
    (int)TGK_GRID_RUNTIME_CLOSE_REQUIRED);
  Tests.AssertEqualInt(
    "failed close remains retryable",
    (int)after_restart.RecordCloseAttempt(
      TGK_GRID_CLOSE_ATTEMPT_FAILED),
    (int)TGK_GRID_RECONCILE_RETRY_REQUIRED);
  Tests.AssertEqualInt(
    "market closed remains retryable",
    (int)after_restart.RecordCloseAttempt(
      TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED),
    (int)TGK_GRID_RECONCILE_RETRY_REQUIRED);
  ArrayResize(positions, 0);
  Tests.AssertEqualInt(
    "restart completes after fresh zero count",
    (int)after_restart.UpdateFromSnapshot(positions),
    (int)TGK_GRID_RUNTIME_WAIT_INITIAL_ENTRY);
  Tests.EndTest();

  string orphan_id = NewRuntimeInstanceId("O");
  Tests.BeginTest("Missing snapshot with owned positions is never adopted");
  SetPositions(positions, _Symbol, 711004, 1, 0);
  CTGKGridRuntimeOrchestrator orphaned;
  Tests.AssertTrue(
    "initialize orphaned instance into safe error",
    orphaned.InitializeFromSnapshot(
      orphan_id,
      _Symbol,
      711004,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      positions));
  Tests.AssertEqualInt(
    "orphaned instance reports error",
    (int)orphaned.UpdateFromSnapshot(positions),
    (int)TGK_GRID_RUNTIME_ERROR);
  Tests.EndTest();

  Tests.EndSuite();

  CleanupRuntimeInstance(fresh_id);
  CleanupRuntimeInstance(reset_id);
  CleanupRuntimeInstance(restart_id);
  CleanupRuntimeInstance(orphan_id);
  GlobalVariablesFlush();

  return INIT_SUCCEEDED;
}

void OnTick()
{
}
