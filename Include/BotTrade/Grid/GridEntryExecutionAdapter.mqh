#ifndef BOTTRADE_GRID_ENTRY_EXECUTION_ADAPTER_MQH
#define BOTTRADE_GRID_ENTRY_EXECUTION_ADAPTER_MQH

#include <Trade/Trade.mqh>

#include <BotTrade/Grid/GridEntryExecutionPolicy.mqh>
#include <BotTrade/Grid/GridEntryMappingReducer.mqh>
#include <BotTrade/Grid/GridLevelRuntimeCoordinator.mqh>
#include <BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh>

enum ENUM_TGK_GRID_ENTRY_EXECUTION_STATUS
{
  TGK_GRID_ENTRY_EXECUTION_STATUS_NOT_SENT = 0,
  TGK_GRID_ENTRY_EXECUTION_STATUS_RECORDED,
  TGK_GRID_ENTRY_EXECUTION_STATUS_RECOVERY_REQUIRED
};

struct STGKGridEntryExecutionOutcome
{
  string request_id;
  string execution_outcome;
  string order_ticket;
  string deal_ticket;
  uint retcode;
  bool trade_return;
  bool requires_reconciliation;
  bool recovery_required;
  ENUM_TGK_GRID_ENTRY_EXECUTION_STATUS status;
};

// Port boundary used by the Adapter; Unit Tests provide an in-memory fake.
interface ITGKGridEntryExecutionPort
{
  bool NextSequence(long &next_sequence);
  bool AppendRecord(
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    const string payload
  );
  bool SendMarketOrder(
    bool is_buy,
    string symbol,
    double volume,
    long magic_number,
    string comment,
    uint &result_retcode,
    string &order_ticket,
    string &deal_ticket
  );
};

// Production port. This is the only WP-03 component that calls CTrade.
class CTGKGridEntryCTradePort : public ITGKGridEntryExecutionPort
{
private:
  CTGKGridEntryMappingSnapshotStorage m_storage;
  CTrade m_trader;
  string m_symbol;
  long m_magic_number;
  bool m_initialized;

public:
  CTGKGridEntryCTradePort()
  {
    m_symbol = "";
    m_magic_number = 0;
    m_initialized = false;
  }

  bool Initialize(
    string symbol,
    string instance_id,
    long magic_number,
    string initial_snapshot_payload,
    long checkpoint_sequence
  )
  {
    m_initialized = false;
    if(symbol == "" || instance_id == "" || magic_number <= 0)
      return false;

    if(!m_storage.Initialize(symbol, instance_id))
      return false;
    if(!m_storage.HasCommittedState() &&
       !m_storage.Bootstrap(
         initial_snapshot_payload,
         checkpoint_sequence))
      return false;
    if(m_storage.RecoveryStatus() != TGK_GRID_MAPPING_STATUS_NORMAL)
      return false;

    m_trader.SetExpertMagicNumber((ulong)magic_number);
    m_trader.SetAsyncMode(false);
    m_symbol = symbol;
    m_magic_number = magic_number;
    m_initialized = true;
    return true;
  }

  virtual bool AppendRecord(
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    const string payload
  )
  {
    return m_initialized && m_storage.Append(record_type, payload);
  }

  virtual bool NextSequence(long &next_sequence)
  {
    next_sequence = 0;
    if(!m_initialized)
      return false;

    string snapshot_payload;
    long checkpoint_sequence = 0;
    STGKGridMappingJournalRecord records[];
    int record_count = 0;
    return m_storage.Replay(
             snapshot_payload,
             checkpoint_sequence,
             records,
             record_count,
             next_sequence) &&
           m_storage.RecoveryStatus() == TGK_GRID_MAPPING_STATUS_NORMAL;
  }

  virtual bool SendMarketOrder(
    bool is_buy,
    string symbol,
    double volume,
    long magic_number,
    string comment,
    uint &result_retcode,
    string &order_ticket,
    string &deal_ticket
  )
  {
    result_retcode = 0;
    order_ticket = "0";
    deal_ticket = "0";
    if(!m_initialized ||
       symbol != m_symbol ||
       magic_number != m_magic_number)
      return false;

    bool request_sent = false;
    if(is_buy)
      request_sent = m_trader.Buy(
        volume,
        symbol,
        0.0,
        0.0,
        0.0,
        comment);
    else
      request_sent = m_trader.Sell(
        volume,
        symbol,
        0.0,
        0.0,
        0.0,
        comment);

    result_retcode = m_trader.ResultRetcode();
    if(request_sent)
    {
      order_ticket = StringFormat("%I64u", m_trader.ResultOrder());
      deal_ticket = StringFormat("%I64u", m_trader.ResultDeal());
    }
    return request_sent;
  }
};

// Persists an Entry Intent before the port can issue a market request.
// Accepted server outcomes stay unresolved until Position Reconciliation.
class CTGKGridEntryExecutionAdapter
{
private:
  bool m_initialized;
  bool m_recovery_required;

