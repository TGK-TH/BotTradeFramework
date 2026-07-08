//+------------------------------------------------------------------+
//|                                                          ADX.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

//=====================================================
// ADX FUNCTION
//=====================================================

double GetADX(int handle, int shift) {
   double adx[];

   if(CopyBuffer(handle, 0, shift, 1, adx) <= 0)
      return 0;

   return adx[0];
}

double GetDIPlus(int handle, int shift) {
   double buf[];

   if(CopyBuffer(handle, 1, shift, 1, buf) <= 0)
      return 0;

   return buf[0];
}

double GetDIMinus(int handle, int shift) {
   double buf[];

   if(CopyBuffer(handle, 2, shift, 1, buf) <= 0)
      return 0;

   return buf[0];
}
