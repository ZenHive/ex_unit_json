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

---

### Task 2: JSON Encoder - Basic Test Serialization

**Completed:** 2026-01-09

**What was done:**
- Implemented `encode_test/1` - converts `%ExUnit.Test{}` to JSON-serializable map
- Implemented `encode_state/1` - converts test state tuples to strings (nil→passed, failed, skipped, excluded, invalid)
- Implemented `encode_tags/1` - filters internal ExUnit keys and converts values to JSON-safe types
- Added `encode_tag_value/1` - handles atoms, strings, numbers, booleans, lists, maps, and non-serializable values
- Added `encoded_test` type with full field documentation
- Handles `:ex_unit_no_meaningful_value` marker
- Filters keys starting with `ex_` prefix
- 28 comprehensive unit tests covering all edge cases

**Key implementation details:**
- Struct type enforced in function signature: `def encode_test(%ExUnit.Test{} = test)`
- Pattern matching in function heads for state encoding
- Boolean guards checked before atom guards (booleans are atoms in Elixir)
- Non-serializable values (PIDs, refs) safely converted via `inspect/1`
- Nested structures (maps, lists) recursively encoded

**Files modified:**
- `lib/ex_unit_json/json_encoder.ex` - Full implementation
- `test/ex_unit_json/json_encoder_test.exs` - 28 tests

**Also in this commit:**
- Removed unused `jason` dependency (using built-in `:json`)
- Updated GitHub URL to `ZenHive/ex_unit_json`

**Verification:**
- `mix test` passes (32 tests)
- `mix dialyzer` passes (0 warnings)
- `mix doctor` passes (100% coverage)
