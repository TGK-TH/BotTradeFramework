# Project conventions

- Prefer reusable components over strategy-specific duplication.
- Keep business/strategy logic separate from infrastructure and platform-specific execution.
- Existing framework follows SRP and state-machine patterns where applicable.
- MQL5 source is maintained in the repository; MT5's linked `Experts` and `Include` directories are execution/compile surfaces, not source-of-truth locations.