  void ResetOutcome(STGKGridEntryExecutionOutcome &outcome)
  {
    outcome.request_id = "";
    outcome.execution_outcome = "";
    outcome.order_ticket = "0";
    outcome.deal_ticket = "0";
    outcome.retcode = 0;
    outcome.trade_return = false;
    outcome.requires_reconciliation = false;
    outcome.recovery_required = false;
    outcome.status = TGK_GRID_ENTRY_EXECUTION_STATUS_NOT_SENT;
  }

  bool IsToken(string value)
  {
    return value != "" &&
           StringFind(value, "|") < 0 &&
           StringFind(value, "\n") < 0 &&
           StringFind(value, "\r") < 0;
  }

  string ModeToken(ENUM_TGK_GRID_MODE mode)
  {
    if(mode == TGK_GRID_MODE_BUY)
      return "BUY";
    if(mode == TGK_GRID_MODE_SELL)
      return "SELL";
    return "";
  }

  string TargetKind(const STGKGridEntryTargetLevel &target_level)
  {
    return target_level.is_anchor ? "ANCHOR" : "LEVEL";
  }

  string BuildComment(
    const STGKGridEntryExecutionCandidate &candidate
  )
  {
    if(candidate.target_level.is_anchor)
      return StringFormat("TGK GRID %s ANCHOR", ModeToken(candidate.mode));
    return StringFormat(
      "TGK GRID %s L%d",
      ModeToken(candidate.mode),
      candidate.target_level.level_index);
  }

  string ClassifyOutcome(bool trade_return, uint retcode)
  {
    if(!trade_return)
      return "FAILED";

    if(retcode == TRADE_RETCODE_DONE)
      return "DONE";
    if(retcode == TRADE_RETCODE_DONE_PARTIAL)
      return "DONE_PARTIAL";
    if(retcode == TRADE_RETCODE_PLACED)
      return "PLACED";
    if(retcode == TRADE_RETCODE_MARKET_CLOSED)
      return "MARKET_CLOSED";
    return "REJECTED";
  }

  bool AppendAndApply(
    ITGKGridEntryExecutionPort &port,
    CTGKGridEntryMappingReducer &reducer,
    long expected_sequence,
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    string payload
  )
  {
    long next_sequence = 0;
    if(expected_sequence <= 0 ||
       !port.NextSequence(next_sequence) ||
       next_sequence != expected_sequence ||
       expected_sequence != reducer.LastSequence() + 1 ||
       !port.AppendRecord(record_type, payload))
      return false;

    STGKGridMappingJournalRecord record;
    record.sequence = expected_sequence;
    record.record_type = record_type;
    record.payload = payload;
    STGKGridMappingJournalRecord records[];
    ArrayResize(records, 1);
    records[0] = record;
    return reducer.Replay(records, 1);
  }

  void SetRecoveryRequired(STGKGridEntryExecutionOutcome &outcome)
  {
    m_recovery_required = true;
    outcome.recovery_required = true;
    outcome.status = TGK_GRID_ENTRY_EXECUTION_STATUS_RECOVERY_REQUIRED;
  }

public:
  CTGKGridEntryExecutionAdapter()
  {
    m_initialized = false;
    m_recovery_required = false;
  }

  bool Initialize()
  {
    m_initialized = true;
    m_recovery_required = false;
    return true;
  }

