#include <BotTrade/Indicators/ADX.mqh>
#include <BotTrade/Indicators/Pivot.mqh>

#include <BotTrade/Position/Position.mqh>

#include <BotTrade/Risk/LotCalculator.mqh>

#include <BotTrade/Strategy/StateMachine/WaitA.mqh>

#include <BotTrade/Trade/OrderExecution.mqh>

#include <BotTrade/Types/BotContext.mqh>

//=====================================================
// PROCESS STATE WAIT_B for BUY
//=====================================================

void ProcessBuyWaitB(BotContext &ctx) {
  bool adxBuy =
    GetADX(ADXHandle, 1) >= ADXThreshold &&
    GetDIPlus(ADXHandle, 1) > GetDIMinus(ADXHandle, 1);

  datetime currentBar = iTime(_Symbol, PERIOD_M15, 1);

  if(BuyB()) {
    Print("BUY B FOUND ON ", TimeToString(currentBar));

    if(!HasPosition()) {
      if (adxBuy) {
        ctx.EntryPrice = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        ctx.TradeSL = LastPivotLow(_Symbol, PERIOD_M15) - SLBuffer;
        ctx.InitialRisk = ctx.EntryPrice - ctx.TradeSL;
        ctx.TrendMode = IsH4BullTrend();
        ctx.TradeTP = 0;

        ctx.CurrentLot = CalcLot(
          _Symbol,
          ORDER_TYPE_BUY,
          ctx.EntryPrice,
          ctx.TradeSL,
          RiskUSD,
          MaxLot
        );

        bool result = ExecuteBuy(
          trade,
          _Symbol,
          ctx.CurrentLot,
          ctx.TradeSL,
          ctx.TradeTP,
          "BUY"
        );

        if(result) {
          Print(
            "BUY OPENED Lot=",
            ctx.CurrentLot,
            " SL=",
            ctx.TradeSL,
            " TP=",
            ctx.TradeTP);

          ctx.State = STATE_IN_TRADE;
        }
      } else {
        ctx.State = STATE_WAIT_CROSS;
      } // End of adxBuy
    } // End of !HasPosition
  } // End of BuyB()
  else {
    if (currentBar == ctx.A.Time + PeriodSeconds(PERIOD_M15)) {
      if (BuyA()) {
        ProcessBuyWaitA(ctx);
      }
      else{
        ctx.State = STATE_WAIT_A;
        Print("Not BuyB() -> BACK TO WAIT A");
      }
    }
  }
}

//=====================================================
// PROCESS STATE WAIT_B for SELL
//=====================================================

void ProcessSellWaitB(BotContext &ctx) {
  bool adxSell =
    GetADX(ADXHandle, 1) >= ADXThreshold &&
    GetDIMinus(ADXHandle, 1) > GetDIPlus(ADXHandle, 1);

  datetime currentBar = iTime(_Symbol, PERIOD_M15, 1);

  if(SellB()) {
    Print("SELL B FOUND ON ", TimeToString(currentBar));

    if(!HasPosition()) {
      if (adxSell) {
        ctx.EntryPrice = SymbolInfoDouble(_Symbol,SYMBOL_BID);
        ctx.TradeSL = LastPivotHigh(_Symbol, PERIOD_M15) + SLBuffer;
        ctx.InitialRisk = ctx.TradeSL - ctx.EntryPrice;
        ctx.TrendMode = IsH4BearTrend();
        ctx.TradeTP = 0;

        ctx.CurrentLot = CalcLot(
          _Symbol,
          ORDER_TYPE_SELL,
          ctx.EntryPrice,
          ctx.TradeSL,
          RiskUSD,
          MaxLot
        );

        bool result = ExecuteSell(
          trade,
          _Symbol,
          ctx.CurrentLot,
          ctx.TradeSL,
          ctx.TradeTP,
          "SELL"
        );

        if(result) {
          Print(
            "SELL OPENED Lot=",
            ctx.CurrentLot,
            " SL=",
            ctx.TradeSL,
            " TP=",
            ctx.TradeTP);

          ctx.State = STATE_IN_TRADE;
        }
      } else {
        ctx.State = STATE_WAIT_CROSS;
      } // End of adxSell
    } // End of !HasPosition()
  } // End of SellB()
  else {
    if (currentBar == ctx.A.Time + PeriodSeconds(PERIOD_M15)) {
      if (SellA()) {
        ProcessSellWaitA(ctx);
      }
      else {
        ctx.State = STATE_WAIT_A;
        Print("Not SellB() -> BACK TO WAIT A");
      }
    }
  }
}
