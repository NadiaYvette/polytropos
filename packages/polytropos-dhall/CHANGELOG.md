# Changelog for polytropos-dhall

## 0.1.0.1 — Initial Release

- High-performance Dhall `ToDhall` and `FromDhall` codecs for open records and variants
- Direct linear unrolling of flat contiguous `SmallArray` memory into Dhall AST expressions
- Tagged variant serialization into native Dhall union expressions
- Higher-kinded record support (`RecordF f r`) with automatic fallback for optional fields
- Turnkey generic adapters (`GenericDhall`, `GenericFromDhall`, `GenericToDhall`) for `DerivingVia`
- Homogeneous reflection and introspection helpers
