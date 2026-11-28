#ifndef BOTTRADE_GRID_OPEN_POSITION_SNAPSHOT_MQH
#define BOTTRADE_GRID_OPEN_POSITION_SNAPSHOT_MQH

// Authoritative Open Position Snapshot for Grid Reconciliation.
//
// This module only reads account positions. It never sends, modifies, selects
// for trading or closes anything, and it never turns a failed, incomplete or
// unstable observation into an empty result. A Snapshot is accepted only after
// two full account scans inside one serialized EA event agree on the complete
// Owned Position Set.

#define TGK_GRID_OPEN_POSITION_MAX_RECORDS 4096
#define TGK_GRID_OPEN_POSITION_MAX_ATTEMPTS 3
#define TGK_GRID_OPEN_POSITION_VOLUME_EPSILON 0.00000001

enum ENUM_TGK_GRID_OPEN_POSITION_STATUS
{
  // Enumeration, Ticket selection or a required property read failed.
  TGK_GRID_OPEN_POSITION_INVALID = 0,
  // Both scans succeeded but disagreed, and the bounded retry was exhausted.
  TGK_GRID_OPEN_POSITION_UNSTABLE,
  // Both scans succeeded and agreed on the complete Owned Position Set.
  TGK_GRID_OPEN_POSITION_COMPLETE
};

// One live position as observed by a full account scan. The Identifier is the
// canonical lifecycle identity; the Ticket is only its current operational
// handle.
struct STGKGridOpenPositionRecord
{
  string position_identifier;
  ulong ticket;
  string symbol;
  long magic_number;
  double volume;
};

// Envelope of one accepted or rejected acquisition. The record set itself is
// held by the Acquirer, so this envelope stays a plain value type.
struct STGKGridOpenPositionSnapshot
{
  ENUM_TGK_GRID_OPEN_POSITION_STATUS status;
  string symbol;
  long magic_number;
  int first_scan_total;
  int second_scan_total;
  long generation;
  long base_sequence;
  bool consumed;
};

// Canonical Position Identifier literal: decimal digits only, never zero.
bool TGKGridIsDecimalPositionIdentifier(string value)
{
  int length = StringLen(value);
  if(length <= 0 || value == "0")
    return false;

  for(int index = 0; index < length; index++)
  {
    ushort character = StringGetCharacter(value, index);
    if(character < '0' || character > '9')
      return false;
  }

  return true;
}

// Minimal read-only account port. Production implements it with the MT5
// Position API; tests implement it with scripted scans.
class CTGKGridOpenPositionSource
{
public:
  // Number of positions the account currently reports.
  virtual bool TotalPositions(int &total)
  {
    total = -1;
    return false;
  }

  // Operational Ticket of one enumeration index.
  virtual bool TicketAt(int index, ulong &ticket)
  {
    ticket = 0;
    return false;
  }

  // Makes the Ticket's properties readable for the following read.
  virtual bool SelectTicket(ulong ticket)
  {
    return false;
  }

  // Reads the required properties of the currently selected position.
  virtual bool ReadSelectedPosition(STGKGridOpenPositionRecord &record)
  {
    record.position_identifier = "";
    record.ticket = 0;
    record.symbol = "";
    record.magic_number = 0;
    record.volume = 0.0;
    return false;
  }
};

// Production read-only adapter. It uses PositionsTotal, PositionGetTicket,
// PositionSelectByTicket and the Position property getters only.
class CTGKGridMT5OpenPositionSource : public CTGKGridOpenPositionSource
{
public:
  virtual bool TotalPositions(int &total)
  {
    total = PositionsTotal();
    return total >= 0;
  }

  virtual bool TicketAt(int index, ulong &ticket)
  {
    ticket = 0;
    if(index < 0)
      return false;

    ticket = PositionGetTicket(index);
    return ticket != 0;
  }

  virtual bool SelectTicket(ulong ticket)
  {
    return ticket != 0 && PositionSelectByTicket(ticket);
  }

