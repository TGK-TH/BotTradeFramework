#property strict
#property version "1.00"
#property description "Unit tests for Grid State Machine transitions; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridStateMachine.mqh>

CTGKTestRunner Tests;
CTGKGridStateMachine StateMachine;

void SetGridData(STGKGridInstanceData &data)
{
  data.instance_id = "UT_STATE_MACHINE";
  data.symbol = "XAUUSD";
  data.magic_number = 710901;
  data.mode = TGK_GRID_MODE_BUY;
  data.state = TGK_GRID_STATE_WAIT_INITIAL_ENTRY;
  data.anchor_price = 0.0;
  data.grid_step_price = 2.5;
  data.fixed_lot = 0.01;
  data.reset_reason = TGK_GRID_RESET_NONE;
  data.pending_mode = TGK_GRID_MODE_BUY;
  data.pending_grid_step_price = 2.5;
  data.pending_magic_number = 710901;
  data.level_count = 0;
  data.last_state_change = 0;
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid State Machine");

  Tests.BeginTest("Initialize waits for the first fill when no anchor exists");
  STGKGridInstanceData initial_data;
  SetGridData(initial_data);
  Tests.AssertTrue(
    "initialize valid instance",
    StateMachine.Initialize(initial_data));
  Tests.AssertEqualInt(
    "initial state",
    (int)initial_data.state,
    (int)TGK_GRID_STATE_WAIT_INITIAL_ENTRY);
  Tests.AssertEqualDouble(
    "anchor remains unset",
    initial_data.anchor_price,
    0.0,
    0.000001);
  Tests.EndTest();

  Tests.BeginTest("First fill establishes the anchor using the actual fill price");
  STGKGridInstanceData fill_data;
  SetGridData(fill_data);
  StateMachine.Initialize(fill_data);
  Tests.AssertTrue(
    "accept initial fill",
    StateMachine.RecordInitialFill(fill_data, 2650.37));
  Tests.AssertEqualDouble(
    "anchor uses actual fill",
    fill_data.anchor_price,
    2650.37,
    0.000001);
  Tests.AssertEqualInt(
    "state becomes active",
    (int)fill_data.state,
    (int)TGK_GRID_STATE_ACTIVE);
  Tests.AssertFalse(
    "reject another initial fill while active",
    StateMachine.RecordInitialFill(fill_data, 2651.00));
  Tests.EndTest();

  Tests.BeginTest("Mode change waits for all old positions to close before rebuild");
  STGKGridInstanceData mode_data;
  SetGridData(mode_data);
  StateMachine.Initialize(mode_data);
  StateMachine.RecordInitialFill(mode_data, 2650.37);
  Tests.AssertTrue(
    "request mode change",
    StateMachine.RequestConfiguration(
      mode_data,
      TGK_GRID_MODE_SELL,
      2.5,
      710901));
  Tests.AssertEqualInt(
    "state enters close-old",
    (int)mode_data.state,
    (int)TGK_GRID_STATE_RESET_CLOSE_OLD);
  Tests.AssertEqualInt(
    "active mode remains unchanged while closing",
    (int)mode_data.mode,
    (int)TGK_GRID_MODE_BUY);
  Tests.AssertTrue(
    "still waiting while positions remain",
    StateMachine.AdvanceReset(mode_data, 2));
  Tests.AssertEqualInt(
    "close-old state retained",
    (int)mode_data.state,
    (int)TGK_GRID_STATE_RESET_CLOSE_OLD);
  Tests.AssertTrue(
    "zero remaining positions advances to rebuild",
    StateMachine.AdvanceReset(mode_data, 0));
  Tests.AssertEqualInt(
    "state enters rebuild",
    (int)mode_data.state,
    (int)TGK_GRID_STATE_RESET_REBUILD);
  Tests.AssertTrue(
    "rebuild applies pending mode",
    StateMachine.AdvanceReset(mode_data, 0));
  Tests.AssertEqualInt(
    "new mode applied",
    (int)mode_data.mode,
    (int)TGK_GRID_MODE_SELL);
  Tests.AssertEqualDouble(
    "mode change clears anchor",
    mode_data.anchor_price,
    0.0,
    0.000001);
  Tests.AssertEqualInt(
    "wait for new mode first fill",
    (int)mode_data.state,
    (int)TGK_GRID_STATE_WAIT_INITIAL_ENTRY);
  Tests.EndTest();

  Tests.BeginTest("Step change retains anchor and returns to active after reset");
  STGKGridInstanceData step_data;
  SetGridData(step_data);
  StateMachine.Initialize(step_data);
  StateMachine.RecordInitialFill(step_data, 2650.37);
  Tests.AssertTrue(
    "request step change",
    StateMachine.RequestConfiguration(
      step_data,
      TGK_GRID_MODE_BUY,
      1.25,
      710901));
  Tests.AssertEqualInt(
    "step change reason",
    (int)step_data.reset_reason,
    (int)TGK_GRID_RESET_STEP_CHANGED);
  Tests.AssertTrue(
    "close old positions",
    StateMachine.AdvanceReset(step_data, 0));
  Tests.AssertTrue(
    "rebuild with new step",
    StateMachine.AdvanceReset(step_data, 0));
  Tests.AssertEqualDouble(
    "new step applied",
    step_data.grid_step_price,
    1.25,
    0.000001);
  Tests.AssertEqualDouble(
    "previous anchor retained",
    step_data.anchor_price,
    2650.37,
    0.000001);
  Tests.AssertEqualInt(
    "state returns active",
    (int)step_data.state,
    (int)TGK_GRID_STATE_ACTIVE);
  Tests.EndTest();

  Tests.BeginTest("Invalid initial fill and invalid configuration are rejected");
  STGKGridInstanceData invalid_data;
  SetGridData(invalid_data);
  invalid_data.grid_step_price = 0.0;
  Tests.AssertFalse(
    "zero step rejected during initialization",
    StateMachine.Initialize(invalid_data));
  STGKGridInstanceData bad_config_data;
  SetGridData(bad_config_data);
  StateMachine.Initialize(bad_config_data);
  Tests.AssertFalse(
    "zero step rejected in requested configuration",
    StateMachine.RequestConfiguration(
      bad_config_data,
      TGK_GRID_MODE_BUY,
      0.0,
      710901));
  Tests.AssertEqualInt(
    "invalid configuration leaves state unchanged",
    (int)bad_config_data.state,
    (int)TGK_GRID_STATE_WAIT_INITIAL_ENTRY);
  STGKGridInstanceData bad_fill_data;
  SetGridData(bad_fill_data);
  StateMachine.Initialize(bad_fill_data);
  Tests.AssertFalse(
    "non-positive fill rejected",
    StateMachine.RecordInitialFill(bad_fill_data, 0.0));
  Tests.AssertEqualInt(
    "invalid fill leaves waiting state",
    (int)bad_fill_data.state,
    (int)TGK_GRID_STATE_WAIT_INITIAL_ENTRY);
  Tests.EndTest();

  Tests.BeginTest("Recovery error blocks state-changing operations");
  STGKGridInstanceData error_data;
  SetGridData(error_data);
  StateMachine.Initialize(error_data);
  StateMachine.SetRecoveryError(error_data);
  Tests.AssertEqualInt(
    "recovery error state",
    (int)error_data.state,
    (int)TGK_GRID_STATE_RECOVERY_ERROR);
  Tests.AssertFalse(
    "initial fill blocked in recovery error",
    StateMachine.RecordInitialFill(error_data, 2650.37));
  Tests.AssertFalse(
    "configuration blocked in recovery error",
    StateMachine.RequestConfiguration(
      error_data,
      TGK_GRID_MODE_SELL,
      2.5,
      710901));
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
