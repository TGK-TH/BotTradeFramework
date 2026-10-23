#ifndef BOTTRADE_TESTING_TEST_RUNNER_MQH
#define BOTTRADE_TESTING_TEST_RUNNER_MQH

#include <BotTrade/Testing/TestAssert.mqh>

// Small synchronous test runner for MQL5 Scripts and Expert Advisors.
// It does not send orders or depend on market data.
class CTGKTestRunner
{
private:
  CTGKTestAssert m_assert;
  string m_suite_name;
  string m_test_name;
  int m_total_tests;
  int m_passed_tests;
  int m_failed_tests;
  int m_total_assertions;
  int m_passed_assertions;
  int m_failed_assertions;
  int m_test_assertions;
  bool m_test_failed;
  bool m_test_open;

  bool RecordAssertion(string assertion_name, bool passed, string details = "")
  {
    m_total_assertions++;
    m_test_assertions++;

    if(passed)
    {
      m_passed_assertions++;
      PrintFormat("  PASS: %s", assertion_name);
      return true;
    }

    m_failed_assertions++;
    m_test_failed = true;
    if(details == "")
      PrintFormat("  FAIL: %s", assertion_name);
    else
      PrintFormat("  FAIL: %s | %s", assertion_name, details);

    return false;
  }

public:
  CTGKTestRunner()
  {
    m_suite_name = "";
    m_test_name = "";
    m_total_tests = 0;
    m_passed_tests = 0;
    m_failed_tests = 0;
    m_total_assertions = 0;
    m_passed_assertions = 0;
    m_failed_assertions = 0;
    m_test_assertions = 0;
    m_test_failed = false;
    m_test_open = false;
  }

  void BeginSuite(string suite_name)
  {
    m_suite_name = suite_name;
    m_test_name = "";
    m_total_tests = 0;
    m_passed_tests = 0;
    m_failed_tests = 0;
    m_total_assertions = 0;
    m_passed_assertions = 0;
    m_failed_assertions = 0;
    m_test_assertions = 0;
    m_test_failed = false;
    m_test_open = false;

    Print("==================================================");
    PrintFormat("TEST SUITE: %s", m_suite_name);
    Print("==================================================");
  }

  void BeginTest(string test_name)
  {
    if(m_test_open)
      EndTest();

    m_test_name = test_name;
    m_total_tests++;
    m_test_assertions = 0;
    m_test_failed = false;
    m_test_open = true;

    PrintFormat("TEST: %s", m_test_name);
  }

  bool AssertTrue(string assertion_name, bool actual)
  {
    return RecordAssertion(
      assertion_name,
      m_assert.True(actual),
      StringFormat("actual=%s", actual ? "true" : "false")
    );
  }

  bool AssertFalse(string assertion_name, bool actual)
  {
    return RecordAssertion(
      assertion_name,
      m_assert.False(actual),
      StringFormat("actual=%s", actual ? "true" : "false")
    );
  }

  bool AssertEqualInt(string assertion_name, int actual, int expected)
  {
    return RecordAssertion(
      assertion_name,
      m_assert.EqualInt(actual, expected),
      StringFormat("expected=%d, actual=%d", expected, actual)
    );
  }

  bool AssertEqualLong(string assertion_name, long actual, long expected)
  {
    return RecordAssertion(
      assertion_name,
      m_assert.EqualLong(actual, expected),
      StringFormat("expected=%I64d, actual=%I64d", expected, actual)
    );
  }

  bool AssertEqualDouble(
    string assertion_name,
    double actual,
    double expected,
    double tolerance = 0.000001
  )
  {
    return RecordAssertion(
      assertion_name,
      m_assert.EqualDouble(actual, expected, tolerance),
      StringFormat(
        "expected=%.10f, actual=%.10f, tolerance=%.10f",
        expected,
        actual,
        tolerance
      )
    );
  }

  bool AssertEqualString(string assertion_name, string actual, string expected)
  {
    return RecordAssertion(
      assertion_name,
      m_assert.EqualString(actual, expected),
      StringFormat("expected='%s', actual='%s'", expected, actual)
    );
  }

  void EndTest()
  {
    if(!m_test_open)
      return;

    // A test passes only when it has assertions and all of them pass.
    if(m_test_failed)
    {
      m_failed_tests++;
      PrintFormat("RESULT: FAIL - %s", m_test_name);
    }
    else if(m_test_assertions == 0)
    {
      m_failed_tests++;
      PrintFormat("RESULT: FAIL - %s (no assertions)", m_test_name);
    }
    else
    {
      m_passed_tests++;
      PrintFormat("RESULT: PASS - %s", m_test_name);
    }

    m_test_name = "";
    m_test_open = false;
  }

  void EndSuite()
  {
    if(m_test_open)
      EndTest();

    Print("==================================================");
    PrintFormat("SUITE: %s", m_suite_name);
    PrintFormat("Tests: %d total, %d passed, %d failed",
                m_total_tests, m_passed_tests, m_failed_tests);
    PrintFormat("Assertions: %d total, %d passed, %d failed",
                m_total_assertions, m_passed_assertions, m_failed_assertions);
    Print(m_failed_tests == 0 && m_failed_assertions == 0
          ? "FINAL RESULT: PASS"
          : "FINAL RESULT: FAIL");
    Print("==================================================");
  }

  int FailedTests()
  {
    return m_failed_tests;
  }

  int FailedAssertions()
  {
    return m_failed_assertions;
  }

  bool AllPassed()
  {
    return m_failed_tests == 0 && m_failed_assertions == 0;
  }
};

#endif
