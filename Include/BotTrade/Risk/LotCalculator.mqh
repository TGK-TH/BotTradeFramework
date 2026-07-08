//+------------------------------------------------------------------+
//|                                                LotCalculator.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

//=====================================================
// POSITION SIZE
//=====================================================

double CalcLot(
   string symbol,
   ENUM_ORDER_TYPE type,
   double entryPrice,
   double stopPrice,
   double riskUSD,
   double maxLot
) {
   double maxRisk = riskUSD;
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLotBroker = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot = minLot;

   for(
      double testLot = minLot;
      testLot <= MathMin(maxLot, maxLotBroker);
      testLot += lotStep
   ) {
      double loss = 0;

      if(OrderCalcProfit(type, symbol, testLot, entryPrice, stopPrice, loss)) {
         loss = MathAbs(loss);

         if(loss >= maxRisk) {
            lot = testLot;
            break;
         }
      }
   }

   return NormalizeDouble(lot, 2);
}
