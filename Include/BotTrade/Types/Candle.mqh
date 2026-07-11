//+------------------------------------------------------------------+
//|                                                      Candle.mqh  |
//+------------------------------------------------------------------+
#ifndef __CANDLE_MQH__
#define __CANDLE_MQH__

struct Candle
{
   double High;
   double Low;
   datetime Time;

   void Reset()
   {
      High = 0;
      Low = 0;
      Time = 0;
   }
};

#endif
