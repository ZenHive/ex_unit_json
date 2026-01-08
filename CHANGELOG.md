# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## Phase 1: MVP Core Features

### Task 1: Project Structure Setup

**Completed:** 2026-01-08

**What was done:**
- Created `lib/ex_unit_json/formatter.ex` - GenServer stub with struct and typespecs
- Created `lib/ex_unit_json/json_encoder.ex` - Encoder module with function stubs and specs
- Created `lib/mix/tasks/test_json.ex` - Mix task stub with option parsing
- Updated `lib/ex_unit_json.ex` with comprehensive moduledoc
- Added 4 module existence tests

**Files created:**
- `lib/ex_unit_json/formatter.ex`
- `lib/ex_unit_json/json_encoder.ex`
- `lib/mix/tasks/test_json.ex`

**Verification:**
- `mix compile --warnings-as-errors` passes
- `mix test` passes (4 tests)
