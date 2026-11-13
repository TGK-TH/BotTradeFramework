#property strict
#property version "1.00"
#property description "Grid lifecycle integration tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridLifecycle.mqh>

CTGKTestRunner Tests;

string NewTestInstanceId(string suffix)
{
  return StringFormat(
    "L%I64d_%d%s",
    (long)TimeLocal(),
    (int)(GetTickCount() % 100000),
    suffix);
}

void CleanupInstance(string instance_id)
{
  CTGKGridPersistence cleanup;
  if(cleanup.Initialize(_Symbol, instance_id))
    cleanup.DeleteState(10);
}

void AssertState(
  string assertion_name,
  CTGKGridLifecycle &lifecycle,
  ENUM_TGK_GRID_STATE expected_state)
{
  STGKGridInstanceData data;
  bool data_ok = lifecycle.GetData(data);
  Tests.AssertTrue(assertion_name + " data available", data_ok);
  if(data_ok)
    Tests.AssertEqualInt(
      assertion_name,
      (int)data.state,
      (int)expected_state);
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Lifecycle Integration");

  string fresh_id = NewTestInstanceId("F");
  CTGKGridLifecycle fresh;
  Tests.BeginTest("New instance starts only when no positions exist");
  Tests.AssertTrue(
    "initialize fresh instance",
    fresh.Initialize(
      fresh_id,
      _Symbol,
      710981,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      0));
  AssertState(
    "fresh instance waits for first entry",
    fresh,
    TGK_GRID_STATE_WAIT_INITIAL_ENTRY);
  Tests.EndTest();

  Tests.BeginTest("Snapshot restores lifecycle state and actual anchor");
  Tests.AssertTrue(
    "record actual initial fill",
    fresh.RecordInitialFill(2650.37));
  CTGKGridLifecycle restarted;
  Tests.AssertTrue(
    "restart restores existing instance",
    restarted.Initialize(
      fresh_id,
      _Symbol,
      710981,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      1));
  STGKGridInstanceData restored;
  bool restored_ok = restarted.GetData(restored);
  Tests.AssertTrue("restored data available", restored_ok);
  if(restored_ok)
  {
    Tests.AssertEqualInt(
      "restored state active",
      (int)restored.state,
      (int)TGK_GRID_STATE_ACTIVE);
    Tests.AssertEqualDouble(
      "restored anchor is actual fill",
      restored.anchor_price,
      2650.37,
      0.000001);
    Tests.AssertEqualLong(
      "restored magic remains stable",
      restored.magic_number,
      710981);
  }
  Tests.EndTest();

  Tests.BeginTest("Mode reset remains pending across restart until positions are gone");
  Tests.AssertTrue(
    "request mode change",
    restarted.RequestConfiguration(
      TGK_GRID_MODE_SELL,
      2.5));
  CTGKGridLifecycle resetting;
  Tests.AssertTrue(
    "restore pending reset",
    resetting.Initialize(
      fresh_id,
      _Symbol,
      710981,
      TGK_GRID_MODE_SELL,
      2.5,
      0.01,
      1));
  AssertState(
    "pending reset remains close-old",
    resetting,
    TGK_GRID_STATE_RESET_CLOSE_OLD);
  Tests.AssertTrue(
    "still waits while one position remains",
    resetting.AdvanceReset(1));
  AssertState(
    "still close-old",
    resetting,
    TGK_GRID_STATE_RESET_CLOSE_OLD);
  Tests.AssertTrue(
    "zero positions advances to rebuild",
    resetting.AdvanceReset(0));
  AssertState(
    "state enters rebuild",
    resetting,
    TGK_GRID_STATE_RESET_REBUILD);
  Tests.AssertTrue(
    "apply pending configuration",
    resetting.AdvanceReset(0));
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
    Tests.AssertEqualInt(
      "mode reset waits for first entry",
      (int)reset_data.state,
      (int)TGK_GRID_STATE_WAIT_INITIAL_ENTRY);
  }
  Tests.EndTest();

  Tests.BeginTest("Missing snapshot with remaining positions enters recovery error");
  string orphaned_id = NewTestInstanceId("O");
  CTGKGridLifecycle orphaned;
  Tests.AssertTrue(
    "initialize orphaned instance into safe state",
    orphaned.Initialize(
      orphaned_id,
      _Symbol,
      710982,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      1));
  AssertState(
    "orphaned positions block fresh start",
    orphaned,
    TGK_GRID_STATE_RECOVERY_ERROR);
  Tests.EndTest();

  Tests.BeginTest("Magic mismatch between snapshot and current identity enters recovery error");
  string mismatch_id = NewTestInstanceId("M");
  CTGKGridLifecycle original;
  Tests.AssertTrue(
    "create original snapshot",
    original.Initialize(
      mismatch_id,
      _Symbol,
      710983,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      0));
  CTGKGridLifecycle mismatch;
  Tests.AssertTrue(
    "load mismatched identity into safe state",
    mismatch.Initialize(
      mismatch_id,
      _Symbol,
      710984,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      0));
  AssertState(
    "magic mismatch blocks lifecycle",
    mismatch,
    TGK_GRID_STATE_RECOVERY_ERROR);
  Tests.EndTest();

  Tests.BeginTest("Present but invalid snapshot enters recovery error");
  string corrupt_id = NewTestInstanceId("C");
  CTGKGridLifecycle valid_snapshot;
  Tests.AssertTrue(
    "create snapshot to corrupt",
    valid_snapshot.Initialize(
      corrupt_id,
      _Symbol,
      710985,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      0));
  string corrupt_mode_key = StringFormat(
    "TGK.G.%I64d.%s.%s.mode",
    AccountInfoInteger(ACCOUNT_LOGIN),
    _Symbol,
    corrupt_id);
  Tests.AssertTrue(
    "corrupt persisted mode",
    GlobalVariableSet(corrupt_mode_key, 99.0) != 0);
  GlobalVariablesFlush();

  CTGKGridLifecycle corrupted;
  Tests.AssertTrue(
    "invalid snapshot loads into safe state",
    corrupted.Initialize(
      corrupt_id,
      _Symbol,
      710985,
      TGK_GRID_MODE_BUY,
      2.5,
      0.01,
      0));
  AssertState(
    "invalid snapshot blocks lifecycle",
    corrupted,
    TGK_GRID_STATE_RECOVERY_ERROR);
  Tests.EndTest();

  Tests.EndSuite();

  CleanupInstance(fresh_id);
  CleanupInstance(orphaned_id);
  CleanupInstance(mismatch_id);
  CleanupInstance(corrupt_id);
  GlobalVariablesFlush();

  return INIT_SUCCEEDED;
}

void OnTick()
{
}
