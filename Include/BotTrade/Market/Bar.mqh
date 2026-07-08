//+------------------------------------------------------------------+
//|                                                          Bar.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

//=====================================================
// CHECK NEW M15 BAR
//=====================================================

bool IsNewBar(
   string symbol,
   ENUM_TIMEFRAMES tf,
   datetime &lastBar
) {
   datetime currentBar = iTime(symbol, tf, 0);

   if(currentBar != lastBar) {
      lastBar = currentBar;
      return true;
   }

   return false;
}
