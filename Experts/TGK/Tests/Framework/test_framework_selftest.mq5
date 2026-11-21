//+------------------------------------------------------------------+
//|                                      test_framework_selftest.mq5 |
//|      TGK BotTradeFramework - Test Runner failure-detection tests  |
//+------------------------------------------------------------------+
#property version   "1.00"
#property description "Validates test-runner failure detection. No trading."

#include <BotTrade/Testing/TestRunner.mqh>

CTGKTestRunner g_self_test_runner;

int OnInit()
{
  g_self_test_runner.BeginSuite("TGK Test Framework Self-Test");

  // The nested runner is intentionally made to fail. This is expected:
  // the outer test verifies that failure counts and AllPassed() respond.
  CTGKTestRunner expected_failure_runner;
  expected_failure_runner.BeginSuite("Expected Failure Probe");

  expected_failure_runner.BeginTest("Deliberate failed assertion");
  expected_failure_runner.AssertTrue("false must fail", false);
  expected_failure_runner.EndTest();
  expected_failure_runner.EndSuite();

  g_self_test_runner.BeginTest("Failed assertion is counted");
  g_self_test_runner.AssertEqualInt(
    "one failed assertion recorded",
    expected_failure_runner.FailedAssertions(),
    1
  );
  g_self_test_runner.AssertEqualInt(
    "one failed test recorded",
    expected_failure_runner.FailedTests(),
    1
  );
  g_self_test_runner.AssertFalse(
    "runner reports failure through AllPassed",
    expected_failure_runner.AllPassed()
  );
  g_self_test_runner.EndTest();

  // A test with no assertions must also fail, rather than silently pass.
  CTGKTestRunner empty_test_runner;
  empty_test_runner.BeginSuite("Expected Empty-Test Failure Probe");
  empty_test_runner.BeginTest("No assertions");
  empty_test_runner.EndTest();
  empty_test_runner.EndSuite();

  g_self_test_runner.BeginTest("Test without assertions is rejected");
  g_self_test_runner.AssertEqualInt(
    "empty test counted as failed",
    empty_test_runner.FailedTests(),
    1
  );
  g_self_test_runner.AssertEqualInt(
    "empty test has no failed assertions",
    empty_test_runner.FailedAssertions(),
    0
  );
  g_self_test_runner.AssertFalse(
    "empty-test suite reports failure",
    empty_test_runner.AllPassed()
  );
  g_self_test_runner.EndTest();

  g_self_test_runner.EndSuite();

  if(!g_self_test_runner.AllPassed())
    Print("WARNING: Framework self-tests failed. Review the results above.");

  return INIT_SUCCEEDED;
}

void OnTick()
{
  // Intentionally empty. This test EA never sends trade requests.
}
