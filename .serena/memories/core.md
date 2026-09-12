# BotTradeFramework core

- Reusable MQL5 trading framework; not a single-EA repository.
- Primary source tree: `Experts/` for EAs; `Include/BotTrade/` for reusable indicators, market, position, risk, strategy, trade, types, and utility modules.
- Design invariants: reusable modules, SRP, state-machine architecture, strategy-independent infrastructure, business logic separated from infrastructure.
- MT5 consumes repository `Experts`/`Include` via symlinks; source is edited in the repo, not inside MT5 data directory.
- Current project direction includes learning Python trading-system architecture while preserving reusable, platform-independent strategy logic; Python-specific conventions are not yet established.
- Focused MQL5 CDC Account 3 benchmark details and Python conversion/backtest plans belong in task-specific memories when stabilized.-oriented Python conversion of `Experts/TGK/CDC_Account_3_Benchmark.mq5`, with strategy logic intended to remain platform-independent and later support MT5 and other execution adapters. Python work is separate from the existing MQL5 implementation and should not alter the EA unless explicitly requested.
- Focused memories: `mem:tech_stack` covers the current toolchain and runtime; `mem:conventions` covers architectural/code conventions; `mem:suggested_commands` covers project-specific commands; `mem:task_completion` covers completion checks.