  // Every required property is read through its Boolean overload. A failed
  // Getter rejects the whole read, because a default value must never be
  // accepted as a successful read: a Magic Getter that failed would otherwise
  // yield Magic 0, reclassify a Grid-owned Position as a Foreign Position and
  // turn its still-open Mapping into a false Full Close.
  virtual bool ReadSelectedPosition(STGKGridOpenPositionRecord &record)
  {
    record.position_identifier = "";
    record.ticket = 0;
    record.symbol = "";
    record.magic_number = 0;
    record.volume = 0.0;

    long identifier = 0;
    if(!PositionGetInteger(POSITION_IDENTIFIER, identifier))
      return false;

    long ticket_value = 0;
    if(!PositionGetInteger(POSITION_TICKET, ticket_value))
      return false;

    string symbol = "";
    if(!PositionGetString(POSITION_SYMBOL, symbol))
      return false;

    long magic_number = 0;
    if(!PositionGetInteger(POSITION_MAGIC, magic_number))
      return false;

    double volume = 0.0;
    if(!PositionGetDouble(POSITION_VOLUME, volume))
      return false;

    if(identifier <= 0 ||
       ticket_value <= 0 ||
       symbol == "" ||
       magic_number < 0 ||
       !MathIsValidNumber(volume) ||
       volume <= 0.0)
      return false;

    record.position_identifier = StringFormat("%I64d", identifier);
    record.ticket = (ulong)ticket_value;
    record.symbol = symbol;
    record.magic_number = magic_number;
    record.volume = volume;
    return true;
  }
};

// Stable two-scan acquisition. Both scans run inside one call, so an accepted
// Snapshot can never be queued or applied after a newer Reconciliation/Entry
// transition.
class CTGKGridOpenPositionAcquirer
{
private:
  CTGKGridOpenPositionSource *m_source;
  string m_symbol;
  long m_magic_number;
  int m_max_attempts;
  long m_generation;
  long m_accepted_generation;
  long m_consumed_generation;
  long m_consumed_base_sequence;
  bool m_consumed;
  bool m_initialized;
  STGKGridOpenPositionRecord m_owned[];

  void ClearOwned()
  {
    ArrayResize(m_owned, 0);
  }

  void ResetSnapshot(STGKGridOpenPositionSnapshot &snapshot)
  {
    snapshot.status = TGK_GRID_OPEN_POSITION_INVALID;
    snapshot.symbol = "";
    snapshot.magic_number = 0;
    snapshot.first_scan_total = 0;
    snapshot.second_scan_total = 0;
    snapshot.generation = 0;
    snapshot.base_sequence = 0;
    snapshot.consumed = false;
  }

  // One full account scan. Every enumerated index must yield a non-zero
  // Ticket, a successful selection and every required property, and the
  // account total must be unchanged by the end of the scan.
  bool CaptureScan(
    STGKGridOpenPositionRecord &records[],
    int &scan_total)
  {
    ArrayResize(records, 0);
    scan_total = 0;

    if(CheckPointer(m_source) == POINTER_INVALID)
      return false;

    int total = -1;
    if(!m_source.TotalPositions(total) ||
       total < 0 ||
       total > TGK_GRID_OPEN_POSITION_MAX_RECORDS)
      return false;

    for(int index = 0; index < total; index++)
    {
      ulong ticket = 0;
      if(!m_source.TicketAt(index, ticket) || ticket == 0)
        return false;

      if(!m_source.SelectTicket(ticket))
        return false;

      STGKGridOpenPositionRecord record;
      if(!m_source.ReadSelectedPosition(record))
        return false;

      if(record.ticket != ticket ||
         record.symbol == "" ||
         record.magic_number < 0 ||
         !MathIsValidNumber(record.volume) ||
         record.volume <= 0.0 ||
         !TGKGridIsDecimalPositionIdentifier(record.position_identifier))
        return false;

      for(int previous = 0; previous < ArraySize(records); previous++)
      {
        if(records[previous].ticket == ticket ||
           records[previous].position_identifier ==
             record.position_identifier)
          return false;
      }

      int position_index = ArraySize(records);
      if(ArrayResize(records, position_index + 1) != position_index + 1)
        return false;
      records[position_index] = record;
    }

    int total_after = -1;
    if(!m_source.TotalPositions(total_after) || total_after != total)
      return false;

    scan_total = total;
    return true;
  }

  // Exact Symbol + Instance Magic filter, applied only after a full account
  // scan already passed its own validation.
  bool BuildOwnedSet(
    STGKGridOpenPositionRecord &records[],
    STGKGridOpenPositionRecord &owned[])
  {
    ArrayResize(owned, 0);

    for(int index = 0; index < ArraySize(records); index++)
    {
      if(records[index].symbol != m_symbol ||
         records[index].magic_number != m_magic_number)
        continue;

      int owned_index = ArraySize(owned);
      if(ArrayResize(owned, owned_index + 1) != owned_index + 1)
        return false;
      owned[owned_index] = records[index];
    }

    return true;
  }

