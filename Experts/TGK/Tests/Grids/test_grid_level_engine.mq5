#property strict
#property version "1.00"
#property description "Unit tests for pure Grid level calculation and touch/cross selection; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridLevelEngine.mqh>

CTGKTestRunner Tests;

int OnInit()
{
  Tests.BeginSuite("TGK Grid Level Engine");

  Tests.BeginTest("BUY levels are calculated below the actual Anchor");
  CTGKGridLevelEngine buy;
  Tests.AssertTrue(
    "valid BUY configuration initializes",
    buy.Initialize(
      TGK_GRID_MODE_BUY,
      2650.25,
      2.5,
      2630.0,
      2660.0,
      5));
  double price = 0.0;
  Tests.AssertTrue("BUY level 0 exists", buy.GetLevelPrice(0, price));
  Tests.AssertEqualDouble("BUY level 0", price, 2647.75, 0.000001);
  Tests.AssertTrue("BUY level 1 exists", buy.GetLevelPrice(1, price));
  Tests.AssertEqualDouble("BUY level 1", price, 2645.25, 0.000001);
  Tests.AssertTrue("BUY level 4 exists", buy.GetLevelPrice(4, price));
  Tests.AssertEqualDouble("BUY level 4", price, 2637.75, 0.000001);
  Tests.EndTest();

  Tests.BeginTest("SELL levels are calculated above the actual Anchor");
  CTGKGridLevelEngine sell;
  Tests.AssertTrue(
    "valid SELL configuration initializes",
    sell.Initialize(
      TGK_GRID_MODE_SELL,
      2650.25,
      2.5,
      2640.0,
      2660.0,
      5));
  Tests.AssertTrue("SELL level 0 exists", sell.GetLevelPrice(0, price));
  Tests.AssertEqualDouble("SELL level 0", price, 2652.75, 0.000001);
  Tests.AssertTrue("SELL level 1 exists", sell.GetLevelPrice(1, price));
  Tests.AssertEqualDouble("SELL level 1", price, 2655.25, 0.000001);
  Tests.EndTest();

  Tests.BeginTest("Bounds are hard filters and never shift calculated levels");
  CTGKGridLevelEngine bounded;
  Tests.AssertTrue(
    "configuration with bounds initializes",
    bounded.Initialize(
      TGK_GRID_MODE_BUY,
      2650.0,
      2.0,
      2646.0,
      2654.0,
      5));
  Tests.AssertTrue("level exactly at lower bound is included", bounded.GetLevelPrice(1, price));
  Tests.AssertEqualDouble("exact lower bound", price, 2646.0, 0.000001);
  Tests.AssertFalse("level below lower bound is excluded", bounded.GetLevelPrice(2, price));
  Tests.EndTest();

  Tests.BeginTest("Invalid configuration and level indexes are rejected");
  CTGKGridLevelEngine invalid;
  Tests.AssertFalse(
    "zero Anchor is rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      0.0,
      2.0,
      2600.0,
      2700.0,
      5));
  Tests.AssertFalse(
    "zero GridStep is rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      2650.0,
      0.0,
      2600.0,
      2700.0,
      5));
  Tests.AssertFalse(
    "reversed Bounds are rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      2650.0,
      2.0,
      2700.0,
      2600.0,
      5));
  Tests.AssertFalse(
    "zero level count is rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      2650.0,
      2.0,
      2600.0,
      2700.0,
      0));
  Tests.AssertFalse("negative index is rejected", buy.GetLevelPrice(-1, price));
  Tests.AssertFalse("index past configured count is rejected", buy.GetLevelPrice(5, price));
  Tests.EndTest();

  Tests.BeginTest("BUY uses Ask and detects touch or downward crossing");
  CTGKGridLevelEngine buy_touch;
  buy_touch.Initialize(
    TGK_GRID_MODE_BUY,
    2650.0,
    2.0,
    2640.0,
    2660.0,
    5);
  int selected = -1;
  double selected_price = 0.0;
  Tests.AssertTrue(
    "Ask touching level selects it",
    buy_touch.FindEntryLevel(
      2648.5,
      2648.0,
      2648.0,
      2647.9,
      selected,
      selected_price));
  Tests.AssertEqualInt("selected BUY level", selected, 0);
  Tests.AssertEqualDouble("selected BUY price", selected_price, 2648.0, 0.000001);

  selected = -1;
  Tests.AssertTrue(
    "Ask crossing downward selects level",
    buy_touch.FindEntryLevel(
      2648.5,
      2648.5,
      2647.5,
      2647.5,
      selected,
      selected_price));
  Tests.AssertEqualInt("crossed BUY level", selected, 0);
  Tests.EndTest();

  Tests.BeginTest("SELL uses Bid and detects touch or upward crossing");
  CTGKGridLevelEngine sell_touch;
  sell_touch.Initialize(
    TGK_GRID_MODE_SELL,
    2650.0,
    2.0,
    2640.0,
    2660.0,
    5);
  selected = -1;
  Tests.AssertTrue(
    "Bid touching level selects it",
    sell_touch.FindEntryLevel(
      2651.5,
      2652.0,
      2652.0,
      2652.1,
      selected,
      selected_price));
  Tests.AssertEqualInt("selected SELL level", selected, 0);
  Tests.AssertEqualDouble("selected SELL price", selected_price, 2652.0, 0.000001);

  selected = -1;
  Tests.AssertTrue(
    "Bid crossing upward selects level",
    sell_touch.FindEntryLevel(
      2651.5,
      2651.5,
      2652.5,
      2652.5,
      selected,
      selected_price));
  Tests.AssertEqualInt("crossed SELL level", selected, 0);
  Tests.EndTest();

  Tests.BeginTest("One price check selects only the first crossed eligible level");
  CTGKGridLevelEngine multi;
  multi.Initialize(
    TGK_GRID_MODE_BUY,
    2650.0,
    2.0,
    2640.0,
    2660.0,
    5);
  selected = -1;
  Tests.AssertTrue(
    "large downward move selects one level",
    multi.FindEntryLevel(
      2650.5,
      2650.5,
      2643.5,
      2643.5,
      selected,
      selected_price));
  Tests.AssertEqualInt("nearest crossed level from previous price", selected, 0);
  Tests.AssertEqualDouble("only first level is selected", selected_price, 2648.0, 0.000001);
  Tests.EndTest();

  Tests.BeginTest("Bounds exclude entries and price checks without a crossing select nothing");
  CTGKGridLevelEngine filtered;
  filtered.Initialize(
    TGK_GRID_MODE_BUY,
    2650.0,
    2.0,
    2649.0,
    2660.0,
    5);
  selected = -1;
  Tests.AssertFalse(
    "out-of-bounds calculated level is not selectable",
    filtered.FindEntryLevel(
      2649.0,
      2649.0,
      2647.5,
      2647.5,
      selected,
      selected_price));
  Tests.AssertEqualInt("no selection leaves index sentinel", selected, -1);

  Tests.AssertFalse(
    "no touch or crossing returns false",
    buy_touch.FindEntryLevel(
      2649.0,
      2649.0,
      2648.5,
      2648.5,
      selected,
      selected_price));
  Tests.EndTest();

  Tests.BeginTest("Non-READY levels cannot be selected again");
  CTGKGridLevelEngine states;
  states.Initialize(
    TGK_GRID_MODE_BUY,
    2650.0,
    2.0,
    2640.0,
    2660.0,
    5);
  Tests.AssertTrue(
    "mark level ACTIVE",
    states.SetLevelState(0, TGK_GRID_LEVEL_ACTIVE));
  selected = -1;
  Tests.AssertFalse(
    "ACTIVE level is not selected again",
    states.FindEntryLevel(
      2648.5,
      2648.5,
      2647.5,
      2647.5,
      selected,
      selected_price));
  Tests.AssertTrue(
    "mark level WAIT_RETURN",
    states.SetLevelState(0, TGK_GRID_LEVEL_WAIT_RETURN));
  Tests.AssertFalse(
    "WAIT_RETURN level is not selected as a new entry",
    states.FindEntryLevel(
      2648.5,
      2648.5,
      2647.5,
      2647.5,
      selected,
      selected_price));
  Tests.AssertTrue(
    "level can become READY after return handling",
    states.SetLevelState(0, TGK_GRID_LEVEL_READY));
  Tests.AssertTrue(
    "READY level can be selected again",
    states.FindEntryLevel(
      2648.5,
      2648.5,
      2647.5,
      2647.5,
      selected,
      selected_price));
  Tests.EndTest();

  Tests.BeginTest("Invalid state updates are rejected");
  Tests.AssertFalse("negative state index is rejected", states.SetLevelState(-1, TGK_GRID_LEVEL_ACTIVE));
  Tests.AssertFalse("state index past count is rejected", states.SetLevelState(5, TGK_GRID_LEVEL_ACTIVE));
  Tests.AssertFalse("invalid state value is rejected", states.SetLevelState(0, (ENUM_TGK_GRID_LEVEL_STATE)99));
  ENUM_TGK_GRID_LEVEL_STATE level_state = TGK_GRID_LEVEL_READY;
  Tests.AssertFalse("state index past count is rejected", states.GetLevelState(5, level_state));
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
