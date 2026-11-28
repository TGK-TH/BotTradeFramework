#property strict
#property version "1.00"
#property description "Grid Entry Mapping Journal tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridEntryMappingStorage.mqh>

CTGKTestRunner Tests;

int OnInit()
{
  Tests.BeginSuite("TGK Grid Entry Mapping Storage");

  string instance_id = StringFormat(
    "UT%d_%I64d",
    (int)ChartID(),
    (long)TimeLocal());
  string other_instance_id = instance_id + "_OTHER";

  CTGKGridEntryMappingStorage storage;
  CTGKGridEntryMappingStorage restored_storage;
  CTGKGridEntryMappingStorage other_storage;

  Tests.BeginTest("Initialize validates identity and creates an isolated journal");
  Tests.AssertFalse(
    "empty symbol rejected",
    storage.Initialize("", instance_id));
  Tests.AssertFalse(
    "empty instance rejected",
    storage.Initialize(_Symbol, ""));
  Tests.AssertTrue(
    "valid identity initializes",
    storage.Initialize(_Symbol, instance_id));
  Tests.AssertTrue(
    "journal filename is available",
    StringLen(storage.FileName()) > 0);
  Tests.EndTest();

  if(!storage.IsInitialized())
  {
    Tests.EndSuite();
    return INIT_FAILED;
  }

  storage.DeleteJournal();

  Tests.BeginTest("Append and replay preserve ordered records");
  Tests.AssertTrue(
    "append entry intent",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
      "request=R1;identifier=9007199254740993;comment=TGK Grid BUY ANCHOR"));
  Tests.AssertTrue(
    "append execution result",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
      "request=R1;outcome=PLACED;order=9007199254740995;deal=9007199254740997"));

  STGKGridMappingJournalRecord records[];
  int record_count = 0;
  long next_sequence = 0;
  Tests.AssertTrue(
    "restore journal",
    restored_storage.Initialize(_Symbol, instance_id) &&
    restored_storage.Replay(records, record_count, next_sequence));
  Tests.AssertEqualInt("two records restored", record_count, 2);
  Tests.AssertEqualLong("next sequence follows last record", next_sequence, 3);
  if(record_count == 2)
  {
    Tests.AssertEqualLong("first sequence", records[0].sequence, 1);
    Tests.AssertEqualInt(
      "first record type",
      (int)records[0].record_type,
      (int)TGK_GRID_MAPPING_RECORD_ENTRY_INTENT);
    Tests.AssertEqualString(
      "large decimal identifier retained exactly",
      records[0].payload,
      "request=R1;identifier=9007199254740993;comment=TGK Grid BUY ANCHOR");
    Tests.AssertEqualLong("second sequence", records[1].sequence, 2);
  }
  Tests.EndTest();

  Tests.BeginTest("Large identifiers remain decimal strings, never numeric conversions");
  Tests.AssertTrue(
    "append maximum practical ticket text",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
      "deal=18446744073709551614;position_identifier=18446744073709551613"));
  ArrayFree(records);
  record_count = 0;
  Tests.AssertTrue(
    "replay large identifiers",
    restored_storage.Replay(records, record_count, next_sequence));
  Tests.AssertEqualInt("three records restored", record_count, 3);
  if(record_count == 3)
    Tests.AssertEqualString(
      "64-bit unsigned identifiers round-trip exactly",
      records[2].payload,
      "deal=18446744073709551614;position_identifier=18446744073709551613");
  Tests.EndTest();

  Tests.BeginTest("Different Instance receives a different journal");
  Tests.AssertTrue(
    "other Instance initializes",
    other_storage.Initialize(_Symbol, other_instance_id));
  Tests.AssertTrue(
    "other Instance has distinct filename",
    storage.FileName() != other_storage.FileName());
  int other_count = -1;
  long other_next_sequence = 0;
  STGKGridMappingJournalRecord other_records[];
  Tests.AssertTrue(
    "other Instance replays its own empty journal",
    other_storage.Replay(other_records, other_count, other_next_sequence));
  Tests.AssertEqualInt("other Instance has no records", other_count, 0);
  Tests.EndTest();

  Tests.BeginTest("Comment text is opaque payload and is not interpreted");
  Tests.AssertTrue(
    "append changed comment",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
      "request=R1;position=77;level=3;comment=SELL L-99"));
  ArrayFree(records);
  record_count = 0;
  Tests.AssertTrue(
    "replay with arbitrary comment",
    restored_storage.Replay(records, record_count, next_sequence));
  Tests.AssertEqualInt("four records restored", record_count, 4);
  if(record_count == 4)
    Tests.AssertEqualString(
      "comment mismatch remains ordinary data",
      records[3].payload,
      "request=R1;position=77;level=3;comment=SELL L-99");
  Tests.EndTest();

  Tests.BeginTest("Incomplete final record is ignored and removed before the next append");
  int journal_handle = FileOpen(
    storage.FileName(),
    FILE_READ | FILE_WRITE | FILE_BIN);
  bool tail_written = false;
  if(journal_handle != INVALID_HANDLE)
  {
    FileSeek(journal_handle, 0, SEEK_END);
    uchar partial_tail[];
    int partial_count = StringToCharArray(
      "TGKJ|1|5|",
      partial_tail,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(partial_count > 1)
    {
      ArrayResize(partial_tail, partial_count - 1);
      tail_written = FileWriteArray(
        journal_handle,
        partial_tail,
        0,
        (uint)ArraySize(partial_tail)) == ArraySize(partial_tail);
    }
    FileClose(journal_handle);
  }
  Tests.AssertTrue("partial final bytes written", tail_written);
  ArrayFree(records);
  record_count = 0;
  Tests.AssertTrue(
    "replay ignores incomplete final record",
    restored_storage.Replay(records, record_count, next_sequence));
  Tests.AssertEqualInt("incomplete tail does not add a record", record_count, 4);
  Tests.AssertTrue(
    "next append repairs tail and succeeds",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "request=R1;state=RECONCILED"));
  ArrayFree(records);
  record_count = 0;
  Tests.AssertTrue(
    "replay after tail repair succeeds",
    restored_storage.Replay(records, record_count, next_sequence));
  Tests.AssertEqualInt("repaired journal contains five records", record_count, 5);
  Tests.EndTest();

  Tests.BeginTest("Complete malformed record causes safe replay failure");
  journal_handle = FileOpen(
    storage.FileName(),
    FILE_READ | FILE_WRITE | FILE_BIN);
  bool malformed_written = false;
  if(journal_handle != INVALID_HANDLE)
  {
    FileSeek(journal_handle, 0, SEEK_END);
    uchar malformed[];
    int malformed_count = StringToCharArray(
      "not-a-valid-record\n",
      malformed,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(malformed_count > 1)
    {
      ArrayResize(malformed, malformed_count - 1);
      malformed_written = FileWriteArray(
        journal_handle,
        malformed,
        0,
        (uint)ArraySize(malformed)) == ArraySize(malformed);
    }
    FileClose(journal_handle);
  }
  Tests.AssertTrue("malformed complete record written", malformed_written);
  ArrayFree(records);
  record_count = 0;
  Tests.AssertFalse(
    "complete malformed record rejects replay",
    restored_storage.Replay(records, record_count, next_sequence));
  Tests.EndTest();

  // Each test run uses a unique Instance ID; remove only its own journal.
  storage.DeleteJournal();
  other_storage.DeleteJournal();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
