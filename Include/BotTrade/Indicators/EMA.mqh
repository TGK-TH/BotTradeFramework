//+------------------------------------------------------------------+
//|                                                          EMA.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

//=====================================================
// EMA FUNCTION
// shift = 1 ==> is last closed candle stick
//=====================================================

double GetEMA(
   string symbol,
   ENUM_TIMEFRAMES tf,
   int period,
   int shift
) {
   int handle = iMA(
      symbol,
      tf,
      period,
      0,
      MODE_EMA,
      PRICE_CLOSE);

   if(handle == INVALID_HANDLE)
      return 0;

   double buffer[];

   if(CopyBuffer(handle,0,shift,1,buffer) <= 0)
      return 0;

   return buffer[0];
}
