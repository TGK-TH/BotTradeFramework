#property strict
#property version "1.00"
#property description "Unit tests for Two-sided Grid levels, state transitions and candidate selection; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridLevelEngine.mqh>

CTGKTestRunner Tests;

int OnInit()
{
  Tests.BeginSuite("TGK Grid Level Engine");

  Tests.BeginTest("Two-sided levels use Anchor and Step with hard Bounds");
  CTGKGridLevelEngine bounded;
  Tests.AssertTrue(
    "Two-sided configuration initializes",
    bounded.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3992.0,
      4012.0,
      3,
      3999.0,
      4000.0));
  Tests.AssertEqualInt("three ordinary levels fit inside Bounds", bounded.LevelCount(), 3);

  double price = 0.0;
  Tests.AssertTrue("lowest level exists", bounded.GetLevelPrice(0, price));
  Tests.AssertEqualDouble("lowest level is 3995", price, 3995.0, 0.000001);
  Tests.AssertTrue("middle level exists", bounded.GetLevelPrice(1, price));
  Tests.AssertEqualDouble("middle level is 4005", price, 4005.0, 0.000001);
  Tests.AssertTrue("highest level exists", bounded.GetLevelPrice(2, price));
  Tests.AssertEqualDouble("highest level is 4010", price, 4010.0, 0.000001);
  Tests.AssertFalse("Anchor is not duplicated as a Grid Level", bounded.GetLevelPrice(3, price));
  Tests.EndTest();

  Tests.BeginTest("Initial states use Current Price and Anchor is ACTIVE");
  CTGKGridLevelEngine buy_initial;
  Tests.AssertTrue(
    "BUY initializes",
    buy_initial.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3990.0,
      4010.0,
      4,
      3999.0,
      4000.0));
  ENUM_TGK_GRID_LEVEL_STATE state = TGK_GRID_LEVEL_READY;
  Tests.AssertTrue("BUY lower level state available", buy_initial.GetLevelState(0, state));
  Tests.AssertEqualInt("BUY lower level starts READY", (int)state, (int)TGK_GRID_LEVEL_READY);
  Tests.AssertTrue("BUY upper level state available", buy_initial.GetLevelState(2, state));
  Tests.AssertEqualInt("BUY upper level starts WAIT_ACTIVATION", (int)state, (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertEqualInt(
    "BUY Anchor starts ACTIVE",
    (int)buy_initial.GetAnchorState(),
    (int)TGK_GRID_LEVEL_ACTIVE);

  CTGKGridLevelEngine sell_initial;
  Tests.AssertTrue(
    "SELL initializes",
    sell_initial.Initialize(
      TGK_GRID_MODE_SELL,
      4000.0,
      5.0,
      3990.0,
      4010.0,
      4,
      4000.0,
      4001.0));
  Tests.AssertTrue("SELL lower level state available", sell_initial.GetLevelState(0, state));
  Tests.AssertEqualInt("SELL lower level starts WAIT_ACTIVATION", (int)state, (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertTrue("SELL upper level state available", sell_initial.GetLevelState(2, state));
  Tests.AssertEqualInt("SELL upper level starts READY", (int)state, (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("BUY WAIT_ACTIVATION becomes READY only on upward crossing");
  CTGKGridLevelEngine buy_activation;
  buy_activation.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3990.0,
    4010.0,
    4,
    4004.0,
    4005.0);
  bool is_anchor = false;
  int selected = -1;
  double selected_price = 0.0;
  Tests.AssertFalse(
    "upward activation does not create a BUY entry",
    buy_activation.UpdatePrice(
      4003.0,
      4004.0,
      4004.0,
      4005.0,
      is_anchor,
      selected,
      selected_price));
  Tests.AssertTrue("BUY level state readable after activation", buy_activation.GetLevelState(2, state));
  Tests.AssertEqualInt("BUY upper level becomes READY", (int)state, (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("SELL WAIT_ACTIVATION becomes READY only on downward crossing");
  CTGKGridLevelEngine sell_activation;
  sell_activation.Initialize(
    TGK_GRID_MODE_SELL,
    4000.0,
    5.0,
    3990.0,
    4010.0,
    4,
    3995.0,
    3996.0);
  Tests.AssertFalse(
    "downward activation does not create a SELL entry",
    sell_activation.UpdatePrice(
      3996.0,
      3997.0,
      3995.0,
      3996.0,
      is_anchor,
      selected,
      selected_price));
  Tests.AssertTrue("SELL lower level state readable", sell_activation.GetLevelState(1, state));
  Tests.AssertEqualInt("SELL lower level becomes READY", (int)state, (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("BUY selects the lowest crossed READY level");
  CTGKGridLevelEngine buy_selection;
  buy_selection.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3990.0,
    4010.0,
    4,
    4010.0,
    4011.0);
  Tests.AssertTrue("mark an unselected level WAIT_RETURN", buy_selection.SetLevelState(2, TGK_GRID_LEVEL_WAIT_RETURN));
  Tests.AssertTrue(
    "downward gap returns one candidate",
    buy_selection.UpdatePrice(
      4010.0,
      4011.0,
      3989.0,
      3990.0,
      is_anchor,
      selected,
      selected_price));
  Tests.AssertFalse("selected candidate is not Anchor", is_anchor);
  Tests.AssertEqualInt("candidate index is lowest-price level", selected, 0);
  Tests.AssertEqualDouble("BUY selects 3990", selected_price, 3990.0, 0.000001);
  Tests.AssertTrue("unselected higher level state readable", buy_selection.GetLevelState(1, state));
  Tests.AssertEqualInt("unselected crossed BUY level becomes WAIT_ACTIVATION", (int)state, (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertTrue("unselected WAIT_RETURN state readable", buy_selection.GetLevelState(2, state));
  Tests.AssertEqualInt("unselected crossed WAIT_RETURN becomes WAIT_ACTIVATION", (int)state, (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.EndTest();

  Tests.BeginTest("SELL selects the highest crossed READY level");
  CTGKGridLevelEngine sell_selection;
  sell_selection.Initialize(
    TGK_GRID_MODE_SELL,
    4000.0,
    5.0,
    3990.0,
    4010.0,
    4,
    3989.0,
    3990.0);
  Tests.AssertTrue(
    "upward gap returns one candidate",
    sell_selection.UpdatePrice(
      3989.0,
      3990.0,
      4010.0,
      4011.0,
      is_anchor,
      selected,
      selected_price));
  Tests.AssertFalse("selected candidate is not Anchor", is_anchor);
  Tests.AssertEqualInt("candidate index is highest-price level", selected, 3);
  Tests.AssertEqualDouble("SELL selects 4010", selected_price, 4010.0, 0.000001);
  Tests.AssertTrue("unselected lower level state readable", sell_selection.GetLevelState(1, state));
  Tests.AssertEqualInt("unselected crossed SELL level becomes WAIT_ACTIVATION", (int)state, (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.EndTest();

  Tests.BeginTest("WAIT_RETURN can be selected and ACTIVE cannot");
  CTGKGridLevelEngine reentry;
  reentry.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3990.0,
    4010.0,
    4,
    4010.0,
    4011.0);
  Tests.AssertTrue("set level WAIT_RETURN", reentry.SetLevelState(2, TGK_GRID_LEVEL_WAIT_RETURN));
  Tests.AssertTrue(
    "WAIT_RETURN is eligible for re-entry",
    reentry.UpdatePrice(
      4005.0,
      4006.0,
      4004.0,
      4005.0,
      is_anchor,
      selected,
      selected_price));
  Tests.AssertEqualInt("WAIT_RETURN level selected", selected, 2);
  Tests.AssertTrue("set another level ACTIVE", reentry.SetLevelState(0, TGK_GRID_LEVEL_ACTIVE));
  Tests.AssertTrue("disable lower READY level", reentry.SetLevelState(1, TGK_GRID_LEVEL_WAIT_ACTIVATION));
  Tests.AssertTrue("disable upper READY level", reentry.SetLevelState(3, TGK_GRID_LEVEL_WAIT_ACTIVATION));
  Tests.AssertFalse(
    "ACTIVE level is not selected",
    reentry.UpdatePrice(
      3995.0,
      3996.0,
      3994.0,
      3995.0,
      is_anchor,
      selected,
      selected_price));
  Tests.EndTest();

  Tests.BeginTest("Anchor is a separate candidate and supports re-entry");
  CTGKGridLevelEngine anchor;
  anchor.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3990.0,
    4010.0,
    4,
    4005.0,
    4006.0);
  Tests.AssertTrue(
    "close Anchor with TP",
    anchor.RecordPositionClosed(
      true,
      -1,
      true,
      4004.0,
      4005.0));
  Tests.AssertEqualInt(
    "Anchor becomes WAIT_RETURN",
    (int)anchor.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_RETURN);
  Tests.AssertTrue(
    "Anchor return creates candidate",
    anchor.UpdatePrice(
      4001.0,
      4002.0,
      3999.0,
      4000.0,
      is_anchor,
      selected,
      selected_price));
  Tests.AssertTrue("candidate identifies Anchor", is_anchor);
  Tests.AssertEqualDouble("Anchor candidate price", selected_price, 4000.0, 0.000001);
  Tests.AssertTrue("confirm Anchor entry", anchor.RecordEntryConfirmed(true, -1));
  Tests.AssertEqualInt(
    "confirmed Anchor becomes ACTIVE",
    (int)anchor.GetAnchorState(),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.EndTest();

  Tests.BeginTest("TP and non-TP close outcomes use Current Price");
  CTGKGridLevelEngine close_states;
  close_states.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3990.0,
    4010.0,
    4,
    3999.0,
    4000.0);
  Tests.AssertTrue(
    "close lower level by TP above Entry",
    close_states.RecordPositionClosed(
      false,
      0,
      true,
      4000.0,
      4001.0));
  Tests.AssertTrue("read lower level after TP", close_states.GetLevelState(0, state));
  Tests.AssertEqualInt("TP below current BUY price becomes WAIT_RETURN", (int)state, (int)TGK_GRID_LEVEL_WAIT_RETURN);

  Tests.AssertTrue(
    "close lower level by SL below Entry",
    close_states.RecordPositionClosed(
      false,
      0,
      false,
      3989.0,
      3990.0));
  Tests.AssertTrue("read lower level after SL", close_states.GetLevelState(0, state));
  Tests.AssertEqualInt("non-TP below current BUY price becomes WAIT_ACTIVATION", (int)state, (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  Tests.AssertTrue(
    "close lower level by manual close above Entry",
    close_states.RecordPositionClosed(
      false,
      0,
      false,
      3995.0,
      3996.0));
  Tests.AssertTrue("read lower level after manual close", close_states.GetLevelState(0, state));
  Tests.AssertEqualInt("non-TP above current BUY price becomes READY", (int)state, (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("Failed candidate is re-armed from Current Price");
  CTGKGridLevelEngine retry;
  retry.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3990.0,
    4010.0,
    4,
    3994.0,
    3995.0);
  Tests.AssertTrue(
    "failed lower candidate is recorded",
    retry.RecordEntryFailed(
      false,
      0,
      3989.0,
      3990.0));
  Tests.AssertTrue("failed lower level state readable", retry.GetLevelState(0, state));
  Tests.AssertEqualInt("failed BUY level now above price waits activation", (int)state, (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.EndTest();

  Tests.BeginTest("Touch equality triggers once and stationary price does not retrigger");
  CTGKGridLevelEngine equality;
  equality.Initialize(
    TGK_GRID_MODE_BUY,
    4005.0,
    5.0,
    3995.0,
    4015.0,
    4,
    4004.0,
    4005.0);
  Tests.AssertTrue(
    "current Ask exactly at READY level triggers",
    equality.UpdatePrice(
      4000.0,
      4001.0,
      3999.0,
      4000.0,
      is_anchor,
      selected,
      selected_price));
  Tests.AssertFalse(
    "same price does not retrigger on next check",
    equality.UpdatePrice(
      3999.0,
      4000.0,
      3999.0,
      4000.0,
      is_anchor,
      selected,
      selected_price));
  Tests.EndTest();

  Tests.BeginTest("Invalid configuration and invalid level indexes are rejected");
  CTGKGridLevelEngine invalid;
  Tests.AssertFalse(
    "zero Anchor is rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      0.0,
      5.0,
      3900.0,
      4100.0,
      40,
      3999.0,
      4000.0));
  Tests.AssertFalse(
    "zero Step is rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      0.0,
      3900.0,
      4100.0,
      40,
      3999.0,
      4000.0));
  Tests.AssertFalse(
    "mismatched total level_count is rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3990.0,
      4010.0,
      5,
      3999.0,
      4000.0));
  Tests.AssertFalse("invalid index is rejected", bounded.GetLevelPrice(-1, price));
  Tests.AssertFalse("index past count is rejected", bounded.GetLevelPrice(3, price));
  Tests.AssertFalse("invalid state is rejected", bounded.SetLevelState(0, (ENUM_TGK_GRID_LEVEL_STATE)99));
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
