#ifndef BOTTRADE_TESTING_TEST_ASSERT_MQH
#define BOTTRADE_TESTING_TEST_ASSERT_MQH

// Lightweight assertion helpers for MQL5 test programs.
// Each assertion returns true when it passes and false when it fails.
// TestRunner owns counting and reporting.

class CTGKTestAssert
{
public:
  bool True(bool actual)
  {
    return actual;
  }

  bool False(bool actual)
  {
    return !actual;
  }

  bool EqualInt(int actual, int expected)
  {
    return actual == expected;
  }

  bool EqualLong(long actual, long expected)
  {
    return actual == expected;
  }

  bool EqualDouble(double actual, double expected, double tolerance)
  {
    if(tolerance < 0.0)
      return false;

    return MathAbs(actual - expected) <= tolerance;
  }

  bool EqualString(string actual, string expected)
  {
    return actual == expected;
  }
};

#endif
