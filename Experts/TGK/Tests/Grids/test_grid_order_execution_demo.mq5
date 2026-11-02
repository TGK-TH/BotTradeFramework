#property strict
#property version   "1.00"
#property description "Demo-only integration test for TGK Grid close execution."

#include <Trade/Trade.mqh>
#include <BotTrade/Grid/GridIdentity.mqh>
#include <BotTrade/Grid/GridRuntimeOrchestrator.mqh>
#include <BotTrade/Grid/GridOrderExecutionAdapter.mqh>

input bool   EnableDemoTest = false;
input double TestLot = 0.01;
input double TestGridStep = 1.0;
input ulong  TestDeviationPoints = 30;

enum ENUM_TGK_GRID_DEMO_STAGE
{
  TGK_DEMO_IDLE = 0,
  TGK_DEMO_CLOSING_OWNED,
  TGK_DEMO_WAIT_FOREIGN_CLEANUP,
  TGK_DEMO_VERIFYING_CLEANUP,
  TGK_DEMO_COMPLETE,
  TGK_DEMO_FAILED
};

CTGKGridIdentity Identity;
CTGKGridRuntimeOrchestrator Runtime;
CTGKGridOrderExecutionAdapter Adapter;
CTrade Trade;
CTrade CleanupTrade;

ENUM_TGK_GRID_DEMO_STAGE Stage = TGK_DEMO_IDLE;
long ForeignMagic = 0;
ulong ForeignTicket = 0;
bool Started = false;
string StartButtonName = "TGK_DEMO_START";
string CleanupButtonName = "TGK_DEMO_CLEANUP";

bool IsAcceptedTradeResult(CTrade &trader)
{
  uint retcode = trader.ResultRetcode();
  return retcode == TRADE_RETCODE_DONE ||
         retcode == TRADE_RETCODE_DONE_PARTIAL ||
         retcode == TRADE_RETCODE_PLACED;
}

bool IsTradeEnvironmentAllowed()
{
  if(!EnableDemoTest)
  {
    Print("TGK Demo Integration: EnableDemoTest must be true.");
    return false;
  }

  if((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) !=
     ACCOUNT_TRADE_MODE_DEMO)
  {
    Print("TGK Demo Integration: real and contest accounts are rejected.");
    return false;
  }

  if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) !=
     ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
  {
    Print("TGK Demo Integration: a Hedging account is required.");
    return false;
  }

  if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
     !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
     !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
  {
    Print("TGK Demo Integration: trading is not allowed by terminal, EA, or account.");
    return false;
  }

  return true;
}

bool IsValidTestVolume()
{
  double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

  if(TestLot < minimum || TestLot > maximum || step <= 0.0)
    return false;

  double steps = (TestLot - minimum) / step;
  return MathAbs(steps - MathRound(steps)) <= 0.0000001;
}

bool IsMagicInUse(long magic_number)
{
  for(int index = PositionsTotal() - 1; index >= 0; index--)
  {
    ulong ticket = PositionGetTicket(index);
    if(ticket == 0 || !PositionSelectByTicket(ticket))
      return true;

    if(PositionGetInteger(POSITION_MAGIC) == magic_number)
      return true;
  }

  for(int index = OrdersTotal() - 1; index >= 0; index--)
  {
    ulong ticket = OrderGetTicket(index);
    if(ticket == 0)
      return true;

    if(OrderGetInteger(ORDER_MAGIC) == magic_number)
      return true;
  }

  return false;
}

int CountPositions(string symbol, long magic_number)
{
  int count = 0;

  for(int index = PositionsTotal() - 1; index >= 0; index--)
  {
    ulong ticket = PositionGetTicket(index);
    if(ticket == 0 || !PositionSelectByTicket(ticket))
      return -1;

    if(PositionGetString(POSITION_SYMBOL) == symbol &&
       PositionGetInteger(POSITION_MAGIC) == magic_number)
      count++;
  }

  return count;
}

