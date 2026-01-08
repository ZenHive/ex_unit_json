# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ExUnitJSON is an Elixir library that provides AI-friendly JSON test output for ExUnit. It generates structured JSON output from `mix test` for use with AI editors like Claude Code.

## Commands

```bash
# Run all tests
mix test

# Run a single test file
mix test test/ex_unit_json_test.exs

# Run a specific test by line number
mix test test/ex_unit_json_test.exs:5

# Format code
mix format

# Generate documentation
mix docs
```

## Architecture

This is an early-stage library with a single module:
- `lib/ex_unit_json.ex` - Main module (currently placeholder)

The library is intended to be an ExUnit formatter that outputs JSON instead of the default text output, making test results machine-readable for AI tooling.

@include ~/.claude/includes/across-instances.md
@include ~/.claude/includes/critical-rules.md
@include ~/.claude/includes/task-prioritization.md
@include ~/.claude/includes/task-writing.md
@include ~/.claude/includes/web-command.md
@include ~/.claude/includes/code-style.md
@include ~/.claude/includes/development-philosophy.md
@include ~/.claude/includes/documentation-guidelines.md
@include ~/.claude/includes/api-integration.md
@include ~/.claude/includes/development-commands.md
@include ~/.claude/includes/elixir-patterns.md
@include ~/.claude/includes/library-design.md
