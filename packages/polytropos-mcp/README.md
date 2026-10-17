# polytropos-mcp

Model Context Protocol (MCP) JSON-RPC 2.0 server implementation for [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants.

## Overview

`polytropos-mcp` implements the Anthropic Model Context Protocol specification for agentic tooling. It leverages open product rows for compile-time OpenAPI 3.0 tool schema generation and open variant sum rows for $O(1)$ jump table tool call dispatch.

## Features

- **`recordToTool`**: Derives compliant OpenAPI 3.0 input schemas directly from open product row types (`Proxy (r :: Row)`).
- **`toolCallToVariant` & `dispatchToolCall`**: Parses JSON tool call arguments into open variants and executes handlers via `eliminateUniform`.
- **`runStdioServer`**: Complete stdio server loop handling lifecycle handshakes (`initialize`, `tools/list`, `tools/call`).

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
