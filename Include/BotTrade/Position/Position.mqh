//+------------------------------------------------------------------+
//|                                                     Position.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

#include <Trade/Trade.mqh>

//=====================================================
// POSITION EXISTS
//=====================================================

bool HasPosition() {
  return PositionSelect(_Symbol);
}

void ClosePosition(
  CTrade &trade,
  string symbol,
  ENUM_POSITION_TYPE type
) {
   if(!PositionSelect(symbol))
      return;

   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) {
      trade.PositionClose(symbol);
   }
}