  // Order-independent Owned Position Set comparison. Identifier, Ticket,
  // Symbol, Magic and Volume must all agree.
  bool SetsMatch(
    STGKGridOpenPositionRecord &left[],
    STGKGridOpenPositionRecord &right[])
  {
    int total = ArraySize(left);
    if(total != ArraySize(right))
      return false;

    for(int index = 0; index < total; index++)
    {
      int match = -1;
      for(int other = 0; other < total; other++)
      {
        if(right[other].position_identifier ==
           left[index].position_identifier)
        {
          match = other;
          break;
        }
      }

      if(match < 0)
        return false;

      if(right[match].ticket != left[index].ticket ||
         right[match].symbol != left[index].symbol ||
         right[match].magic_number != left[index].magic_number ||
         MathAbs(right[match].volume - left[index].volume) >
           TGK_GRID_OPEN_POSITION_VOLUME_EPSILON)
        return false;
    }

    return true;
  }

public:
  CTGKGridOpenPositionAcquirer()
  {
    m_source = NULL;
    m_symbol = "";
    m_magic_number = 0;
    m_max_attempts = TGK_GRID_OPEN_POSITION_MAX_ATTEMPTS;
    m_generation = 0;
    m_accepted_generation = 0;
    m_consumed_generation = 0;
    m_consumed_base_sequence = 0;
    m_consumed = false;
    m_initialized = false;
  }

  bool Initialize(
    CTGKGridOpenPositionSource &source,
    string symbol,
    long magic_number)
  {
    m_initialized = false;
    m_source = GetPointer(source);
    m_symbol = "";
    m_magic_number = 0;
    m_generation = 0;
    m_accepted_generation = 0;
    m_consumed_generation = 0;
    m_consumed_base_sequence = 0;
    m_consumed = false;
    ClearOwned();

    if(CheckPointer(m_source) == POINTER_INVALID ||
       symbol == "" ||
       magic_number <= 0)
      return false;

    m_symbol = symbol;
    m_magic_number = magic_number;
    m_initialized = true;
    return true;
  }

  // Bounded retry policy. Only a scan disagreement is retried; a failed
  // enumeration, Ticket selection or property read rejects the Snapshot.
  bool SetMaxAttemptsForTest(int attempts)
  {
    if(attempts < 1 || attempts > 10)
      return false;

    m_max_attempts = attempts;
    return true;
  }

  // Runs both full scans. On success the Acquirer retains the accepted Owned
  // Position Set and the Snapshot carries its generation and the Reducer Base
  // Sequence captured at acquisition start. Reconciliation receives the Set
  // only through the single-use TakeConsumedSnapshot() hand-off.
  bool Acquire(
    long base_sequence,
    STGKGridOpenPositionSnapshot &snapshot)
  {
    ResetSnapshot(snapshot);
    snapshot.symbol = m_symbol;
    snapshot.magic_number = m_magic_number;
    snapshot.base_sequence = base_sequence;

    // Any new acquisition attempt supersedes every prior accepted/consumed
    // Snapshot, including when the new attempt later fails.
    m_consumed = false;
    m_consumed_generation = 0;
    m_consumed_base_sequence = 0;
    m_accepted_generation = 0;
    ClearOwned();

    if(!m_initialized || base_sequence < 0)
      return false;

    m_generation++;
    snapshot.generation = m_generation;

    bool unstable = false;

    for(int attempt = 0; attempt < m_max_attempts; attempt++)
    {
      STGKGridOpenPositionRecord first_scan[];
      STGKGridOpenPositionRecord second_scan[];
      int first_total = 0;
      int second_total = 0;

      if(!CaptureScan(first_scan, first_total) ||
         !CaptureScan(second_scan, second_total))
      {
        snapshot.first_scan_total = first_total;
        snapshot.second_scan_total = second_total;
        ClearOwned();
        return false;
      }

      snapshot.first_scan_total = first_total;
      snapshot.second_scan_total = second_total;

      STGKGridOpenPositionRecord first_owned[];
      STGKGridOpenPositionRecord second_owned[];
      if(!BuildOwnedSet(first_scan, first_owned) ||
         !BuildOwnedSet(second_scan, second_owned))
      {
        ClearOwned();
        return false;
      }

      // A Scan pair is Stable only when both full scans observed the same
      // account membership and the same Owned Position Set. A differing
      // account total means membership changed while the pair was observed, so
      // the pair is retried rather than accepted. An empty Owned set is still
      // accepted only when both scans reported a zero account total.
      bool totals_match = first_total == second_total;
      bool empty_with_nonzero_total =
        ArraySize(first_owned) == 0 &&
        (first_total != 0 || second_total != 0);

      if(!totals_match ||
         !SetsMatch(first_owned, second_owned) ||
         empty_with_nonzero_total)
      {
        unstable = true;
        continue;
      }

      ClearOwned();
      int owned_count = ArraySize(first_owned);
      if(ArrayResize(m_owned, owned_count) != owned_count)
        return false;

      for(int index = 0; index < owned_count; index++)
        m_owned[index] = first_owned[index];

      snapshot.status = TGK_GRID_OPEN_POSITION_COMPLETE;
      m_accepted_generation = m_generation;
      return true;
    }

    snapshot.status = unstable
                      ? TGK_GRID_OPEN_POSITION_UNSTABLE
                      : TGK_GRID_OPEN_POSITION_INVALID;
    ClearOwned();
    return false;
  }

