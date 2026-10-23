#property strict
#property version "1.00"
#property description "Two-run chart restart persistence test; no trade operations."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridIdentity.mqh>
#include <BotTrade/Grid/GridPersistence.mqh>

input string TestSlot = "R1";

CTGKTestRunner Tests;
CTGKGridPersistence Persistence;

string TestInstanceId;
string TestPrefix;

string ControlKey(string field)
{
  return StringFormat(
    "TGRST.%I64d.%s.%s",
    AccountInfoInteger(ACCOUNT_LOGIN),
    TestSlot,
    field);
}

string PersistenceTestId()
{
  return "RT" + TestSlot;
}

long HashString(string value)
{
  long hash = 5381;

  for(int i = 0; i < StringLen(value); i++)
    hash = (hash * 33 + StringGetCharacter(value, i)) % 2147483647;

  return hash;
}

bool WriteControl(string field, double value)
{
  return GlobalVariableSet(ControlKey(field), value) != 0;
}

bool ReadControl(string field, double &value)
{
  string key = ControlKey(field);
  if(!GlobalVariableCheck(key))
    return false;

  value = GlobalVariableGet(key);
  return true;
}

void CleanupTestState()
{
  Persistence.DeleteState(10);

  GlobalVariableDel(ControlKey("stage"));
  GlobalVariableDel(ControlKey("chart"));
  GlobalVariableDel(ControlKey("id_hash"));
  GlobalVariableDel(ControlKey("magic"));
  GlobalVariablesFlush();
}

void FillRestartData(
  STGKGridInstanceData &data,
  CTGKGridIdentity &identity)
{
  data.instance_id = TestInstanceId;
  data.symbol = _Symbol;
  data.magic_number = identity.MagicNumber();
  data.mode = TGK_GRID_MODE_SELL;
  data.state = TGK_GRID_STATE_ACTIVE;
  data.anchor_price = 2651.75;
  data.grid_step_price = 2.25;
  data.fixed_lot = 0.03;
  data.reset_reason = TGK_GRID_RESET_NONE;
  data.pending_mode = TGK_GRID_MODE_SELL;
  data.pending_grid_step_price = 0.0;
  data.pending_magic_number = 0;
  data.level_count = 3;
  data.last_state_change = (datetime)1760000000;
}

