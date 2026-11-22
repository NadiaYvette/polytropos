# Changelog for polytropos-profunctors

## 0.1.0.4 — 2026-11-22

- Constrain `ctorPrism` constructor payload type to `ConstructorPayload c s`.
- Require `polytropos-core >= 0.1.2.0 && < 0.2`.

## 0.1.0.1 — Initial Release (2026-10-20)

- Integration with the `profunctors` ecosystem for open records and variants
- Pure profunctor lenses and prisms (`Lens`, `Prism`, `view`, `preview`, `review`, `over`, `set`)
- High-level `fieldLens` and `ctorPrism` with compile-time index resolution
- Low-level `slotLens`, `typedSlotLens`, `variantPrism`, and `typedVariantPrism` over unboxed `SmallArray` memory
