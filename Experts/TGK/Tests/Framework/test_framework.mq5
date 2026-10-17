//+------------------------------------------------------------------+
//|                                               test_framework.mq5 |
//|             TGK BotTradeFramework - MQL5 Unit Test Framework      |
//+------------------------------------------------------------------+
#property version   "1.00"
#property description "Runs the TGK MQL5 test framework checks. No trading."

#include <BotTrade/Testing/TestRunner.mqh>

CTGKTestRunner g_test_runner;

int OnInit()
{
  g_test_runner.BeginSuite("TGK Test Framework");

  g_test_runner.BeginTest("Boolean assertions");
  g_test_runner.AssertTrue("true value passes", true);
  g_test_runner.AssertFalse("false value passes", false);
  g_test_runner.EndTest();

  g_test_runner.BeginTest("Integer assertions");
  g_test_runner.AssertEqualInt("equal integers", 42, 42);
  g_test_runner.AssertEqualLong("equal long integers", 710001, 710001);
  g_test_runner.EndTest();

  g_test_runner.BeginTest("Floating-point assertions");
  g_test_runner.AssertEqualDouble("equal doubles", 1.25, 1.25);
  g_test_runner.AssertEqualDouble(
    "double values within tolerance",
    1.0000001,
    1.0,
    0.000001
  );
  g_test_runner.EndTest();

  g_test_runner.BeginTest("String assertions");
  g_test_runner.AssertEqualString("equal strings", "TGK", "TGK");
  g_test_runner.EndTest();

  g_test_runner.EndSuite();

  if(!g_test_runner.AllPassed())
    Print("WARNING: Test framework checks failed. Review the results above.");

  return INIT_SUCCEEDED;
}

void OnTick()
{
  // Intentionally empty. This test EA never sends trade requests.
}
