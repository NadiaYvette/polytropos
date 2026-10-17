# polytropos-openapi3

Automatic OpenAPI 3.0 specification and JSON Schema generation for [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants via `openapi3`.

## Overview

`polytropos-openapi3` synthesizes `ToSchema` instances for open records and variants:
- Open records generate object schemas with typed properties and required field lists.
- Open variants generate `oneOf` tagged-union schemas with discriminator objects.

## Features

- **No Generics Blowup**: Direct type-level row inspection without generic binary tree expansion.
- **Full OpenAPI 3.0 Compliance**: Emits schemas directly consumed by Swagger UI, Redoc, and OpenAPI code generators.
- **Customizable Schemas**: Combine with custom descriptions, examples, and formats.

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