int OnInit()
{
  bool valid_slot = StringLen(TestSlot) >= 1 && StringLen(TestSlot) <= 6;
  for(int i = 0; i < StringLen(TestSlot) && valid_slot; i++)
  {
    ushort character = StringGetCharacter(TestSlot, i);
    valid_slot =
      (character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9');
  }

  if(!valid_slot)
  {
    Print("FATAL: TestSlot must contain 1 to 6 alphanumeric characters.");
    return INIT_PARAMETERS_INCORRECT;
  }

  TestInstanceId = PersistenceTestId();

  if(!Persistence.Initialize(
    _Symbol,
    TestInstanceId))
  {
    Print("FATAL: restart persistence test initialization failed.");
    return INIT_FAILED;
  }

  CTGKGridIdentity identity;
  if(!identity.Initialize(
    ChartID(),
    _Symbol))
  {
    Print("FATAL: Grid identity initialization failed.");
    return INIT_FAILED;
  }

  double stage_value;
  if(!ReadControl("stage", stage_value) || (int)stage_value != 1)
  {
    // First run: create a dedicated fixture. The second run must occur after
    // closing and reopening this same saved chart, then attaching this EA again.
    CleanupTestState();

    STGKGridInstanceData data;
    FillRestartData(data, identity);

    bool saved = Persistence.Save(data);
    bool levels_saved =
      Persistence.SaveLevelState(0, TGK_GRID_LEVEL_READY) &&
      Persistence.SaveLevelState(1, TGK_GRID_LEVEL_ACTIVE) &&
      Persistence.SaveLevelState(2, TGK_GRID_LEVEL_WAIT_RETURN);

    bool controls_saved =
      WriteControl("chart", (double)ChartID()) &&
      WriteControl("id_hash", (double)HashString(identity.InstanceId())) &&
      WriteControl("magic", (double)identity.MagicNumber()) &&
      WriteControl("stage", 1.0);

    GlobalVariablesFlush();

    if(!saved || !levels_saved || !controls_saved)
    {
      CleanupTestState();
      Print("FINAL RESULT: FAIL - could not create restart fixture.");
      return INIT_FAILED;
    }

    Print("==================================================");
    Print("TGK Grid Restart Persistence: setup complete.");
    Print("Now close this chart, reopen the same saved chart/profile,");
    Print("then attach this same test EA with the same TestSlot.");
    Print("Do not simply remove and reattach the EA without closing the chart.");
    Print("The second run will validate identity, snapshot, and level states.");
    Print("==================================================");
    return INIT_SUCCEEDED;
  }

  Tests.BeginSuite("TGK Grid Restart Persistence");

  double saved_chart_value;
  double saved_hash_value;
  double saved_magic_value;
  bool controls_ok =
    ReadControl("chart", saved_chart_value) &&
    ReadControl("id_hash", saved_hash_value) &&
    ReadControl("magic", saved_magic_value);

  Tests.BeginTest("Chart was reopened and identity was restored");
  Tests.AssertTrue(
    "restart control values exist",
    controls_ok);

  if(controls_ok)
  {
    // MT5 may reuse a chart ID when restoring a saved profile, so this is
    // diagnostic information rather than a persistence requirement.
    PrintFormat(
      "INFO: saved ChartID=%I64d, current ChartID=%I64d",
      (long)saved_chart_value,
      ChartID());
    Tests.AssertEqualLong(
      "instance id hash restored",
      HashString(identity.InstanceId()),
      (long)saved_hash_value);
    Tests.AssertEqualLong(
      "Magic Number restored",
      identity.MagicNumber(),
      (long)saved_magic_value);
  }
  Tests.EndTest();

  Tests.BeginTest("Grid snapshot and level states survive chart restart");
  STGKGridInstanceData restored;
  bool restore_ok = Persistence.Restore(restored);
  Tests.AssertTrue(
    "snapshot restores",
    restore_ok);

  if(restore_ok)
  {
    Tests.AssertEqualString(
      "instance id",
      restored.instance_id,
      TestInstanceId);
    Tests.AssertEqualString(
      "symbol",
      restored.symbol,
      _Symbol);
    Tests.AssertEqualLong(
      "Magic Number in snapshot",
      restored.magic_number,
      identity.MagicNumber());
    Tests.AssertEqualInt(
      "mode",
      (int)restored.mode,
      (int)TGK_GRID_MODE_SELL);
    Tests.AssertEqualInt(
      "state",
      (int)restored.state,
      (int)TGK_GRID_STATE_ACTIVE);
    Tests.AssertEqualDouble(
      "Anchor",
      restored.anchor_price,
      2651.75,
      0.000001);
    Tests.AssertEqualDouble(
      "Grid Step",
      restored.grid_step_price,
      2.25,
      0.000001);
    Tests.AssertEqualDouble(
      "Fixed Lot",
      restored.fixed_lot,
      0.03,
      0.000001);
    Tests.AssertEqualInt(
      "level count",
      restored.level_count,
      3);

    ENUM_TGK_GRID_LEVEL_STATE level_state = TGK_GRID_LEVEL_READY;
    Tests.AssertTrue(
      "level 0 restores",
      Persistence.RestoreLevelState(0, level_state));
    Tests.AssertEqualInt(
      "level 0 state",
      (int)level_state,
      (int)TGK_GRID_LEVEL_READY);

    Tests.AssertTrue(
      "level 1 restores",
      Persistence.RestoreLevelState(1, level_state));
    Tests.AssertEqualInt(
      "level 1 state",
      (int)level_state,
      (int)TGK_GRID_LEVEL_ACTIVE);

    Tests.AssertTrue(
      "level 2 restores",
      Persistence.RestoreLevelState(2, level_state));
    Tests.AssertEqualInt(
      "level 2 state",
      (int)level_state,
      (int)TGK_GRID_LEVEL_WAIT_RETURN);
  }
  Tests.EndTest();

  bool passed = Tests.AllPassed();
  Tests.EndSuite();

  CleanupTestState();

  if(!passed)
    Print("Restart test failed. Test fixture was cleaned; start again from run 1.");

  return INIT_SUCCEEDED;
}

void OnTick()
{
}
