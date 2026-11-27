#property strict
#property version "1.00"
#property description "Grid Open Position Snapshot acquisition tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridOpenPositionSnapshot.mqh>

CTGKTestRunner Tests;

#define UT_SYMBOL "XAUUSD"
#define UT_MAGIC 710501

#define FAKE_PROPERTY_IDENTIFIER 1
#define FAKE_PROPERTY_TICKET 2
#define FAKE_PROPERTY_SYMBOL 3
#define FAKE_PROPERTY_MAGIC 4
#define FAKE_PROPERTY_VOLUME 5

// Scripted two-scan Account port. It never touches the MT5 Position API.
//
// Each required property is read through its own boolean Getter, mirroring
// CTGKGridMT5OpenPositionSource: an injected Getter failure rejects the whole
// read instead of yielding a default value that could pass validation.
class CFakeOpenPositionSource : public CTGKGridOpenPositionSource
{
public:
  STGKGridOpenPositionRecord first_scan[];
  STGKGridOpenPositionRecord second_scan[];
  STGKGridOpenPositionRecord retry_first_scan[];
  STGKGridOpenPositionRecord retry_second_scan[];
  bool has_retry_script;
  int retry_from_attempt;
  bool fail_total;
  int total_delta_on_end_call;
  int fail_ticket_index;
  int zero_ticket_index;
  int fail_select_index;
  int fail_read_index;
  int fail_property_read_index;
  int fail_property_read;
  int total_call_count;
  int current_scan;
  int current_attempt;
  int selected_index;

  CFakeOpenPositionSource()
  {
    Reset();
  }

  void Reset()
  {
    ArrayResize(first_scan, 0);
    ArrayResize(second_scan, 0);
    ArrayResize(retry_first_scan, 0);
    ArrayResize(retry_second_scan, 0);
    has_retry_script = false;
    retry_from_attempt = 0;
    fail_total = false;
    total_delta_on_end_call = 0;
    fail_ticket_index = -1;
    zero_ticket_index = -1;
    fail_select_index = -1;
    fail_read_index = -1;
    fail_property_read_index = -1;
    fail_property_read = 0;
    total_call_count = 0;
    current_scan = 0;
    current_attempt = 0;
    selected_index = -1;
  }

  // Number of complete scan pairs the Acquirer has already observed.
  int AttemptCount()
  {
    return total_call_count / 4;
  }

  void AssignScan(
    STGKGridOpenPositionRecord &source[],
    STGKGridOpenPositionRecord &destination[])
  {
    int total = ArraySize(source);
    ArrayResize(destination, total);
    for(int index = 0; index < total; index++)
      destination[index] = source[index];
  }

  // The retry script replaces the primary pair from retry_from_attempt onward,
  // so a transient membership change can be followed by a Stable pair.
  void CopyScan(int scan, STGKGridOpenPositionRecord &records[])
  {
    bool use_retry = has_retry_script && current_attempt >= retry_from_attempt;

    if(scan == 0)
    {
      if(use_retry)
        AssignScan(retry_first_scan, records);
      else
        AssignScan(first_scan, records);
    }
    else
    {
      if(use_retry)
        AssignScan(retry_second_scan, records);
      else
        AssignScan(second_scan, records);
    }
  }

  virtual bool TotalPositions(int &total)
  {
    total = -1;
    if(fail_total)
      return false;

    current_scan = (total_call_count / 2) % 2;
    current_attempt = total_call_count / 4;

    STGKGridOpenPositionRecord records[];
    CopyScan(current_scan, records);

    total = ArraySize(records);
    if(total_call_count % 2 == 1)
      total += total_delta_on_end_call;

    total_call_count++;
    return true;
  }

  virtual bool TicketAt(int index, ulong &ticket)
  {
    ticket = 0;
    if(index == fail_ticket_index)
      return false;

    STGKGridOpenPositionRecord records[];
    CopyScan(current_scan, records);
    if(index < 0 || index >= ArraySize(records))
      return false;

    ticket = records[index].ticket;
    if(index == zero_ticket_index)
      ticket = 0;
    return true;
  }

  virtual bool SelectTicket(ulong ticket)
  {
    STGKGridOpenPositionRecord records[];
    CopyScan(current_scan, records);

    selected_index = -1;
    for(int index = 0; index < ArraySize(records); index++)
    {
      if(records[index].ticket == ticket)
      {
        selected_index = index;
        break;
      }
    }

    return selected_index >= 0 && selected_index != fail_select_index;
  }

  bool PropertyReadFails(int property)
  {
    return selected_index == fail_property_read_index &&
           fail_property_read == property;
  }

