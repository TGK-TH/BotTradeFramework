//+------------------------------------------------------------------+
//|                                                 IsEmaCrossUp.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

#include <BotTrade/Indicators/EMA.mqh>

//+------------------------------------------------------------------+
//| Check EMA Cross Up                                               |
//+------------------------------------------------------------------+
bool IsEmaCrossUp(
  string symbol,
  ENUM_TIMEFRAMES timeframe,
  int fastEmaPeriod,
  int slowEmaPeriod
) {
  double emaFastPrev = GetEMA(symbol, timeframe, fastEmaPeriod, 2);
  double emaSlowPrev = GetEMA(symbol, timeframe, slowEmaPeriod, 2);
  double emaFastCurr = GetEMA(symbol, timeframe, fastEmaPeriod, 1);
  double emaSlowCurr = GetEMA(symbol, timeframe, slowEmaPeriod, 1);

  return emaFastPrev <= emaSlowPrev && emaFastCurr > emaSlowCurr;
}
