#property strict
#property version "1.00"
#property description "Multi-chart Grid identity isolation test; no trade operations."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridIdentity.mqh>

CTGKTestRunner Tests;

int OnInit()
{
  Tests.BeginSuite("TGK Grid Multi-Chart Identity");

  CTGKGridIdentity first;
  bool first_ok = first.Initialize(
    ChartID(),
    _Symbol);

  Tests.BeginTest("Current chart identity initializes");
  Tests.AssertTrue(
    "current chart identity initializes",
    first_ok);
  if(first_ok)
  {
    Tests.AssertTrue(
      "current instance id is not empty",
      StringLen(first.InstanceId()) > 0);
    Tests.AssertTrue(
      "current Magic Number is positive",
      first.MagicNumber() > 0);
  }
  Tests.EndTest();

  long second_chart_id = ChartOpen(
    _Symbol,
    (ENUM_TIMEFRAMES)_Period);

  Tests.BeginTest("Second chart receives isolated identity");
  Tests.AssertTrue(
    "ChartOpen returns a chart id",
    second_chart_id > 0);

  if(second_chart_id > 0 && first_ok)
  {
    Tests.AssertTrue(
      "second chart id differs",
      second_chart_id != ChartID());

    CTGKGridIdentity second;
    bool second_ok = second.Initialize(
      second_chart_id,
      _Symbol);

    Tests.AssertTrue(
      "second chart identity initializes",
      second_ok);

    if(second_ok)
    {
      Tests.AssertTrue(
        "instance ids are different",
        second.InstanceId() != first.InstanceId());
      Tests.AssertTrue(
        "Magic Numbers are different",
        second.MagicNumber() != first.MagicNumber());
      Tests.AssertTrue(
        "second Magic Number is positive",
        second.MagicNumber() > 0);

      // The secondary chart is temporary. Remove only its registry entry;
      // the global allocation sequence is intentionally not decremented.
      string registry_key = StringFormat(
        "TGK.M.%I64d.%s",
        AccountInfoInteger(ACCOUNT_LOGIN),
        second.InstanceId());

      ChartClose(second_chart_id);
      GlobalVariableDel(registry_key);
      GlobalVariablesFlush();
    }
    else
    {
      ChartClose(second_chart_id);
    }
  }
  else if(second_chart_id > 0)
  {
    ChartClose(second_chart_id);
  }

  Tests.EndTest();
  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
