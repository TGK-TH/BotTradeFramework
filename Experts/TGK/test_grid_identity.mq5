//+------------------------------------------------------------------+
//|                                                    test_grid.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <BotTrade/Grid/GridIdentity.mqh>

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
    CTGKGridIdentity GridIdentity;
    bool isSuccess = GridIdentity.Initialize(ChartID(), _Symbol);

    if (isSuccess) {
      Print("Initialize Grid Identity Successful");

      string instanceId = GridIdentity.InstanceId();
      long magicNumber = GridIdentity.MagicNumber();
      string symbol = GridIdentity.Symbol();

      Print(StringFormat("Instance ID: %s", instanceId));
      Print(StringFormat("Magic Number: %I64d", magicNumber));
      Print(StringFormat("Symbol: %s", symbol));
    } else {
      Print("Initialize Grid Identity Unsuccessful");
    }
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---

  }
//+------------------------------------------------------------------+
