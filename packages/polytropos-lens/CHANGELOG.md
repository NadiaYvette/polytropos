# Changelog for polytropos-lens

## 0.1.0.4 — 2026-11-22

- Constrain `prismVariant` constructor payload type to `ConstructorPayload c s`.
- Require `polytropos-core >= 0.1.2.0 && < 0.2` and `polytropos-plugin >= 0.1.2.0 && < 0.2`.

## 0.1.0.0 — Initial Release

- Full `Control.Lens` optics integration for open records and variants
- `fieldLens` providing Van Laarhoven lenses for record fields
- `ctorPrism` providing first-class prisms for variant constructors
- `HasField` and `LabelOptic` integration enabling `#fieldName` overloaded label optics