bool FindSinglePosition(
  string symbol,
  long magic_number,
  ulong &ticket
)
{
  ticket = 0;
  int count = 0;

  for(int index = PositionsTotal() - 1; index >= 0; index--)
  {
    ulong current_ticket = PositionGetTicket(index);
    if(current_ticket == 0 || !PositionSelectByTicket(current_ticket))
      return false;

    if(PositionGetString(POSITION_SYMBOL) != symbol ||
       PositionGetInteger(POSITION_MAGIC) != magic_number)
      continue;

    ticket = current_ticket;
    count++;
  }

  return count == 1 && ticket > 0;
}

bool OpenBuy(long magic_number, string comment)
{
  Trade.SetExpertMagicNumber((ulong)magic_number);
  Trade.SetDeviationInPoints(TestDeviationPoints);

  bool sent = Trade.Buy(TestLot, _Symbol, 0.0, 0.0, 0.0, comment);
  if(!sent || !IsAcceptedTradeResult(Trade))
  {
    PrintFormat(
      "TGK Demo Integration: BUY failed magic=%I64d retcode=%u (%s)",
      magic_number,
      Trade.ResultRetcode(),
      Trade.ResultRetcodeDescription());
    return false;
  }

  return true;
}

void CreateButton(string name, string caption, int y, color background)
{
  if(ObjectFind(0, name) >= 0)
    ObjectDelete(0, name);

  if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
  {
    PrintFormat("TGK Demo Integration: cannot create button %s.", name);
    return;
  }

  ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
  ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 12);
  ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
  ObjectSetInteger(0, name, OBJPROP_XSIZE, 220);
  ObjectSetInteger(0, name, OBJPROP_YSIZE, 30);
  ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
  ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
  ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  ObjectSetString(0, name, OBJPROP_TEXT, caption);
}

void FailTest(string reason)
{
  Stage = TGK_DEMO_FAILED;
  int owned_count = CountPositions(_Symbol, Identity.MagicNumber());
  int foreign_count = ForeignMagic > 0
    ? CountPositions(_Symbol, ForeignMagic)
    : 0;

  PrintFormat(
    "TGK DEMO INTEGRATION: FAIL — %s Remaining positions: owned=%d magic=%I64d, foreign=%d magic=%I64d ticket=%I64u. Inspect and close only these test positions manually.",
    reason,
    owned_count,
    Identity.MagicNumber(),
    foreign_count,
    ForeignMagic,
    ForeignTicket);
  Comment("TGK Grid Demo Integration: FAILED\n", reason,
          "\nInspect remaining test positions before removing this EA.");
  ObjectDelete(0, StartButtonName);
  ObjectDelete(0, CleanupButtonName);
}

void CleanupTestPersistence()
{
  CTGKGridPersistence persistence;
  if(persistence.Initialize(_Symbol, Identity.InstanceId()))
  {
    persistence.DeleteState(10);
    GlobalVariablesFlush();
  }
}

bool PrepareForeignMagic()
{
  ForeignMagic = Identity.MagicNumber() + 100000000;
  if(ForeignMagic <= Identity.MagicNumber() ||
     ForeignMagic > 2000000000 ||
     IsMagicInUse(ForeignMagic))
  {
    Print("TGK Demo Integration: generated Foreign Magic Number is invalid or already in use.");
    return false;
  }

  return true;
}

