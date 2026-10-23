#property strict
#property version "1.00"
#property description "Integration tests for Grid persistence using terminal Global Variables."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridPersistence.mqh>

CTGKTestRunner Tests;
CTGKGridPersistence Persistence;
string TestInstanceId;
string TestPrefix;

string TestKey(string suffix)
{
  return TestPrefix + "." + suffix;
}

void FillValidData(STGKGridInstanceData &data)
{
  data.instance_id = TestInstanceId;
  data.symbol = _Symbol;
  data.magic_number = 710321;
  data.mode = TGK_GRID_MODE_BUY;
  data.state = TGK_GRID_STATE_ACTIVE;
  data.anchor_price = 2651.75;
  data.grid_step_price = 2.0;
  data.fixed_lot = 0.02;
  data.reset_reason = TGK_GRID_RESET_NONE;
  data.pending_mode = TGK_GRID_MODE_BUY;
  data.pending_grid_step_price = 0.0;
  data.pending_magic_number = 0;
  data.level_count = 3;
  data.last_state_change = (datetime)1760000000;
}

int OnInit()
{
  TestInstanceId = StringFormat(
    "UT%d_%I64d",
    (int)ChartID(),
    (long)TimeLocal());
  TestPrefix = StringFormat(
    "TGK.G.%I64d.%s.%s",
    AccountInfoInteger(ACCOUNT_LOGIN),
    _Symbol,
    TestInstanceId);

  Tests.BeginSuite("TGK Grid Persistence");

  if(!Persistence.Initialize(
    _Symbol,
    TestInstanceId))
  {
    Print("FATAL: persistence test initialization failed.");
    return INIT_FAILED;
  }

  // Remove only this test run's namespace before starting.
  Persistence.DeleteState(10);

  STGKGridInstanceData data;
  FillValidData(data);

  Tests.BeginTest("Restore rejects missing snapshot");
  STGKGridInstanceData missing;
  Tests.AssertFalse(
    "no snapshot should not restore",
    Persistence.Restore(missing));
  Tests.EndTest();

  Tests.BeginTest("Save and restore complete snapshot");
  Tests.AssertTrue(
    "save succeeds",
    Persistence.Save(data));

  STGKGridInstanceData restored;
  bool restore_ok = Persistence.Restore(restored);
  Tests.AssertTrue(
    "restore succeeds",
    restore_ok);
  if(restore_ok)
  {
    Tests.AssertEqualString(
      "restored instance id",
      restored.instance_id,
      data.instance_id);
    Tests.AssertEqualString(
      "restored symbol",
      restored.symbol,
      data.symbol);
    Tests.AssertEqualLong(
      "restored magic",
      restored.magic_number,
      data.magic_number);
    Tests.AssertEqualInt(
      "restored mode",
      (int)restored.mode,
      (int)data.mode);
    Tests.AssertEqualInt(
      "restored state",
      (int)restored.state,
      (int)data.state);
    Tests.AssertEqualDouble(
      "restored anchor",
      restored.anchor_price,
      data.anchor_price,
      0.000001);
    Tests.AssertEqualDouble(
      "restored step",
      restored.grid_step_price,
      data.grid_step_price,
      0.000001);
    Tests.AssertEqualDouble(
      "restored lot",
      restored.fixed_lot,
      data.fixed_lot,
      0.000001);
    Tests.AssertEqualInt(
      "restored reset reason",
      (int)restored.reset_reason,
      (int)data.reset_reason);
    Tests.AssertEqualInt(
      "restored pending mode",
      (int)restored.pending_mode,
      (int)data.pending_mode);
    Tests.AssertEqualDouble(
      "restored pending step",
      restored.pending_grid_step_price,
      data.pending_grid_step_price,
      0.000001);
    Tests.AssertEqualLong(
      "restored pending magic",
      restored.pending_magic_number,
      data.pending_magic_number);
    Tests.AssertEqualInt(
      "restored level count",
      restored.level_count,
      data.level_count);
    Tests.AssertEqualLong(
      "restored state time",
      (long)restored.last_state_change,
      (long)data.last_state_change);
  }
  Tests.EndTest();

  Tests.BeginTest("Save rejects mismatched instance or symbol");
  STGKGridInstanceData wrong_identity;
  FillValidData(wrong_identity);
  wrong_identity.instance_id = "WRONG_INSTANCE";
  Tests.AssertFalse(
    "mismatched instance rejected",
    Persistence.Save(wrong_identity));

  STGKGridInstanceData wrong_symbol;
  FillValidData(wrong_symbol);
  wrong_symbol.symbol = "WRONG_SYMBOL";
  Tests.AssertFalse(
    "mismatched symbol rejected",
    Persistence.Save(wrong_symbol));
  Tests.EndTest();

  Tests.BeginTest("Level state save and restore");
  Tests.AssertTrue(
    "save READY level",
    Persistence.SaveLevelState(0, TGK_GRID_LEVEL_READY));
  Tests.AssertTrue(
    "save ACTIVE level",
    Persistence.SaveLevelState(1, TGK_GRID_LEVEL_ACTIVE));
  Tests.AssertTrue(
    "save WAIT_RETURN level",
    Persistence.SaveLevelState(2, TGK_GRID_LEVEL_WAIT_RETURN));

  ENUM_TGK_GRID_LEVEL_STATE level_state = TGK_GRID_LEVEL_READY;
  Tests.AssertTrue(
    "restore READY level",
    Persistence.RestoreLevelState(0, level_state));
  Tests.AssertEqualInt(
    "READY value",
    (int)level_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertTrue(
    "restore ACTIVE level",
    Persistence.RestoreLevelState(1, level_state));
  Tests.AssertEqualInt(
    "ACTIVE value",
    (int)level_state,
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertTrue(
    "restore WAIT_RETURN level",
    Persistence.RestoreLevelState(2, level_state));
  Tests.AssertEqualInt(
    "WAIT_RETURN value",
    (int)level_state,
    (int)TGK_GRID_LEVEL_WAIT_RETURN);
  Tests.AssertFalse(
    "missing level rejected",
    Persistence.RestoreLevelState(9, level_state));
  Tests.AssertFalse(
    "negative level index rejected",
    Persistence.RestoreLevelState(-1, level_state));
  Tests.AssertFalse(
    "invalid level state rejected",
    Persistence.SaveLevelState(4, (ENUM_TGK_GRID_LEVEL_STATE)99));
  Tests.EndTest();

  Tests.BeginTest("Restore rejects invalid persisted enum");
  GlobalVariableSet(TestKey("mode"), 99.0);
  STGKGridInstanceData invalid_mode;
  Tests.AssertFalse(
    "invalid mode rejected",
    Persistence.Restore(invalid_mode));
  Tests.EndTest();

  Tests.BeginTest("Delete removes snapshot and level states");
  Tests.AssertTrue(
    "delete state succeeds",
    Persistence.DeleteState(10));
  STGKGridInstanceData deleted;
  Tests.AssertFalse(
    "deleted snapshot cannot restore",
    Persistence.Restore(deleted));
  Tests.AssertFalse(
    "deleted level cannot restore",
    Persistence.RestoreLevelState(1, level_state));
  Tests.EndTest();

  // Defensive cleanup in case a future assertion is added after DeleteState.
  Persistence.DeleteState(10);
  GlobalVariablesFlush();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
