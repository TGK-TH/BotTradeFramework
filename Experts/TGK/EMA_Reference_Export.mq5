//+------------------------------------------------------------------+
//| EMA Reference Export                                             |
//| Export MT5 close prices and EMA12/EMA26 reference values.        |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input int FastEMA = 12;
input int SlowEMA = 26;
input int BarsToExport = 1000;
input ENUM_TIMEFRAMES Timeframe = PERIOD_M15;
input string OutputFile = "tgk_ema_reference.csv";

void OnStart()
{
  if(BarsToExport <= 0)
  {
    Print("BarsToExport must be greater than 0.");
    return;
  }

  int fastHandle = iMA(_Symbol, Timeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
  int slowHandle = iMA(_Symbol, Timeframe, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

  if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
  {
    Print("Failed to create EMA handles. Error: ", GetLastError());
    if(fastHandle != INVALID_HANDLE)
      IndicatorRelease(fastHandle);
    if(slowHandle != INVALID_HANDLE)
      IndicatorRelease(slowHandle);
    return;
  }

  MqlRates rates[];
  double fastEMA[];
  double slowEMA[];

  ArraySetAsSeries(rates, true);
  ArraySetAsSeries(fastEMA, true);
  ArraySetAsSeries(slowEMA, true);

  int copiedRates = CopyRates(_Symbol, Timeframe, 1, BarsToExport, rates);
  int copiedFast = CopyBuffer(fastHandle, 0, 1, BarsToExport, fastEMA);
  int copiedSlow = CopyBuffer(slowHandle, 0, 1, BarsToExport, slowEMA);

  if(copiedRates != BarsToExport || copiedFast != BarsToExport || copiedSlow != BarsToExport)
  {
    Print(
      "Not enough data. rates=", copiedRates,
      " fast=", copiedFast,
      " slow=", copiedSlow,
      " requested=", BarsToExport
    );

    IndicatorRelease(fastHandle);
    IndicatorRelease(slowHandle);
    return;
  }

  int exportedRows = 0;

  int fileHandle = FileOpen(
    OutputFile,
    FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI,
    ','
  );

  if(fileHandle == INVALID_HANDLE)
  {
    Print("Failed to open output file. Error: ", GetLastError());
    IndicatorRelease(fastHandle);
    IndicatorRelease(slowHandle);
    return;
  }

  FileWrite(
    fileHandle,
    "time",
    "close",
    "ema12",
    "ema26"
  );

  // CopyBuffer/CopyRates arrays are series arrays, so index 0 is the
  // newest closed candle. Write oldest -> newest for Python processing.
  for(int i = BarsToExport - 1; i >= 0; i--)
  {
    FileWrite(
      fileHandle,
      TimeToString(rates[i].time, TIME_DATE | TIME_MINUTES),
      DoubleToString(rates[i].close, _Digits),
      DoubleToString(fastEMA[i], 10),
      DoubleToString(slowEMA[i], 10)
    );

    exportedRows++;
  }

  FileClose(fileHandle);
  IndicatorRelease(fastHandle);
  IndicatorRelease(slowHandle);

  Print("EMA reference exported successfully");
  Print("File name: ", OutputFile);
  Print("Rows exported: ", exportedRows);
  Print("Full path: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", OutputFile);
}
