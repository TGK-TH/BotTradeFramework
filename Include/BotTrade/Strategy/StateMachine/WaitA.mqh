//+------------------------------------------------------------------+
//|                                                        WaitA.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

//=====================================================
// PROCESS STATE WAIT_A
//=====================================================

void ProcessBuyWaitA()
{
   if(BuyA())
   {
      datetime barTime = iTime(_Symbol, PERIOD_M15, 1);

      ctx.A.High = iHigh(_Symbol, PERIOD_M15, 1);
      ctx.A.Low = iLow(_Symbol, PERIOD_M15, 1);
      ctx.A.Time = barTime;

      ctx.State = STATE_WAIT_B;

      Print(
         "FOUND BUY A ON ",
         TimeToString(barTime)
      );
   }
}

void ProcessSellWaitA()
{
   if(SellA())
   {
      datetime barTime = iTime(_Symbol, PERIOD_M15, 1);
      ctx.A.High = iHigh(_Symbol, PERIOD_M15, 1);
      ctx.A.Low = iLow(_Symbol, PERIOD_M15, 1);
      ctx.A.Time = barTime;

      ctx.State = STATE_WAIT_B;

      Print(
         "FOUND SELL A ON ",
         TimeToString(barTime)
      );
   }
}
