# WP-06C — Test Plan

สถานะ: Draft — no implementation authorization

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
| C-04 | Entry rejected/terminal no fill | Remain WAIT_INITIAL_ENTRY; no Anchor |
| C-05 | Entry accepted but no Deal/Position yet | Remain unresolved; no Anchor/ACTIVE |
| C-06 | Actual fill differs from request quote | Anchor equals actual fill price |
| C-07 | Anchor durable bootstrap append fails | No partial ACTIVE/mapping; recovery required |
| C-08 | Two Position Identifiers observed for initial Request | Fail closed under current contract |
| C-09 | Valid initial mapping committed | Coordinator geometry matches actual Anchor + Step + Bounds |
| C-10 | BUY/SELL activation and retrace | Existing Engine candidate rules preserved |
| C-11 | Multiple levels crossed in one price move | At most one candidate; BUY lowest / SELL highest according to current Engine |
| C-12 | Candidate target/config epoch mismatch | Resolver fails closed; no adapter call |
| C-13 | Policy reject | No Intent append and no execution call |
| C-14 | Intent/storage failure | No Trade request |
| C-15 | Accepted normal entry | Remains unresolved until WP-06B + WP-05C complete |
| C-16 | Repeated tick while unresolved | No duplicate request |
| C-17 | Price moves to better candidate during unresolved request | Existing deferred-candidate policy preserved |
| C-18 | Price moves outside Bounds after activation | No new request; existing management path remains enabled |
| C-19 | Foreign Symbol/Magic Position present | Not mapped or managed |
