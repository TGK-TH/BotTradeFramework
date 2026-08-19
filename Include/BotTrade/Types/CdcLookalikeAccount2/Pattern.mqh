//+------------------------------------------------------------------+
//|                                                      Pattern.mqh  |
//+------------------------------------------------------------------+
#ifndef __CDCLOOKACC2_PATTERN_MQH__
#define __CDCLOOKACC2_PATTERN_MQH__

struct Pattern {
  bool valid;
  bool isBuy;

  double point1;
  double point2;
  double point3;

  int point1Bar;
  int point2Bar;
  int point3Bar;

  double retracement;
};

#endif
