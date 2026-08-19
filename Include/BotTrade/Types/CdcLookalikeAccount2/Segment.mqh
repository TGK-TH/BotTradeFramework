//+------------------------------------------------------------------+
//|                                                      Segment.mqh  |
//+------------------------------------------------------------------+
#ifndef __CDCLOOKACC2_SEGMENT_MQH__
#define __CDCLOOKACC2_SEGMENT_MQH__

struct Segment {
  int startBar;
  int endBar;
  int crossBar;

  double highest;
  int highestBar;

  double lowest;
  int lowestBar;

  bool isGreen;
};

#endif
