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

  Tests.BeginTest("Legacy WAIT_RETURN normalizes to READY and ACTIVE is never selected");
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
  Tests.AssertTrue("legacy WAIT_RETURN input is accepted", reentry.SetLevelState(2, TGK_GRID_LEVEL_WAIT_RETURN));
  Tests.AssertTrue("state readable after legacy input", reentry.GetLevelState(2, state));
  Tests.AssertEqualInt("legacy WAIT_RETURN is stored as READY", (int)state, (int)TGK_GRID_LEVEL_READY);
  Tests.AssertTrue(
    "normalized READY is eligible for re-entry",
    reentry.UpdatePrice(
      4005.0,
      4006.0,
      4004.0,
      4005.0,
      is_anchor,
      selected,
      selected_price));
  Tests.AssertEqualInt("normalized level selected", selected, 2);
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
    "close Anchor",
    anchor.RecordPositionClosed(
      true,
      -1,
      4004.0,
      4005.0));
  Tests.AssertEqualInt(
    "Anchor below current Ask becomes READY",
    (int)anchor.GetAnchorState(),
    (int)TGK_GRID_LEVEL_READY);
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

  Tests.BeginTest("Full Close next state is reason-free and equality is wrong-side");
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
    "close lower level below current Ask",
    close_states.RecordPositionClosed(
      false,
      0,
      4000.0,
      4001.0));
  Tests.AssertTrue("read lower level after close", close_states.GetLevelState(0, state));
  Tests.AssertEqualInt("BUY level below current Ask becomes READY", (int)state, (int)TGK_GRID_LEVEL_READY);

  Tests.AssertTrue(
    "close lower level at current entry price",
    close_states.RecordPositionClosed(
      false,
      0,
      3989.0,
      3990.0));
  Tests.AssertTrue("read lower level after equality close", close_states.GetLevelState(0, state));
  Tests.AssertEqualInt("BUY level equal to Ask becomes WAIT_ACTIVATION", (int)state, (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  CTGKGridLevelEngine sell_close_states;
  Tests.AssertTrue(
    "SELL close-state grid initializes",
    sell_close_states.Initialize(
      TGK_GRID_MODE_SELL,
      4000.0,
      5.0,
      3990.0,
      4010.0,
      4,
      4000.0,
      4001.0));
  Tests.AssertTrue(
    "close Level above current Bid",
    sell_close_states.RecordPositionClosed(
      false,
      0,
      3989.0,
      3990.0));
  Tests.AssertTrue("read SELL level after close", sell_close_states.GetLevelState(0, state));
  Tests.AssertEqualInt("SELL level above Bid becomes READY", (int)state, (int)TGK_GRID_LEVEL_READY);

  Tests.AssertTrue(
    "close SELL level at current Bid",
    sell_close_states.RecordPositionClosed(
      false,
      0,
      3990.0,
      3991.0));
  Tests.AssertTrue("read SELL level after equality close", sell_close_states.GetLevelState(0, state));
  Tests.AssertEqualInt("SELL level equal to Bid becomes WAIT_ACTIVATION", (int)state, (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
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

  Tests.BeginTest("Anchor activation is crossing-driven and reported for durable persistence");
  CTGKGridLevelEngine anchor_activation_buy;
  Tests.AssertTrue(
    "BUY Anchor activation grid initializes",
    anchor_activation_buy.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3990.0,
      4010.0,
      4,
      3999.0,
      4000.0));
  Tests.AssertTrue(
    "BUY Anchor close at current Ask waits activation",
    anchor_activation_buy.RecordPositionClosed(
      true,
      -1,
      3999.0,
      4000.0));
  Tests.AssertEqualInt(
    "CR01-01 BUY Anchor close leaves WAIT_ACTIVATION",
    (int)anchor_activation_buy.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertFalse(
    "close alone reports no activation",
    anchor_activation_buy.HasPendingAnchorActivation());

  anchor_activation_buy.UpdatePrice(
    4000.0,
    4001.0,
    3999.0,
    4000.0,
    is_anchor,
    selected,
    selected_price);
  Tests.AssertEqualInt(
    "CR01-04 non-qualifying BUY movement keeps WAIT_ACTIVATION",
    (int)anchor_activation_buy.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertFalse(
    "CR01-04 no activation is reported",
    anchor_activation_buy.HasPendingAnchorActivation());

  anchor_activation_buy.UpdatePrice(
    3998.0,
    3999.0,
    3999.0,
    4000.0,
    is_anchor,
    selected,
    selected_price);
  Tests.AssertEqualInt(
    "CR01-02 BUY upward crossing becomes READY",
    (int)anchor_activation_buy.GetAnchorState(),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertTrue(
    "CR01-02 activation is reported once for persistence",
    anchor_activation_buy.HasPendingAnchorActivation());
  Tests.AssertTrue(
    "durable confirmation clears the report",
    anchor_activation_buy.ConfirmAnchorActivation());
  Tests.AssertFalse(
    "confirmation cannot repeat",
    anchor_activation_buy.ConfirmAnchorActivation());

  CTGKGridLevelEngine anchor_activation_sell;
  Tests.AssertTrue(
    "SELL Anchor activation grid initializes",
    anchor_activation_sell.Initialize(
      TGK_GRID_MODE_SELL,
      4000.0,
      5.0,
      3990.0,
      4010.0,
      4,
      3999.0,
      4000.0));
  Tests.AssertTrue(
    "SELL Anchor close at current Bid waits activation",
    anchor_activation_sell.RecordPositionClosed(
      true,
      -1,
      4000.0,
      4001.0));
  Tests.AssertEqualInt(
    "SELL Anchor close leaves WAIT_ACTIVATION",
    (int)anchor_activation_sell.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  anchor_activation_sell.UpdatePrice(
    3999.0,
    4000.0,
    4000.0,
    4001.0,
    is_anchor,
    selected,
    selected_price);
  Tests.AssertEqualInt(
    "CR01-05 non-qualifying SELL movement keeps WAIT_ACTIVATION",
    (int)anchor_activation_sell.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertFalse(
    "CR01-05 no activation is reported",
    anchor_activation_sell.HasPendingAnchorActivation());

  anchor_activation_sell.UpdatePrice(
    4001.0,
    4002.0,
    4000.0,
    4001.0,
    is_anchor,
    selected,
    selected_price);
  Tests.AssertEqualInt(
    "CR01-03 SELL downward crossing becomes READY",
    (int)anchor_activation_sell.GetAnchorState(),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertTrue(
    "CR01-03 activation is reported for persistence",
    anchor_activation_sell.HasPendingAnchorActivation());
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