  bool Execute(
    const STGKGridEntryExecutionCandidate &candidate,
    double requested_volume,
    const STGKGridEntryExecutionResult &policy_result,
    CTGKGridEntryMappingReducer &reducer,
    ITGKGridEntryExecutionPort &port,
    STGKGridEntryExecutionOutcome &outcome
  )
  {
    ResetOutcome(outcome);
    if(!m_initialized ||
       m_recovery_required ||
       policy_result.decision != TGK_GRID_ENTRY_DECISION_ALLOW ||
       policy_result.reason_code != TGK_GRID_ENTRY_REASON_ELIGIBLE ||
       policy_result.target_level.is_anchor != candidate.target_level.is_anchor ||
       policy_result.target_level.level_index != candidate.target_level.level_index ||
       !MathIsValidNumber(requested_volume) ||
       requested_volume <= 0.0 ||
       !MathIsValidNumber(candidate.entry_price) ||
       candidate.entry_price <= 0.0 ||
       candidate.magic_number <= 0 ||
       candidate.config_epoch <= 0 ||
       !IsToken(candidate.instance_id) ||
       !IsToken(candidate.symbol) ||
       ModeToken(candidate.mode) == "" ||
       !reducer.MatchesContext(
         candidate.instance_id,
         candidate.symbol,
         candidate.magic_number,
         candidate.mode,
         candidate.config_epoch) ||
       reducer.HasUnresolvedRequest())
      return false;

    if((candidate.target_level.is_anchor &&
        candidate.target_level.level_index != -1) ||
       (!candidate.target_level.is_anchor &&
        candidate.target_level.level_index < 0))
      return false;

    long intent_sequence = 0;
    if(!port.NextSequence(intent_sequence) ||
       intent_sequence <= 0 ||
       intent_sequence != reducer.LastSequence() + 1)
    {
      SetRecoveryRequired(outcome);
      return false;
    }

    string request_id = StringFormat(
      "%s-REQ-%I64d",
      candidate.instance_id,
      intent_sequence);
    string intent_payload = StringFormat(
      "v1|%s|%s|%I64d|%s|%s|%d|%.8f|%I64d|%s",
      request_id,
      candidate.symbol,
      candidate.magic_number,
      ModeToken(candidate.mode),
      TargetKind(candidate.target_level),
      candidate.target_level.level_index,
      requested_volume,
      candidate.config_epoch,
      candidate.instance_id);

    outcome.request_id = request_id;
    if(!AppendAndApply(
      port,
      reducer,
      intent_sequence,
      TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
      intent_payload))
    {
      SetRecoveryRequired(outcome);
      return false;
    }

    uint retcode = 0;
    string order_ticket = "0";
    string deal_ticket = "0";
    bool trade_return = port.SendMarketOrder(
      candidate.mode == TGK_GRID_MODE_BUY,
      candidate.symbol,
      requested_volume,
      candidate.magic_number,
      BuildComment(candidate),
      retcode,
      order_ticket,
      deal_ticket);
    if(!trade_return)
    {
      order_ticket = "0";
      deal_ticket = "0";
    }
    string execution_outcome = ClassifyOutcome(trade_return, retcode);
    string result_payload = StringFormat(
      "v1|%s|%s|%s|%s",
      request_id,
      execution_outcome,
      order_ticket,
      deal_ticket);

    outcome.execution_outcome = execution_outcome;
    outcome.order_ticket = order_ticket;
    outcome.deal_ticket = deal_ticket;
    outcome.retcode = retcode;
    outcome.trade_return = trade_return;
    outcome.requires_reconciliation = execution_outcome == "DONE" ||
                                      execution_outcome == "DONE_PARTIAL" ||
                                      execution_outcome == "PLACED";

    if(!AppendAndApply(
      port,
      reducer,
      intent_sequence + 1,
      TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
      result_payload))
    {
      SetRecoveryRequired(outcome);
      return false;
    }

    outcome.status = TGK_GRID_ENTRY_EXECUTION_STATUS_RECORDED;
    return true;
  }

  // Persist the one observed Anchor activation. Every canonical precondition
  // is validated before any Journal append, so an invalid or conflicting
  // activation never creates a durable record. The Journal append still
  // happens before the Reducer applies the record, so an append/flush failure
  // reports failure and leaves the canonical Anchor State at WAIT_ACTIVATION.
  bool RecordAnchorActivation(
    const string instance_id,
    const string symbol,
    long magic_number,
    ENUM_TGK_GRID_MODE mode,
    long config_epoch,
    CTGKGridLevelRuntimeCoordinator &coordinator,
    CTGKGridEntryMappingReducer &reducer,
    ITGKGridEntryExecutionPort &port
  )
  {
    if(!m_initialized ||
       m_recovery_required ||
       !IsToken(instance_id) ||
       !IsToken(symbol) ||
       magic_number <= 0 ||
       config_epoch <= 0 ||
       ModeToken(mode) == "" ||
       !coordinator.HasPendingAnchorActivation() ||
       !coordinator.MatchesGridContext(
         symbol,
         magic_number,
         mode,
         config_epoch) ||
       !reducer.MatchesContext(
         instance_id,
         symbol,
         magic_number,
         mode,
         config_epoch))
      return false;

    // The Reducer is the canonical authority. Only an unmapped Anchor that
    // still waits activation may move to READY, and the requested transition
    // is exactly WAIT_ACTIVATION -> READY. A Coordinator/Reducer disagreement
    // fails closed: no state is guessed, synchronized or repaired here.
    ENUM_TGK_GRID_LEVEL_STATE canonical_anchor_state =
      TGK_GRID_LEVEL_READY;
    bool has_anchor_mapping = true;
    if(!reducer.TryGetAnchorState(canonical_anchor_state) ||
       TGKGridNormalizeLevelState(canonical_anchor_state) !=
         TGK_GRID_LEVEL_WAIT_ACTIVATION ||
       !reducer.TryGetPositionMapping(true, -1, has_anchor_mapping) ||
       has_anchor_mapping)
      return false;

    long next_sequence = reducer.LastSequence() + 1;
    long port_sequence = 0;
    string payload = StringFormat(
      "v1|ANCHOR_STATE|%I64d|READY",
      config_epoch);

    if(next_sequence <= 0 ||
       !port.NextSequence(port_sequence) ||
       port_sequence != next_sequence ||
       !AppendAndApply(
         port,
         reducer,
         next_sequence,
         TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
         payload))
    {
      m_recovery_required = true;
      return false;
    }

    if(!coordinator.ConfirmAnchorActivation())
    {
      m_recovery_required = true;
      return false;
    }

    return true;
  }

  bool IsRecoveryRequired()
  {
    return m_recovery_required;
  }
};

#endif