  bool ReadIdentifier(STGKGridOpenPositionRecord &source, long &value)
  {
    value = 0;
    if(PropertyReadFails(FAKE_PROPERTY_IDENTIFIER))
      return false;

    value = StringToInteger(source.position_identifier);
    return true;
  }

  bool ReadTicket(STGKGridOpenPositionRecord &source, long &value)
  {
    value = 0;
    if(PropertyReadFails(FAKE_PROPERTY_TICKET))
      return false;

    value = (long)source.ticket;
    return true;
  }

  bool ReadSymbol(STGKGridOpenPositionRecord &source, string &value)
  {
    value = "";
    if(PropertyReadFails(FAKE_PROPERTY_SYMBOL))
      return false;

    value = source.symbol;
    return true;
  }

  bool ReadMagic(STGKGridOpenPositionRecord &source, long &value)
  {
    value = 0;
    if(PropertyReadFails(FAKE_PROPERTY_MAGIC))
      return false;

    value = source.magic_number;
    return true;
  }

  bool ReadVolume(STGKGridOpenPositionRecord &source, double &value)
  {
    value = 0.0;
    if(PropertyReadFails(FAKE_PROPERTY_VOLUME))
      return false;

    value = source.volume;
    return true;
  }

  virtual bool ReadSelectedPosition(STGKGridOpenPositionRecord &record)
  {
    record.position_identifier = "";
    record.ticket = 0;
    record.symbol = "";
    record.magic_number = 0;
    record.volume = 0.0;

    if(selected_index < 0 || selected_index == fail_read_index)
      return false;

    STGKGridOpenPositionRecord records[];
    CopyScan(current_scan, records);
    STGKGridOpenPositionRecord source = records[selected_index];

    long identifier = 0;
    long ticket_value = 0;
    string symbol = "";
    long magic_number = 0;
    double volume = 0.0;

    if(!ReadIdentifier(source, identifier) ||
       !ReadTicket(source, ticket_value) ||
       !ReadSymbol(source, symbol) ||
       !ReadMagic(source, magic_number) ||
       !ReadVolume(source, volume))
      return false;

    record.position_identifier = StringFormat("%I64d", identifier);
    record.ticket = (ulong)ticket_value;
    record.symbol = symbol;
    record.magic_number = magic_number;
    record.volume = volume;
    return true;
  }
};

void PushRecord(
  STGKGridOpenPositionRecord &records[],
  string position_identifier,
  ulong ticket,
  string symbol,
  long magic_number,
  double volume)
{
  int index = ArraySize(records);
  ArrayResize(records, index + 1);
  records[index].position_identifier = position_identifier;
  records[index].ticket = ticket;
  records[index].symbol = symbol;
  records[index].magic_number = magic_number;
  records[index].volume = volume;
}

void CopyRecords(
  STGKGridOpenPositionRecord &source[],
  STGKGridOpenPositionRecord &destination[])
{
  int total = ArraySize(source);
  ArrayResize(destination, total);
  for(int index = 0; index < total; index++)
    destination[index] = source[index];
}

void ReverseRecords(
  STGKGridOpenPositionRecord &source[],
  STGKGridOpenPositionRecord &destination[])
{
  int total = ArraySize(source);
  ArrayResize(destination, total);
  for(int index = 0; index < total; index++)
    destination[index] = source[total - 1 - index];
}

// One acquisition attempt with a scripted scan pair.
bool AcquirePair(
  STGKGridOpenPositionRecord &first[],
  STGKGridOpenPositionRecord &second[],
  STGKGridOpenPositionSnapshot &snapshot,
  long base_sequence = 0)
{
  CFakeOpenPositionSource source;
  CopyRecords(first, source.first_scan);
  CopyRecords(second, source.second_scan);

  CTGKGridOpenPositionAcquirer acquirer;
  if(!acquirer.Initialize(source, UT_SYMBOL, UT_MAGIC))
    return false;

  return acquirer.Acquire(base_sequence, snapshot);
}

void BuildOwnedPair(
  STGKGridOpenPositionRecord &first[],
  STGKGridOpenPositionRecord &second[])
{
  ArrayResize(first, 0);
  PushRecord(first, "3100001", 4100001, UT_SYMBOL, UT_MAGIC, 0.10);
  PushRecord(first, "3100002", 4100002, UT_SYMBOL, UT_MAGIC, 0.20);
  CopyRecords(first, second);
}

