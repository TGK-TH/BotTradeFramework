#property strict
#property version "1.00"
#property description "Unit tests for Grid type contracts; no trading or terminal state."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridTypes.mqh>

CTGKTestRunner Tests;

int OnInit()
{
  Tests.BeginSuite("TGK Grid Types");

  Tests.BeginTest("Persisted enum numeric values remain stable");
  Tests.AssertEqualInt(
    "BUY mode",
    (int)TGK_GRID_MODE_BUY,
    0);
  Tests.AssertEqualInt(
    "SELL mode",
    (int)TGK_GRID_MODE_SELL,
    1);
  Tests.AssertEqualInt(
    "WAIT_INITIAL_ENTRY state",
    (int)TGK_GRID_STATE_WAIT_INITIAL_ENTRY,
    0);
  Tests.AssertEqualInt(
    "ACTIVE state",
    (int)TGK_GRID_STATE_ACTIVE,
    1);
  Tests.AssertEqualInt(
    "RESET_CLOSE_OLD state",
    (int)TGK_GRID_STATE_RESET_CLOSE_OLD,
    2);
  Tests.AssertEqualInt(
    "RESET_REBUILD state",
    (int)TGK_GRID_STATE_RESET_REBUILD,
    3);
  Tests.AssertEqualInt(
    "RECOVERY_ERROR state",
    (int)TGK_GRID_STATE_RECOVERY_ERROR,
    4);
  Tests.AssertEqualInt(
    "RESET_NONE reason",
    (int)TGK_GRID_RESET_NONE,
    0);
  Tests.AssertEqualInt(
    "MODE_CHANGED reason",
    (int)TGK_GRID_RESET_MODE_CHANGED,
    1);
  Tests.AssertEqualInt(
    "STEP_CHANGED reason",
    (int)TGK_GRID_RESET_STEP_CHANGED,
    2);
  Tests.AssertEqualInt(
    "MAGIC_CHANGED reason",
    (int)TGK_GRID_RESET_MAGIC_CHANGED,
    3);
  Tests.AssertEqualInt(
    "LEVEL_READY state",
    (int)TGK_GRID_LEVEL_READY,
    0);
  Tests.AssertEqualInt(
    "LEVEL_ACTIVE state",
    (int)TGK_GRID_LEVEL_ACTIVE,
    1);
  Tests.AssertEqualInt(
    "LEVEL_WAIT_RETURN state",
    (int)TGK_GRID_LEVEL_WAIT_RETURN,
    2);
  Tests.EndTest();

  Tests.BeginTest("Grid instance data fields retain assigned values");
  STGKGridInstanceData data;
  data.instance_id = "UT_INSTANCE";
  data.symbol = "XAUUSD";
  data.magic_number = 710123;
  data.mode = TGK_GRID_MODE_SELL;
  data.state = TGK_GRID_STATE_RESET_REBUILD;
  data.anchor_price = 2650.25;
  data.grid_step_price = 2.5;
  data.fixed_lot = 0.03;
  data.reset_reason = TGK_GRID_RESET_STEP_CHANGED;
  data.pending_mode = TGK_GRID_MODE_BUY;
  data.pending_grid_step_price = 1.25;
  data.pending_magic_number = 710124;
  data.level_count = 7;
  data.last_state_change = (datetime)1760000000;

  Tests.AssertEqualString(
    "instance_id",
    data.instance_id,
    "UT_INSTANCE");
  Tests.AssertEqualString(
    "symbol",
    data.symbol,
    "XAUUSD");
  Tests.AssertEqualLong(
    "magic_number",
    data.magic_number,
    710123);
  Tests.AssertEqualInt(
    "mode",
    (int)data.mode,
    (int)TGK_GRID_MODE_SELL);
  Tests.AssertEqualInt(
    "state",
    (int)data.state,
    (int)TGK_GRID_STATE_RESET_REBUILD);
  Tests.AssertEqualDouble(
    "anchor_price",
    data.anchor_price,
    2650.25,
    0.000001);
  Tests.AssertEqualDouble(
    "grid_step_price",
    data.grid_step_price,
    2.5,
    0.000001);
  Tests.AssertEqualDouble(
    "fixed_lot",
    data.fixed_lot,
    0.03,
    0.000001);
  Tests.AssertEqualInt(
    "reset_reason",
    (int)data.reset_reason,
    (int)TGK_GRID_RESET_STEP_CHANGED);
  Tests.AssertEqualInt(
    "pending_mode",
    (int)data.pending_mode,
    (int)TGK_GRID_MODE_BUY);
  Tests.AssertEqualDouble(
    "pending_grid_step_price",
    data.pending_grid_step_price,
    1.25,
    0.000001);
  Tests.AssertEqualLong(
    "pending_magic_number",
    data.pending_magic_number,
    710124);
  Tests.AssertEqualInt(
    "level_count",
    data.level_count,
    7);
  Tests.AssertEqualLong(
    "last_state_change",
    (long)data.last_state_change,
    1760000000);
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