bool StartIntegrationTest()
{
  if(Started || Stage != TGK_DEMO_IDLE)
    return false;

  if(!IsTradeEnvironmentAllowed() || !IsValidTestVolume())
  {
    FailTest("Safety gate or TestLot validation failed.");
    return false;
  }

  if(!PrepareForeignMagic())
  {
    FailTest("Could not reserve a collision-free Foreign Magic Number.");
    return false;
  }

  if(!Runtime.InitializeLive(
    Identity.InstanceId(),
    _Symbol,
    Identity.MagicNumber(),
    TGK_GRID_MODE_BUY,
    TestGridStep,
    TestLot))
  {
    FailTest("Runtime initialization failed.");
    return false;
  }

  if(Runtime.UpdateLive() != TGK_GRID_RUNTIME_WAIT_INITIAL_ENTRY)
  {
    FailTest("Test Instance is not clean and waiting for its first entry; no seed orders were sent.");
    return false;
  }

  if(!Adapter.Initialize(_Symbol, Identity.MagicNumber()))
  {
    FailTest("Execution Adapter initialization failed.");
    return false;
  }

  // Seed two positions owned by this Grid Instance.
  if(!OpenBuy(Identity.MagicNumber(), "TGK-DEMO-OWNED-1"))
  {
    FailTest("Could not open first owned test position.");
    return false;
  }

  double first_fill = Trade.ResultPrice();
  if(first_fill <= 0.0 || !Runtime.RecordInitialFill(first_fill))
  {
    FailTest("First owned fill could not be recorded by Runtime.");
    return false;
  }

  if(!OpenBuy(Identity.MagicNumber(), "TGK-DEMO-OWNED-2"))
  {
    FailTest("Could not open second owned test position.");
    return false;
  }

  // Seed one Foreign Position under a distinct, collision-checked Magic Number.
  if(!OpenBuy(ForeignMagic, "TGK-DEMO-FOREIGN"))
  {
    FailTest("Could not open Foreign test position.");
    return false;
  }

  if(CountPositions(_Symbol, Identity.MagicNumber()) != 2 ||
     !FindSinglePosition(_Symbol, ForeignMagic, ForeignTicket))
  {
    FailTest("Seed verification failed; expected two owned and one foreign position.");
    return false;
  }

  if(!Runtime.RequestConfiguration(TGK_GRID_MODE_SELL, TestGridStep))
  {
    FailTest("Runtime could not enter the reset flow.");
    return false;
  }

  Started = true;
  Stage = TGK_DEMO_CLOSING_OWNED;
  ObjectDelete(0, StartButtonName);
  PrintFormat(
    "TGK Demo Integration: seeded 2 owned positions (magic=%I64d) and 1 foreign position (ticket=%I64u magic=%I64d).",
    Identity.MagicNumber(),
    ForeignTicket,
    ForeignMagic);
  Comment("TGK Grid Demo Integration: closing owned positions...");
  return true;
}

void ProcessOwnedClose()
{
  ENUM_TGK_GRID_RUNTIME_STATUS status = Runtime.UpdateLive();
  if(status == TGK_GRID_RUNTIME_ERROR)
  {
    FailTest("Runtime returned ERROR during owned-position reconciliation.");
    return;
  }

  if(status == TGK_GRID_RUNTIME_CLOSE_REQUIRED)
  {
    Trade.SetExpertMagicNumber((ulong)Identity.MagicNumber());
    Trade.SetDeviationInPoints(TestDeviationPoints);

    ENUM_TGK_GRID_EXECUTION_RESULT result =
      Adapter.ExecuteCloseIfRequired(status, Runtime, Trade);

    if(result == TGK_GRID_EXECUTION_INVALID_IDENTITY ||
       result == TGK_GRID_EXECUTION_SCAN_FAILED)
    {
      FailTest("Execution Adapter rejected identity or account scan failed.");
    }
    return;
  }

  if(status == TGK_GRID_RUNTIME_WAIT_CLOSE_CONFIRMATION)
  {
    Comment("TGK Grid Demo Integration: waiting for close confirmation...");
    return;
  }

  if(status == TGK_GRID_RUNTIME_WAIT_INITIAL_ENTRY ||
     status == TGK_GRID_RUNTIME_ACTIVE)
  {
    int owned_count = CountPositions(_Symbol, Identity.MagicNumber());
    if(owned_count != 0)
    {
      FailTest("Runtime left reset state while owned positions remain.");
      return;
    }

    ulong verified_foreign_ticket = 0;
    if(!FindSinglePosition(_Symbol, ForeignMagic, verified_foreign_ticket) ||
       verified_foreign_ticket != ForeignTicket)
    {
      FailTest("Foreign position verification failed; cleanup is disabled.");
      return;
    }

    Stage = TGK_DEMO_WAIT_FOREIGN_CLEANUP;
    CreateButton(
      CleanupButtonName,
      "CLEANUP FOREIGN POSITION",
      50,
      clrFireBrick);
    PrintFormat(
      "TGK Demo Integration: PASS — owned positions closed; foreign position remains (ticket=%I64u magic=%I64d).",
      ForeignTicket,
      ForeignMagic);
    Comment(
      "TGK Grid Demo Integration: CORE PASS\n",
      "Owned positions: 0\n",
      "Foreign position: 1 verified\n",
      "Review the ticket and Magic Number, then click CLEANUP.");
  }
}

