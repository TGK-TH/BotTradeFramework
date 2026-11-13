#property strict
#property version "1.00"
#property description "Identity integration tests for one chart; no trade operations."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridIdentity.mqh>

CTGKTestRunner Tests;

int OnInit()
{
  Tests.BeginSuite("TGK Grid Identity");

  CTGKGridIdentity first;
  bool first_ok = first.Initialize(
    ChartID(),
    _Symbol);

  Tests.BeginTest("Initialize creates or restores valid identity");
  Tests.AssertTrue(
    "initialization succeeds",
    first_ok);
  if(first_ok)
  {
    Tests.AssertTrue(
      "instance id is not empty",
      StringLen(first.InstanceId()) > 0);
    Tests.AssertTrue(
      "Magic Number is positive",
      first.MagicNumber() > 0);
    Tests.AssertEqualString(
      "symbol matches chart symbol",
      first.Symbol(),
      _Symbol);
  }
  Tests.EndTest();

  Tests.BeginTest("Repeated initialization on the same chart is stable");
  CTGKGridIdentity second;
  bool second_ok = second.Initialize(
    ChartID(),
    _Symbol);
  Tests.AssertTrue(
    "second initialization succeeds",
    second_ok);
  if(first_ok && second_ok)
  {
    Tests.AssertEqualString(
      "instance id remains stable",
      second.InstanceId(),
      first.InstanceId());
    Tests.AssertEqualLong(
      "Magic Number remains stable",
      second.MagicNumber(),
      first.MagicNumber());
    Tests.AssertEqualString(
      "symbol remains stable",
      second.Symbol(),
      first.Symbol());
  }
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