  // Consumes the Accepted Snapshot exactly once. A used token, a token that is
  // not the Latest Accepted Generation, or a Base Sequence that no longer
  // matches the Reducer is rejected before any state mutation.
  bool Consume(
    STGKGridOpenPositionSnapshot &snapshot,
    long current_reducer_sequence)
  {
    if(!m_initialized ||
       snapshot.status != TGK_GRID_OPEN_POSITION_COMPLETE ||
       snapshot.consumed ||
       m_consumed ||
       snapshot.generation != m_generation ||
       snapshot.generation != m_accepted_generation ||
       snapshot.base_sequence != current_reducer_sequence ||
       current_reducer_sequence < 0 ||
       snapshot.symbol != m_symbol ||
       snapshot.magic_number != m_magic_number)
      return false;

    m_consumed = true;
    snapshot.consumed = true;
    m_consumed_generation = snapshot.generation;
    m_consumed_base_sequence = snapshot.base_sequence;
    return true;
  }

  // Atomically transfers the Acquirer's trusted Owned Position Set together
  // with the single-use consumed grant. Caller-provided Position arrays are
  // never used as reconciliation evidence.
  bool TakeConsumedSnapshot(
    STGKGridOpenPositionSnapshot &snapshot,
    STGKGridOpenPositionRecord &records[])
  {
    if(!m_initialized || m_consumed_generation <= 0)
      return false;

    if(snapshot.status != TGK_GRID_OPEN_POSITION_COMPLETE ||
       snapshot.generation != m_generation ||
       snapshot.generation != m_consumed_generation ||
       snapshot.generation != m_accepted_generation ||
       snapshot.base_sequence != m_consumed_base_sequence ||
       snapshot.symbol != m_symbol ||
       snapshot.magic_number != m_magic_number)
      return false;

    int total = ArraySize(m_owned);
    if(ArrayResize(records, total) != total)
      return false;

    for(int index = 0; index < total; index++)
      records[index] = m_owned[index];

    // Consume the grant only after the trusted Position Set was copied.
    m_consumed_generation = 0;
    m_consumed_base_sequence = 0;
    return true;
  }

  bool CopyOwnedPositions(STGKGridOpenPositionRecord &records[])
  {
    int total = ArraySize(m_owned);
    if(ArrayResize(records, total) != total)
      return false;

    for(int index = 0; index < total; index++)
      records[index] = m_owned[index];

    return true;
  }

  int OwnedCount()
  {
    return ArraySize(m_owned);
  }

  bool TryGetOwnedAt(
    int index,
    STGKGridOpenPositionRecord &record)
  {
    if(index < 0 || index >= ArraySize(m_owned))
      return false;

    record = m_owned[index];
    return true;
  }

  long Generation()
  {
    return m_generation;
  }

  long AcceptedGeneration()
  {
    return m_accepted_generation;
  }

  bool IsConsumed()
  {
    return m_consumed;
  }

  bool IsInitialized()
  {
    return m_initialized;
  }
};

#endif