void CleanupForeignPosition()
{
  if(Stage != TGK_DEMO_WAIT_FOREIGN_CLEANUP)
    return;

  ulong current_ticket = 0;
  if(!FindSinglePosition(_Symbol, ForeignMagic, current_ticket) ||
     current_ticket != ForeignTicket ||
     !PositionSelectByTicket(ForeignTicket) ||
     PositionGetString(POSITION_SYMBOL) != _Symbol ||
     PositionGetInteger(POSITION_MAGIC) != ForeignMagic)
  {
    FailTest("Foreign position no longer matches the verified Symbol, Magic Number, and Ticket. Nothing was closed.");
    return;
  }

  CleanupTrade.SetExpertMagicNumber((ulong)ForeignMagic);
  CleanupTrade.SetDeviationInPoints(TestDeviationPoints);

  bool sent = CleanupTrade.PositionClose(ForeignTicket);
  uint retcode = CleanupTrade.ResultRetcode();
  if(!sent || (retcode != TRADE_RETCODE_DONE &&
               retcode != TRADE_RETCODE_DONE_PARTIAL &&
               retcode != TRADE_RETCODE_PLACED))
  {
    FailTest(StringFormat(
      "Foreign cleanup request failed (retcode=%u, %s).",
      retcode,
      CleanupTrade.ResultRetcodeDescription()));
    return;
  }

  Stage = TGK_DEMO_VERIFYING_CLEANUP;
  ObjectDelete(0, CleanupButtonName);
  Comment("TGK Grid Demo Integration: verifying Foreign Position cleanup...");
}

void VerifyCleanup()
{
  int foreign_count = CountPositions(_Symbol, ForeignMagic);
  int owned_count = CountPositions(_Symbol, Identity.MagicNumber());

  if(foreign_count < 0 || owned_count < 0)
  {
    FailTest("Final account scan failed.");
    return;
  }

  if(foreign_count == 0 && owned_count == 0)
  {
    CleanupTestPersistence();
    Stage = TGK_DEMO_COMPLETE;
    Print("TGK DEMO INTEGRATION: FINAL RESULT: PASS");
    Comment(
      "TGK Grid Demo Integration: FINAL PASS\n",
      "Owned positions: 0\n",
      "Foreign position: 0\n",
      "All test positions are closed.");
    return;
  }

  if(foreign_count > 0)
  {
    FailTest("Foreign Position remains after cleanup; inspect the account manually.");
    return;
  }

  FailTest("Owned test positions unexpectedly reappeared during final verification.");
}

int OnInit()
{
  if(!Identity.Initialize(ChartID(), _Symbol))
  {
    Print("TGK Demo Integration: Grid Identity initialization failed.");
    return INIT_FAILED;
  }

  if(!IsValidTestVolume())
  {
    Print("TGK Demo Integration: TestLot is invalid for this Symbol.");
    return INIT_PARAMETERS_INCORRECT;
  }

  if(EnableDemoTest && !IsTradeEnvironmentAllowed())
    return INIT_FAILED;

  CreateButton(
    StartButtonName,
    EnableDemoTest ? "START DEMO INTEGRATION TEST" : "ENABLE INPUT TO START TEST",
    12,
    clrDarkSlateGray);

  Comment(
    "TGK Grid Demo Integration\n",
    "Demo-only; no trades are sent until you click START.\n",
    "EnableDemoTest = ", EnableDemoTest ? "true" : "false");
  return INIT_SUCCEEDED;
}

void OnTick()
{
  if(Stage == TGK_DEMO_CLOSING_OWNED)
    ProcessOwnedClose();
  else if(Stage == TGK_DEMO_VERIFYING_CLEANUP)
    VerifyCleanup();
}

void OnChartEvent(
  const int id,
  const long &lparam,
  const double &dparam,
  const string &sparam
)
{
  if(id != CHARTEVENT_OBJECT_CLICK)
    return;

  if(sparam == StartButtonName)
    StartIntegrationTest();
  else if(sparam == CleanupButtonName)
    CleanupForeignPosition();
}

void OnDeinit(const int reason)
{
  ObjectDelete(0, StartButtonName);
  ObjectDelete(0, CleanupButtonName);
}
