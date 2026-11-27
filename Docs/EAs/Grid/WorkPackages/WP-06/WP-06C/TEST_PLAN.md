# WP-06C — Test Plan

สถานะ: CTO Design — approved bootstrap contract; no implementation authorization

## Preconditions
- WP-06A/B complete and reviewed.
- D-06-03 initial Anchor bootstrap persistence contract approved.
- Fresh no-trade Grid Regression baseline recorded.
- All unit tests use Fake Execution/Event/Position ports; no Trade Requests.

## Test Cases
| ID | Scenario | Expected |
|---|---|---|
| C-01 | Initial price below/above Bounds | No entry request |
| C-02 | Initial BUY within Bounds | Exactly one BUY intent/request |
| C-03 | Initial SELL within Bounds | Exactly one SELL intent/request |
| C-04 | Entry rejected/terminal no fill, with authoritative exact-order evidence proving no Entry Deal exists | Return to WAIT_INITIAL_ENTRY; no Anchor |
| C-05 | Entry accepted but no Deal/Position yet | Remain unresolved; no Anchor/ACTIVE |
| C-06 | Actual fill differs from request quote | Anchor equals actual fill price |
| C-07 | Initial Entry Intent append/flush fails | No Trade Request is sent |
| C-08 | Initial Bootstrap journal append/flush fails | No partial config/Anchor/mapping/ACTIVE; Recovery Error |
| C-09 | Two Position Identifiers observed for initial Request | Fail closed under current contract |
| C-10 | Valid initial mapping committed | Coordinator geometry matches actual Anchor + Step + Bounds |
| C-11 | BUY/SELL activation and retrace | Existing Engine candidate rules preserved |
| C-12 | Multiple levels crossed in one price move | At most one candidate; BUY lowest / SELL highest according to current Engine |
| C-13 | Candidate target/config epoch mismatch | Resolver fails closed; no adapter call |
| C-14 | Policy reject | No Intent append and no execution call |
| C-15 | Intent/storage failure | No Trade request |
| C-16 | Accepted normal entry | Remains unresolved until WP-06B + WP-05C complete |
| C-17 | Repeated tick while unresolved | No duplicate request |
| C-18 | Price moves to better candidate during unresolved request | Existing deferred-candidate policy preserved |
| C-19 | Price moves outside Bounds after activation | No new request; existing management path remains enabled |
| C-20 | Foreign Symbol/Magic Position present | Not mapped or managed |
| C-21 | Initial Intent / Execution Result restored before Bootstrap commit | Recover exact Order/Deals; no duplicate request |
| C-22 | Initial Bootstrap record contains invalid sub-transition | Entire compound commit rejected; no partial in-memory state |
| C-23 | Journal append/flush fails | No partial config/Anchor/mapping/ACTIVE; Recovery Error |
| C-24 | Journal append succeeds but in-memory publish fails | Keep gates closed; replay durable compound record exactly once on recovery |
| C-25 | Valid Initial Bootstrap committed | Config, Anchor Mapping, ACTIVE and geometry agree in canonical projection |
| C-26 | Multiple partial Deals for one Position Identifier | Anchor uses volume-weighted actual fill; matches Position average within Symbol precision |
| C-27 | Multiple Position Identifiers for initial Request | Fail closed under current contract |
| C-28 | Restart after Bootstrap commit | Restore exact Anchor/config/mapping; no second bootstrap |
| C-29 | Normal tick/candidate evaluation occurs before Initial Bootstrap commit | Block all normal candidate evaluation and entry requests |
| C-30 | Event evidence is pending at tick start | Drain/persist Deal evidence and complete WP-05C reconciliation before Coordinator price evaluation |
