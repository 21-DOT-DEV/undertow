# Undertow — Flow-Aware Development Context

## Available MCP Tools

Undertow provides the following tools via its MCP server:

### `get_flow_context`
Returns the developer's current flow context: git branch, uncommitted changes, diff stats, recent commits, recently modified files, and any available Xcode observer data.

**When to call:** At the start of every conversation to understand what the developer is actively working on. This replaces reading git status manually and gives you a complete picture of the current development session.

### `semantic_search`
Search the codebase using natural language or symbol names. Returns ranked code chunks with relevance scores and explanations.

**When to call:** When you need to find relevant code by description (e.g., "error handling in network layer") or by symbol name (e.g., "FlowContextAggregator").

### `find_symbol_references`
Find all references to a Swift symbol (function, type, property) using the compiler index.

**When to call:** When you need to understand how a symbol is used across the codebase before modifying it.

### `find_conformances`
Find all types conforming to a Swift protocol using the compiler index.

**When to call:** When you need to discover all implementations of a protocol.

## Workflow

1. **Start every session** by calling `get_flow_context` to understand what the developer is working on
2. Use `semantic_search` to explore the codebase before making changes
3. Use `find_symbol_references` and `find_conformances` for precise structural queries
