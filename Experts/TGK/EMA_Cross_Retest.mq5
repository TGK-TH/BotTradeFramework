//+------------------------------------------------------------------+
//| EMA Cross Retest Framework - Phase 1                            |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

#include <BotTrade/Indicators/EMA.mqh>
#include <BotTrade/Indicators/ADX.mqh>
#include <BotTrade/Indicators/Pivot.mqh>

#include <BotTrade/Market/Bar.mqh>

#include <BotTrade/Position/Position.mqh>

#include <BotTrade/Risk/LotCalculator.mqh>

#include <BotTrade/Strategy/StateMachine/WaitA.mqh>
#include <BotTrade/Strategy/StateMachine/WaitB.mqh>

#include <BotTrade/Trade/TrailingStop.mqh>

#include <BotTrade/Types/BotContext.mqh>
#include <BotTrade/Types/TradeState.mqh>

CTrade trade;

BotContext ctx;

//=====================================================
// INPUTS
//=====================================================

input int EMAFastLen = 12;
input int EMASlowLen = 26;

input int ADXPeriod = 14;
input double ADXThreshold = 20.0;
int ADXHandle;

input double RiskUSD = 1000;
input double MaxLot = 100.0;

input double SLBuffer = 1.5;

input double TrendTrailStartRR = 3.5;
input double TrendTrailStepRR = 0.5;

input double NonTrendTrailStartRR = 1.0;
input double NonTrendTrailStepRR = 0.5;

//=====================================================
// DIRECTION
//=====================================================

enum ENUM_DIRECTION
{
   DIR_NONE = 0,
   DIR_BUY = 1,
   DIR_SELL = -1
};

ENUM_DIRECTION Direction = DIR_NONE;

//=====================================================
// GLOBALS
//=====================================================

datetime LastM15Bar = 0;

//=====================================================
// TRADE VARIABLES
//=====================================================

double TradeSL = 0;
double TradeTP = 0;

double EntryPrice = 0;
double InitialRisk = 0;

bool TrendMode = false;

double CurrentLot = 0;

//=====================================================
// H1 CROSS
//=====================================================

bool H1CrossUp()
{
   double ema12_prev =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 2);

   double ema26_prev =
      GetEMA(_Symbol, PERIOD_H1, EMASlowLen, 2);

   double ema12_curr =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 1);

   double ema26_curr =
      GetEMA(_Symbol, PERIOD_H1, EMASlowLen, 1);

   return
      ema12_prev <= ema26_prev &&
      ema12_curr > ema26_curr;
}

//-----------------------------------------------------

bool H1CrossDown()
{
   double ema12_prev =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 2);

   double ema26_prev =
      GetEMA(_Symbol, PERIOD_H1, EMASlowLen, 2);

   double ema12_curr =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 1);

   double ema26_curr =
      GetEMA(_Symbol, PERIOD_H1, EMASlowLen, 1);

   return
      ema12_prev >= ema26_prev &&
      ema12_curr < ema26_curr;
}

//=====================================================
// RETEST
//=====================================================

bool BuyRetest()
{
   double lowM15 =
      iLow(_Symbol,PERIOD_M15,1);

   double h1EMA12 =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 1);

   return lowM15 < h1EMA12;
}

//-----------------------------------------------------

bool SellRetest()
{
   double highM15 =
      iHigh(_Symbol,PERIOD_M15,1);

   double h1EMA12 =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 1);

   return highM15 > h1EMA12;
}

//=====================================================
// CANDLE A
//=====================================================

bool BuyA()
{
   double closeM15 =
      iClose(_Symbol, PERIOD_M15, 1);

   double ema12 =
      GetEMA(_Symbol, PERIOD_M15, EMAFastLen, 1);

   double ema26 =
      GetEMA(_Symbol, PERIOD_M15, EMASlowLen, 1);

   double upperEMA = MathMax(ema12, ema26);

   return closeM15 > upperEMA;
}

//-----------------------------------------------------

bool SellA()
{
   double closeM15 =
      iClose(_Symbol, PERIOD_M15, 1);

   double ema12 =
      GetEMA(_Symbol, PERIOD_M15, EMAFastLen, 1);

   double ema26 =
      GetEMA(_Symbol, PERIOD_M15, EMASlowLen, 1);

   double lowerEMA = MathMin(ema12, ema26);

   return closeM15 < lowerEMA;
}

//=====================================================
// CANDLE B
//=====================================================