// Runs one acquisition over a scripted pair and reports the accepted status.
ENUM_TGK_GRID_OPEN_POSITION_STATUS AcquireStatus(
  STGKGridOpenPositionRecord &first[],
  STGKGridOpenPositionRecord &second[])
{
  STGKGridOpenPositionSnapshot snapshot;
  AcquirePair(first, second, snapshot);
  return snapshot.status;
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Open Position Snapshot");

  STGKGridOpenPositionRecord first[];
  STGKGridOpenPositionRecord second[];
  STGKGridOpenPositionRecord empty[];
  STGKGridOpenPositionSnapshot snapshot;

  Tests.BeginTest("C-01 two identical full scans accept the Snapshot");
  BuildOwnedPair(first, second);
  CFakeOpenPositionSource c01_source;
  CopyRecords(first, c01_source.first_scan);
  CopyRecords(second, c01_source.second_scan);

  CTGKGridOpenPositionAcquirer c01_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c01_acquirer.Initialize(c01_source, UT_SYMBOL, UT_MAGIC));
  Tests.AssertTrue("acquire stable Snapshot", c01_acquirer.Acquire(7, snapshot));
  Tests.AssertEqualInt(
    "Snapshot is COMPLETE",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_COMPLETE);
  Tests.AssertEqualInt("first scan total", snapshot.first_scan_total, 2);
  Tests.AssertEqualInt("second scan total", snapshot.second_scan_total, 2);
  Tests.AssertEqualLong(
    "accepted Snapshot carries the Base Sequence",
    snapshot.base_sequence,
    7);
  Tests.AssertEqualLong(
    "accepted Snapshot carries a positive Generation",
    snapshot.generation,
    1);
  Tests.AssertEqualInt("owned position count", c01_acquirer.OwnedCount(), 2);

  STGKGridOpenPositionRecord c01_owned[];
  Tests.AssertTrue(
    "copy owned positions",
    c01_acquirer.CopyOwnedPositions(c01_owned));
  Tests.AssertEqualString(
    "first Identifier preserved",
    c01_owned[0].position_identifier,
    "3100001");
  Tests.AssertEqualLong("first Ticket preserved", (long)c01_owned[0].ticket, 4100001);
  Tests.AssertEqualDouble("first Volume preserved", c01_owned[0].volume, 0.10);
  Tests.AssertEqualString("second Symbol preserved", c01_owned[1].symbol, UT_SYMBOL);
  Tests.AssertEqualLong(
    "second Magic preserved",
    c01_owned[1].magic_number,
    UT_MAGIC);
  Tests.EndTest();

  Tests.BeginTest("C-01 reversed enumeration order is accepted");
  ReverseRecords(first, second);
  Tests.AssertEqualInt(
    "reversed second scan is COMPLETE",
    (int)AcquireStatus(first, second),
    (int)TGK_GRID_OPEN_POSITION_COMPLETE);
  Tests.EndTest();

  Tests.BeginTest("C-02 failed enumeration rejects the Snapshot");
  CopyRecords(first, second);
  CFakeOpenPositionSource c02_source;
  CopyRecords(first, c02_source.first_scan);
  CopyRecords(second, c02_source.second_scan);
  c02_source.fail_total = true;
  CTGKGridOpenPositionAcquirer c02_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c02_acquirer.Initialize(c02_source, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "failed enumeration acquires nothing",
    c02_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "Snapshot is INVALID",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_INVALID);
  Tests.AssertEqualInt("no owned positions", c02_acquirer.OwnedCount(), 0);
  Tests.EndTest();

  Tests.BeginTest("C-02 zero Ticket rejects the Snapshot");
  CFakeOpenPositionSource c02_zero;
  CopyRecords(first, c02_zero.first_scan);
  CopyRecords(second, c02_zero.second_scan);
  c02_zero.zero_ticket_index = 1;
  CTGKGridOpenPositionAcquirer c02_zero_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c02_zero_acquirer.Initialize(c02_zero, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "zero Ticket acquires nothing",
    c02_zero_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "zero Ticket Snapshot is INVALID",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_INVALID);
  Tests.EndTest();

  Tests.BeginTest("C-02 failed Ticket enumeration rejects the Snapshot");
  CFakeOpenPositionSource c02_ticket;
  CopyRecords(first, c02_ticket.first_scan);
  CopyRecords(second, c02_ticket.second_scan);
  c02_ticket.fail_ticket_index = 0;
  CTGKGridOpenPositionAcquirer c02_ticket_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c02_ticket_acquirer.Initialize(c02_ticket, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "failed first enumeration index acquires nothing",
    c02_ticket_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "first-index failure is INVALID",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_INVALID);

  CFakeOpenPositionSource c02_last;
  CopyRecords(first, c02_last.first_scan);
  CopyRecords(second, c02_last.second_scan);
  c02_last.fail_ticket_index = 1;
  CTGKGridOpenPositionAcquirer c02_last_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c02_last_acquirer.Initialize(c02_last, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "failed last enumeration index acquires nothing",
    c02_last_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "last-index failure is INVALID",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_INVALID);
  Tests.EndTest();

  Tests.BeginTest("C-02 failed Ticket selection rejects the Snapshot");
  CFakeOpenPositionSource c02_select;
  CopyRecords(first, c02_select.first_scan);
  CopyRecords(second, c02_select.second_scan);
  c02_select.fail_select_index = 0;
  CTGKGridOpenPositionAcquirer c02_select_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c02_select_acquirer.Initialize(c02_select, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "failed selection acquires nothing",
    c02_select_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "selection failure is INVALID",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_INVALID);
  Tests.EndTest();

  Tests.BeginTest("C-02 failed required property read rejects the Snapshot");
  for(int property = FAKE_PROPERTY_IDENTIFIER;
      property <= FAKE_PROPERTY_VOLUME;
      property++)
  {
    CFakeOpenPositionSource c02_property;
    CopyRecords(first, c02_property.first_scan);
    CopyRecords(second, c02_property.second_scan);
    c02_property.fail_property_read_index = 0;
    c02_property.fail_property_read = property;

    CTGKGridOpenPositionAcquirer c02_property_acquirer;
    Tests.AssertTrue(
      StringFormat("initialize acquirer for property %d", property),
      c02_property_acquirer.Initialize(c02_property, UT_SYMBOL, UT_MAGIC));
    Tests.AssertFalse(
      StringFormat("unreadable property %d acquires nothing", property),
      c02_property_acquirer.Acquire(0, snapshot));
    Tests.AssertEqualInt(
      StringFormat("property %d failure is INVALID", property),
      (int)snapshot.status,
      (int)TGK_GRID_OPEN_POSITION_INVALID);
    Tests.AssertEqualInt(
      StringFormat("property %d failure leaves no Owned Position", property),
      c02_property_acquirer.OwnedCount(),
      0);
    Tests.AssertFalse(
      StringFormat("property %d failure yields no token", property),
      c02_property_acquirer.Consume(snapshot, 0));
  }

  CFakeOpenPositionSource c02_read;
  CopyRecords(first, c02_read.first_scan);
  CopyRecords(second, c02_read.second_scan);
  c02_read.fail_read_index = 0;
  CTGKGridOpenPositionAcquirer c02_read_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c02_read_acquirer.Initialize(c02_read, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "failed property read acquires nothing",
    c02_read_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "property read failure is INVALID",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_INVALID);
  Tests.EndTest();

  Tests.BeginTest("C-02 account total change during a scan rejects the Snapshot");
  CFakeOpenPositionSource c02_total_change;
  CopyRecords(first, c02_total_change.first_scan);
  CopyRecords(second, c02_total_change.second_scan);
  c02_total_change.total_delta_on_end_call = 1;
  CTGKGridOpenPositionAcquirer c02_total_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c02_total_acquirer.Initialize(c02_total_change, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "changing total acquires nothing",
    c02_total_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "changing total is INVALID",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_INVALID);
  Tests.EndTest();

  Tests.BeginTest("C-03 scan disagreement exhausts the bounded retry");
  Tests.AssertEqualInt(
    "different totals are UNSTABLE",
    (int)AcquireStatus(first, empty),
    (int)TGK_GRID_OPEN_POSITION_UNSTABLE);

  STGKGridOpenPositionRecord c03_added[];
  CopyRecords(first, c03_added);
  PushRecord(c03_added, "3100003", 4100003, UT_SYMBOL, UT_MAGIC, 0.30);
  Tests.AssertEqualInt(
    "added position is UNSTABLE",
    (int)AcquireStatus(first, c03_added),
    (int)TGK_GRID_OPEN_POSITION_UNSTABLE);

  STGKGridOpenPositionRecord c03_removed[];
  PushRecord(c03_removed, "3100001", 4100001, UT_SYMBOL, UT_MAGIC, 0.10);
  Tests.AssertEqualInt(
    "removed position is UNSTABLE",
    (int)AcquireStatus(first, c03_removed),
    (int)TGK_GRID_OPEN_POSITION_UNSTABLE);

  STGKGridOpenPositionRecord c03_ticket[];
  PushRecord(c03_ticket, "3100001", 4100011, UT_SYMBOL, UT_MAGIC, 0.10);
  PushRecord(c03_ticket, "3100002", 4100002, UT_SYMBOL, UT_MAGIC, 0.20);
  Tests.AssertEqualInt(
    "changed Ticket is UNSTABLE",
    (int)AcquireStatus(first, c03_ticket),
    (int)TGK_GRID_OPEN_POSITION_UNSTABLE);

  STGKGridOpenPositionRecord c03_volume[];
  PushRecord(c03_volume, "3100001", 4100001, UT_SYMBOL, UT_MAGIC, 0.15);
  PushRecord(c03_volume, "3100002", 4100002, UT_SYMBOL, UT_MAGIC, 0.20);
  Tests.AssertEqualInt(
    "changed Volume is UNSTABLE",
    (int)AcquireStatus(first, c03_volume),
    (int)TGK_GRID_OPEN_POSITION_UNSTABLE);

  STGKGridOpenPositionRecord c03_identifier[];
  PushRecord(c03_identifier, "3100011", 4100001, UT_SYMBOL, UT_MAGIC, 0.10);
  PushRecord(c03_identifier, "3100002", 4100002, UT_SYMBOL, UT_MAGIC, 0.20);
  Tests.AssertEqualInt(
    "changed Identifier is UNSTABLE",
    (int)AcquireStatus(first, c03_identifier),
    (int)TGK_GRID_OPEN_POSITION_UNSTABLE);
  Tests.EndTest();

  Tests.BeginTest("C-03 Owned set comparison ignores enumeration order only");
  // Both scans observe the same account membership; only the enumeration order
  // differs, so the pair is Stable even though a Foreign record is present.
  STGKGridOpenPositionRecord c03_ordered_first[];
  PushRecord(c03_ordered_first, "3100001", 4100001, UT_SYMBOL, UT_MAGIC, 0.10);
  PushRecord(c03_ordered_first, "3200001", 4200001, "EURUSD", UT_MAGIC, 0.10);
  PushRecord(c03_ordered_first, "3100002", 4100002, UT_SYMBOL, UT_MAGIC, 0.20);
  STGKGridOpenPositionRecord c03_ordered_second[];
  PushRecord(c03_ordered_second, "3100002", 4100002, UT_SYMBOL, UT_MAGIC, 0.20);
  PushRecord(c03_ordered_second, "3100001", 4100001, UT_SYMBOL, UT_MAGIC, 0.10);
  PushRecord(c03_ordered_second, "3200001", 4200001, "EURUSD", UT_MAGIC, 0.10);
  Tests.AssertEqualInt(
    "reordered set with a foreign record is COMPLETE",
    (int)AcquireStatus(c03_ordered_first, c03_ordered_second),
    (int)TGK_GRID_OPEN_POSITION_COMPLETE);
  Tests.EndTest();

  Tests.BeginTest("C-04 foreign Symbol and Magic never enter the Owned projection");
  STGKGridOpenPositionRecord c04_first[];
  PushRecord(c04_first, "3100001", 4100001, UT_SYMBOL, UT_MAGIC, 0.10);
  PushRecord(c04_first, "3200001", 4200001, "EURUSD", UT_MAGIC, 0.10);
  PushRecord(c04_first, "3200002", 4200002, UT_SYMBOL, 710999, 0.10);
  PushRecord(c04_first, "3200003", 4200003, UT_SYMBOL, 0, 0.10);
  PushRecord(c04_first, "3200004", 4200004, UT_SYMBOL, 710998, 0.10);
  STGKGridOpenPositionRecord c04_second[];
  CopyRecords(c04_first, c04_second);

  CFakeOpenPositionSource c04_source;
  CopyRecords(c04_first, c04_source.first_scan);
  CopyRecords(c04_second, c04_source.second_scan);
  CTGKGridOpenPositionAcquirer c04_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c04_acquirer.Initialize(c04_source, UT_SYMBOL, UT_MAGIC));
  Tests.AssertTrue("acquire Snapshot", c04_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt("account total covers every position", snapshot.first_scan_total, 5);
  Tests.AssertEqualInt("only the Owned position is projected", c04_acquirer.OwnedCount(), 1);

  STGKGridOpenPositionRecord c04_owned[];
  Tests.AssertTrue(
    "copy owned positions",
    c04_acquirer.CopyOwnedPositions(c04_owned));
  Tests.AssertEqualString(
    "owned Identifier",
    c04_owned[0].position_identifier,
    "3100001");
  Tests.EndTest();

  Tests.BeginTest("CR-01 a failed Magic Getter is never read as Magic 0");
  CFakeOpenPositionSource cr01_magic;
  CopyRecords(first, cr01_magic.first_scan);
  CopyRecords(second, cr01_magic.second_scan);
  cr01_magic.fail_property_read_index = 0;
  cr01_magic.fail_property_read = FAKE_PROPERTY_MAGIC;
  CTGKGridOpenPositionAcquirer cr01_magic_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    cr01_magic_acquirer.Initialize(cr01_magic, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "a failed Magic read rejects the Snapshot",
    cr01_magic_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "failed Magic read is INVALID",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_INVALID);
  Tests.AssertEqualInt(
    "failed Magic read leaves no Owned Position",
    cr01_magic_acquirer.OwnedCount(),
    0);
  Tests.AssertFalse(
    "failed Magic read yields no token",
    cr01_magic_acquirer.Consume(snapshot, 0));

  // A successfully read Magic 0 is a Foreign Position: it is filtered out of
  // the Owned set without failing the scan. That is the behaviour a failed
  // Getter must never be confused with.
  STGKGridOpenPositionRecord cr01_magic_zero[];
  PushRecord(cr01_magic_zero, "3100001", 4100001, UT_SYMBOL, UT_MAGIC, 0.10);
  PushRecord(cr01_magic_zero, "3200005", 4200005, UT_SYMBOL, 0, 0.10);
  CFakeOpenPositionSource cr01_foreign;
  CopyRecords(cr01_magic_zero, cr01_foreign.first_scan);
  CopyRecords(cr01_magic_zero, cr01_foreign.second_scan);
  CTGKGridOpenPositionAcquirer cr01_foreign_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    cr01_foreign_acquirer.Initialize(cr01_foreign, UT_SYMBOL, UT_MAGIC));
  Tests.AssertTrue(
    "a read Magic 0 position is only filtered out",
    cr01_foreign_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "the scan still completes",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_COMPLETE);
  Tests.AssertEqualInt(
    "only the Owned position remains",
    cr01_foreign_acquirer.OwnedCount(),
    1);
  Tests.EndTest();

  Tests.BeginTest("CR-01 every required Property Getter failure rejects the Snapshot");
  for(int property = FAKE_PROPERTY_IDENTIFIER;
      property <= FAKE_PROPERTY_VOLUME;
      property++)
  {
    CFakeOpenPositionSource property_source;
    CopyRecords(first, property_source.first_scan);
    CopyRecords(second, property_source.second_scan);
    property_source.fail_property_read_index = 0;
    property_source.fail_property_read = property;

    CTGKGridOpenPositionAcquirer property_acquirer;
    Tests.AssertTrue(
      StringFormat("initialize acquirer for Property %d", property),
      property_acquirer.Initialize(property_source, UT_SYMBOL, UT_MAGIC));
    Tests.AssertFalse(
      StringFormat("Property %d Getter failure rejects Acquire", property),
      property_acquirer.Acquire(0, snapshot));
    Tests.AssertEqualInt(
      StringFormat("Property %d failure leaves Snapshot INVALID", property),
      (int)snapshot.status,
      (int)TGK_GRID_OPEN_POSITION_INVALID);
    Tests.AssertEqualInt(
      StringFormat("Property %d failure leaves no Owned Positions", property),
      property_acquirer.OwnedCount(),
      0);
    Tests.AssertFalse(
      StringFormat("Property %d failure cannot Consume", property),
      property_acquirer.Consume(snapshot, 0));

    STGKGridOpenPositionRecord unavailable_positions[];
    Tests.AssertFalse(
      StringFormat("Property %d failure cannot transfer a trusted token", property),
      property_acquirer.TakeConsumedSnapshot(snapshot, unavailable_positions));
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-08 the consumed grant transfers only the Acquirer-owned Position Set");
  CFakeOpenPositionSource cr08_source;
  CopyRecords(first, cr08_source.first_scan);
  CopyRecords(second, cr08_source.second_scan);
  CTGKGridOpenPositionAcquirer cr08_acquirer;
  Tests.AssertTrue(
    "initialize Acquirer",
    cr08_acquirer.Initialize(cr08_source, UT_SYMBOL, UT_MAGIC));
  Tests.AssertTrue(
    "acquire complete Snapshot",
    cr08_acquirer.Acquire(0, snapshot));
  Tests.AssertTrue(
    "consume complete Snapshot",
    cr08_acquirer.Consume(snapshot, 0));

  STGKGridOpenPositionRecord trusted_positions[];
  Tests.AssertTrue(
    "transfer Acquirer-owned Position Set with its grant",
    cr08_acquirer.TakeConsumedSnapshot(snapshot, trusted_positions));
  Tests.AssertEqualInt("trusted Position count", ArraySize(trusted_positions), 2);
  Tests.AssertEqualString(
    "trusted first Identifier",
    trusted_positions[0].position_identifier,
    first[0].position_identifier);
  Tests.AssertEqualLong(
    "trusted first Ticket",
    (long)trusted_positions[0].ticket,
    (long)first[0].ticket);
  Tests.AssertEqualDouble(
    "trusted first Volume",
    trusted_positions[0].volume,
    first[0].volume,
    0.000001);
  Tests.AssertFalse(
    "the transferred grant cannot be replayed",
    cr08_acquirer.TakeConsumedSnapshot(snapshot, trusted_positions));
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-08 a failed newer Acquire invalidates an older consumed Snapshot");
  CFakeOpenPositionSource cr08_failed_source;
  CopyRecords(first, cr08_failed_source.first_scan);
  CopyRecords(second, cr08_failed_source.second_scan);
  CTGKGridOpenPositionAcquirer cr08_failed_acquirer;
  Tests.AssertTrue(
    "initialize Acquirer",
    cr08_failed_acquirer.Initialize(cr08_failed_source, UT_SYMBOL, UT_MAGIC));

  STGKGridOpenPositionSnapshot older_consumed;
  Tests.AssertTrue(
    "acquire older Snapshot",
    cr08_failed_acquirer.Acquire(0, older_consumed));
  Tests.AssertTrue(
    "consume older Snapshot",
    cr08_failed_acquirer.Consume(older_consumed, 0));

  cr08_failed_source.fail_total = true;
  STGKGridOpenPositionSnapshot failed_newer;
  Tests.AssertFalse(
    "newer failed acquisition is rejected",
    cr08_failed_acquirer.Acquire(0, failed_newer));
  Tests.AssertEqualInt(
    "failed newer acquisition leaves no Owned Positions",
    cr08_failed_acquirer.OwnedCount(),
    0);

  STGKGridOpenPositionRecord stale_positions[];
  Tests.AssertFalse(
    "older consumed grant cannot transfer after newer failed Acquire",
    cr08_failed_acquirer.TakeConsumedSnapshot(older_consumed, stale_positions));
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-03 an Account Total change between scans is UNSTABLE");
  STGKGridOpenPositionRecord cr03_owned[];
  STGKGridOpenPositionRecord cr03_owned_second[];
  BuildOwnedPair(cr03_owned, cr03_owned_second);

  STGKGridOpenPositionRecord cr03_foreign[];
  CopyRecords(cr03_owned, cr03_foreign);
  PushRecord(cr03_foreign, "3200001", 4200001, "EURUSD", UT_MAGIC, 0.10);

  CFakeOpenPositionSource cr03_source;
  CopyRecords(cr03_foreign, cr03_source.first_scan);
  CopyRecords(cr03_owned_second, cr03_source.second_scan);
  CTGKGridOpenPositionAcquirer cr03_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    cr03_acquirer.Initialize(cr03_source, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "an Account Total mismatch acquires nothing",
    cr03_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "Account Total mismatch is UNSTABLE",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_UNSTABLE);
  Tests.AssertEqualInt(
    "no Owned Position survives the mismatch",
    cr03_acquirer.OwnedCount(),
    0);
  Tests.AssertFalse(
    "an UNSTABLE pair yields no token",
    cr03_acquirer.Consume(snapshot, 0));
  Tests.EndTest();

  Tests.BeginTest("CR-03 a transient Account Total change recovers on retry");
  CFakeOpenPositionSource cr03_retry;
  CopyRecords(cr03_foreign, cr03_retry.first_scan);
  CopyRecords(cr03_owned_second, cr03_retry.second_scan);
  CopyRecords(cr03_owned_second, cr03_retry.retry_first_scan);
  CopyRecords(cr03_owned_second, cr03_retry.retry_second_scan);
  cr03_retry.has_retry_script = true;
  cr03_retry.retry_from_attempt = 1;

  CTGKGridOpenPositionAcquirer cr03_retry_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    cr03_retry_acquirer.Initialize(cr03_retry, UT_SYMBOL, UT_MAGIC));
  Tests.AssertTrue(
    "the Stable retry pair is accepted",
    cr03_retry_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "Snapshot is COMPLETE after the retry",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_COMPLETE);
  Tests.AssertEqualInt("retry pair first total", snapshot.first_scan_total, 2);
  Tests.AssertEqualInt("retry pair second total", snapshot.second_scan_total, 2);
  Tests.AssertEqualInt(
    "two scan pairs were observed",
    cr03_retry.AttemptCount(),
    2);
  Tests.AssertEqualInt(
    "both Owned positions are kept",
    cr03_retry_acquirer.OwnedCount(),
    2);
  Tests.EndTest();

  Tests.BeginTest("CR-03 an Account Total mismatch on every attempt fails closed");
  CFakeOpenPositionSource cr03_exhausted;
  CopyRecords(cr03_foreign, cr03_exhausted.first_scan);
  CopyRecords(cr03_owned_second, cr03_exhausted.second_scan);
  CTGKGridOpenPositionAcquirer cr03_exhausted_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    cr03_exhausted_acquirer.Initialize(cr03_exhausted, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "an exhausted retry acquires nothing",
    cr03_exhausted_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "exhausted retry is UNSTABLE",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_UNSTABLE);
  Tests.AssertEqualInt(
    "the retry is bounded by the configured maximum",
    cr03_exhausted.AttemptCount(),
    TGK_GRID_OPEN_POSITION_MAX_ATTEMPTS);
  Tests.AssertEqualInt(
    "no Owned Position survives an exhausted retry",
    cr03_exhausted_acquirer.OwnedCount(),
    0);
  Tests.AssertFalse(
    "an exhausted retry yields no token",
    cr03_exhausted_acquirer.Consume(snapshot, 0));
  Tests.EndTest();

  Tests.BeginTest("Empty Snapshot is accepted only after two successful zero scans");
  CFakeOpenPositionSource c05_empty;
  CTGKGridOpenPositionAcquirer c05_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c05_acquirer.Initialize(c05_empty, UT_SYMBOL, UT_MAGIC));
  Tests.AssertTrue(
    "empty account acquires a Snapshot",
    c05_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "empty Snapshot is COMPLETE",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_COMPLETE);
  Tests.AssertEqualInt("empty first total", snapshot.first_scan_total, 0);
  Tests.AssertEqualInt("empty second total", snapshot.second_scan_total, 0);
  Tests.AssertEqualInt("no owned positions", c05_acquirer.OwnedCount(), 0);
  Tests.EndTest();

  Tests.BeginTest("Empty result is never produced by a failed scan");
  CFakeOpenPositionSource c05_failed;
  c05_failed.fail_total = true;
  CTGKGridOpenPositionAcquirer c05_failed_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c05_failed_acquirer.Initialize(c05_failed, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "failed scan acquires nothing",
    c05_failed_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "failed scan is not COMPLETE",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_INVALID);

  CFakeOpenPositionSource c05_unstable;
  CopyRecords(first, c05_unstable.first_scan);
  PushRecord(c05_unstable.second_scan, "3100001", 4100001, UT_SYMBOL, UT_MAGIC, 0.10);
  CTGKGridOpenPositionAcquirer c05_unstable_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c05_unstable_acquirer.Initialize(c05_unstable, UT_SYMBOL, UT_MAGIC));
  Tests.AssertFalse(
    "unstable scan acquires nothing",
    c05_unstable_acquirer.Acquire(0, snapshot));
  Tests.AssertEqualInt(
    "unstable scan is not COMPLETE",
    (int)snapshot.status,
    (int)TGK_GRID_OPEN_POSITION_UNSTABLE);
  Tests.EndTest();

  Tests.BeginTest("Consume rejects used, superseded and stale tokens");
  CopyRecords(first, second);
  CFakeOpenPositionSource c06_source;
  CopyRecords(first, c06_source.first_scan);
  CopyRecords(second, c06_source.second_scan);
  CTGKGridOpenPositionAcquirer c06_acquirer;
  Tests.AssertTrue(
    "initialize acquirer",
    c06_acquirer.Initialize(c06_source, UT_SYMBOL, UT_MAGIC));

  STGKGridOpenPositionSnapshot c06_snapshot;
  Tests.AssertTrue("acquire token", c06_acquirer.Acquire(4, c06_snapshot));
  Tests.AssertFalse(
    "Consume rejects a stale Base Sequence",
    c06_acquirer.Consume(c06_snapshot, 5));
  Tests.AssertTrue("Consume accepts the matching sequence", c06_acquirer.Consume(c06_snapshot, 4));
  Tests.AssertFalse(
    "the same token cannot be consumed twice",
    c06_acquirer.Consume(c06_snapshot, 4));
  STGKGridOpenPositionRecord c06_positions[];
  Tests.AssertTrue(
    "the consumed token transfers the trusted Position Set once",
    c06_acquirer.TakeConsumedSnapshot(c06_snapshot, c06_positions));
  Tests.AssertEqualInt("the trusted Position Set is complete", ArraySize(c06_positions), 2);
  Tests.AssertFalse(
    "the Diff grant cannot be transferred twice",
    c06_acquirer.TakeConsumedSnapshot(c06_snapshot, c06_positions));

  STGKGridOpenPositionSnapshot c06_superseded;
  Tests.AssertTrue(
    "acquire a newer token",
    c06_acquirer.Acquire(4, c06_superseded));
  Tests.AssertFalse(
    "an older in-memory token is rejected",
    c06_acquirer.Consume(c06_snapshot, 4));
  Tests.AssertTrue(
    "the latest token is accepted",
    c06_acquirer.Consume(c06_superseded, 4));

  STGKGridOpenPositionSnapshot c06_unsuccessful;
  c06_source.fail_total = true;
  Tests.AssertFalse(
    "failed acquisition produces no token",
    c06_acquirer.Acquire(4, c06_unsuccessful));
  Tests.AssertFalse(
    "a failed acquisition cannot be consumed",
    c06_acquirer.Consume(c06_unsuccessful, 4));
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
