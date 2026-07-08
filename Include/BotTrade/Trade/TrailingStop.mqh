//+------------------------------------------------------------------+
//|                                                 TrailingStop.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

#include <Trade/Trade.mqh>

//=====================================================
// TRAILING STOP
//=====================================================

void ManageOpenPosition(
   CTrade &trade,
   string symbol,

   double entryPrice,
   double initialRisk,

   bool trendMode,

   double trendTrailStartRR,
   double trendTrailStepRR,

   double nonTrendTrailStartRR,
   double nonTrendTrailStepRR,

   double &tradeSL,
   double &tradeTP
) {
   if(!PositionSelect(symbol)) {
      tradeSL = 0;
      tradeTP = 0;

      return;
   }

   ENUM_POSITION_TYPE posType =
      (ENUM_POSITION_TYPE)
      PositionGetInteger(POSITION_TYPE);

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double currentSL = NormalizeDouble(
      PositionGetDouble(POSITION_SL),
      digits
   );

   tradeTP = PositionGetDouble(POSITION_TP);

   double startRR =
      trendMode
      ? trendTrailStartRR
      : nonTrendTrailStartRR;

   double stepRR =
      trendMode
      ? trendTrailStepRR
      : nonTrendTrailStepRR;

   //--------------------------------------------------
   // BUY
   //--------------------------------------------------

   if(posType == POSITION_TYPE_BUY) {
      double bid = SymbolInfoDouble(symbol,SYMBOL_BID);
      double currentRR = (bid - entryPrice) / initialRisk;

      if(currentRR >= startRR) {
         double lockedRR =
            MathFloor(
               (currentRR - startRR)
               / stepRR
            ) * stepRR
            + (startRR - stepRR);

         double calculatedSL = entryPrice + (lockedRR * initialRisk);
         double newSL = NormalizeDouble(calculatedSL, digits);

         if(newSL > currentSL + point) {
            if(trade.PositionModify(
                  symbol,
                  NormalizeDouble(
                     newSL,
                     digits),
                  tradeTP))
            {
               tradeSL = newSL;
               Print("BUY TRAIL SL -> ", tradeSL);
            }
         }
      } else if (currentRR >= 1.0 && currentSL < entryPrice - point) {
         double newSL = NormalizeDouble(entryPrice, digits);

         if (newSL > currentSL + point) {
            if(trade.PositionModify(
                  symbol,
                  NormalizeDouble(
                     newSL,
                     digits),
                  tradeTP))
            {
               tradeSL = newSL;
               Print("BUY TRAIL BE -> ", tradeSL);
            }
         }
      }
   }

   //--------------------------------------------------
   // SELL
   //--------------------------------------------------

   if(posType == POSITION_TYPE_SELL) {
      double ask = SymbolInfoDouble(symbol,SYMBOL_ASK);
      double currentRR = (entryPrice - ask) / initialRisk;

      if(currentRR >= startRR) {
         double lockedRR =
            MathFloor(
               (currentRR - startRR)
               / stepRR
            ) * stepRR
            + (startRR - stepRR);

         double calculatedSL = entryPrice - (lockedRR * initialRisk);
         double newSL = NormalizeDouble(calculatedSL, digits);

         if(newSL < currentSL - point) {
            if(trade.PositionModify(
                  symbol,
                  NormalizeDouble(
                     newSL,
                     digits),
                  tradeTP))
            {
               tradeSL = newSL;
               Print("SELL TRAIL SL -> ", tradeSL);
            }
         }
      } else if (currentRR >= 1.0 && currentSL > entryPrice + point) {
         double newSL = NormalizeDouble(entryPrice, digits);

         if (newSL < currentSL - point) {
            if(trade.PositionModify(
                  symbol,
                  NormalizeDouble(
                     newSL,
                     digits),
                  tradeTP))
            {
               tradeSL = newSL;
               Print("SELL TRAIL BE -> ", tradeSL);
            }
         }
      }
   }
}