bool BuyB()
{
   double closeM15 =
      iClose(_Symbol, PERIOD_M15, 1);

   double lowM15 =
      iLow(_Symbol, PERIOD_M15, 1);

   return
      closeM15 > ctx.A.High &&
      lowM15 > ctx.A.Low;
}

//-----------------------------------------------------

bool SellB()
{
   double closeM15 =
      iClose(_Symbol, PERIOD_M15, 1);

   double highM15 =
      iHigh(_Symbol, PERIOD_M15, 1);

   return
      closeM15 < ctx.A.Low &&
      highM15 < ctx.A.High;
}

//=====================================================
// H4 TREND
//=====================================================

bool IsH4BullTrend()
{
   return
      GetEMA(_Symbol, PERIOD_H4, EMAFastLen, 1) >
      GetEMA(_Symbol, PERIOD_H4, EMASlowLen, 1);
}

//------------------------------------------------

bool IsH4BearTrend()
{
   return
      GetEMA(_Symbol, PERIOD_H4, EMAFastLen, 1) <
      GetEMA(_Symbol, PERIOD_H4, EMASlowLen, 1);
}

//=====================================================
// STATE MACHINE
//=====================================================

void ProcessStateMachine()
{
   //--------------------------------------------------
   // H1 CROSS
   //--------------------------------------------------

   if(H1CrossUp())
   {
      ctx.State = STATE_WAIT_RETEST;
      Direction = DIR_BUY;

      Print("H1 CROSS UP");
   }

   if(H1CrossDown())
   {
      ctx.State = STATE_WAIT_RETEST;
      Direction = DIR_SELL;

      Print("H1 CROSS DOWN");
   }

   //--------------------------------------------------
   // WAIT RETEST
   //--------------------------------------------------

   if(ctx.State == STATE_WAIT_RETEST)
   {
      datetime barTime = iTime(_Symbol, PERIOD_M15, 1);

      if(Direction == DIR_BUY)
      {
         if(BuyRetest())
         {
            ctx.State = STATE_WAIT_A;

            Print(
               "BUY RETEST DONE ON BAR ",
               TimeToString(barTime)
            );
         }
      }

      if(Direction == DIR_SELL)
      {
         if(SellRetest())
         {
            ctx.State = STATE_WAIT_A;

            Print(
               "SELL RETEST DONE ON BAR ",
               TimeToString(barTime)
            );
         }
      }
   }

   //--------------------------------------------------
   // WAIT A
   //--------------------------------------------------

   if(ctx.State == STATE_WAIT_A)
   {
      datetime barTime =
         iTime(_Symbol, PERIOD_M15, 1);

      if(Direction == DIR_BUY)
      {
         ProcessBuyWaitA(ctx);
      }

      if(Direction == DIR_SELL)
      {
         ProcessSellWaitA(ctx);
      }
   }

   //--------------------------------------------------
   // WAIT B
   //--------------------------------------------------

   if(ctx.State == STATE_WAIT_B) {
      datetime currentBar = iTime(_Symbol, PERIOD_M15, 1);

      // B Must be next to A only
      if(currentBar > ctx.A.Time + PeriodSeconds(PERIOD_M15)) {
         ctx.State = STATE_WAIT_A;

         Print("B NOT FOUND -> BACK TO WAIT A");
      }
      else {
         if(Direction == DIR_BUY) {
            ProcessBuyWaitB(ctx);
         } // End of Direction == DIR_BUY

         if(Direction == DIR_SELL) {
            ProcessSellWaitB(ctx);
         } // End of Direction == DIR_SELL
      }
   }

   //--------------------------------------------------
   // DEBUG
   //--------------------------------------------------

   Print(
      "STATE = ",
      ctx.State,
      " | DIR = ",
      Direction
   );
}

//=====================================================
// ON INIT
//=====================================================

int OnInit()
{
   Print("EA STARTED");

   ctx.State = STATE_WAIT_CROSS;

   ADXHandle = iADX(
      _Symbol,
      PERIOD_H1,
      ADXPeriod);

   return(INIT_SUCCEEDED);
}

//=====================================================
// ON TICK
//=====================================================

void OnTick()
{
   ManageOpenPosition(
      trade,
      _Symbol,

      EntryPrice,
      InitialRisk,

      TrendMode,

      TrendTrailStartRR,
      TrendTrailStepRR,

      NonTrendTrailStartRR,
      NonTrendTrailStepRR,

      TradeSL,
      TradeTP
   );

   if (!IsNewBar(_Symbol, PERIOD_M15, LastM15Bar))
      return;

   ProcessStateMachine();
}
