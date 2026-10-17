# Changelog for polytropos-mcp

## 0.1.0.0 — Initial Release

- Model Context Protocol (MCP) JSON-RPC 2.0 server implementation for open records and variants
- `recordToTool`: Compile-time OpenAPI 3.0 schema synthesis from open product row types
- `toolCallToVariant` & `dispatchToolCall`: JSON argument parsing and $O(1)$ jump table variant dispatch via `eliminateUniform`
- `runStdioServer`: Standard I/O transport loop
