# Changelog for polytropos-optics

## 0.1.0.4 — 2026-11-22

- Constrain `ctorOptic` constructor payload type to `ConstructorPayload c s`.
- Require `polytropos-core >= 0.1.2.0 && < 0.2`.

## 0.1.0.0 — Initial Release

- Integration with the `optics-core` ecosystem for open records and variants
- `fieldLens` providing profunctor-based lenses for record fields
- `ctorOptic` providing first-class prisms for variant constructors
- `Optics.Label.LabelOptic` instances enabling `#fieldName` lens syntax with `OverloadedLabels`
