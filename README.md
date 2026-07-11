# BotTradeFramework

A reusable MQL5 trading framework designed for building, testing, and maintaining multiple trading strategies with a shared architecture.

---

## Project Goal

This project is not intended to build only one Expert Advisor.

The goal is to create a reusable framework that allows multiple trading strategies to share the same infrastructure, including:

- Market utilities
- Risk management
- Position management
- State machine
- Trailing stop
- Entry and exit modules

Each new trading strategy should reuse the framework instead of rewriting common components.

---

## Current Status

Current Development Phase

- ✅ Phase 0 : Initial EA
- ✅ Phase 0.5 : Development Environment
- ✅ Phase 1 : Utility Extraction
- ✅ Phase 2 : Trailing Stop Module
- 🚧 Phase 3 : State Machine Refactoring

---

## Project Structure

```
BotTradeFramework/

├── Experts/
│   └── TGK/
|       └── EMA_Cross_Retest.mq5
│
├── Include/
│   └── BotTrade/
│       ├── Indicators/
│       ├── Market/
│       ├── Position/
│       ├── Risk/
│       ├── Strategy/
│       ├── Trade/
│       ├── Types/
│       └── Utils/
│
├── docs/
│
├── README.md
│
└── .gitignore
```

---

## Development Environment

Operating System

- macOS
- Wine (MetaTrader 5)

Editor

- Visual Studio Code

Extensions

- MQL Clangd

Version Control

- Git
- GitHub

---

## MetaTrader 5 Location

Current MT5 Data Folder

```
/Users/tachagon/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5
```

The project source code is **not** edited inside the MT5 folder.

---

## Symbolic Link

The MT5 `Experts` and `Include` folders are symbolic links pointing to this repository.

Repository

```
Documents/
└── 13_Trade/
    └── 1_Bot/
        └── BotTradeFramework/
```

Workflow

```
VS Code
      │
      ▼
Save Source Code
      │
      ▼
MetaTrader Compile
      │
      ▼
Backtest
      │
      ▼
Git Commit
```

No manual file copying is required.

---

## Coding Principles

The framework follows several software engineering principles.

- Single Responsibility Principle (SRP)
- Reusable modules
- State Machine architecture
- Strategy-independent utilities
- Keep business logic separated from infrastructure

---

## Roadmap

### Phase 3

- [ ] Bot Context
- [ ] WaitA Module
- [ ] WaitB Module
- [ ] Entry Module
- [ ] Position Module

### Future

- [ ] Multi-strategy support
- [ ] Multi-symbol support
- [ ] Multi-timeframe support
- [ ] Backtest helper tools
- [ ] Performance analytics

---

## License

Private Project
