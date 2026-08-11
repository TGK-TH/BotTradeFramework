//+------------------------------------------------------------------+
//|                                                      Segment.mqh  |
//+------------------------------------------------------------------+
#ifndef __SEGMENT_MQH__
#define __SEGMENT_MQH__

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

