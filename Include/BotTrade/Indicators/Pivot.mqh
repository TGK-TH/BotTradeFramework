//+------------------------------------------------------------------+
//|                                                        Pivot.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

//=====================================================
// PIVOT LOW
//=====================================================

double LastPivotLow(
   string symbol,
   ENUM_TIMEFRAMES tf
) {
   for(int i = 2; i < 100; i++) {
      double p = iLow(symbol, tf, i);

      if(
         p < iLow(symbol, tf, i+1) &&
         p < iLow(symbol, tf, i+2) &&
         p < iLow(symbol, tf, i-1)
      ) {
         return p;
      }
   }

   return 0;
}

//=====================================================
// PIVOT HIGH
//=====================================================

double LastPivotHigh(
   string symbol,
   ENUM_TIMEFRAMES tf
) {
   for(int i = 2; i < 100; i++) {
      double p = iHigh(symbol, tf, i);

      if(
         p > iHigh(symbol, tf, i+1) &&
         p > iHigh(symbol, tf, i+2) &&
         p > iHigh(symbol, tf, i-1)
      ) {
         return p;
      }
   }

   return 0;
}
