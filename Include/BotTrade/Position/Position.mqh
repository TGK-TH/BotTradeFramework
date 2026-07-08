//+------------------------------------------------------------------+
//|                                                     Position.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

//=====================================================
// POSITION EXISTS
//=====================================================

bool HasPosition() {
  return PositionSelect(_Symbol);
}
