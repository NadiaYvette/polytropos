# Revision history for polytropos-docrecords

## 0.1.0.2 -- 2026-10-21

* Added comprehensive worked examples and when-to-use guidance to front-door Haddock documentation.
* Coordinated version bump across all Polytropos packages.

## 0.1.0.1 -- 2026-10-20

* Coordinated release with `polytropos-core-0.1.0.1`.

## 0.1.0.0 -- 2026-10-19

* Initial release.
* Self-documenting extensible records (`DocRec`) based on Polytropos's flat representation.
* Tri-state missing value semantics (`PossiblyEmpty`).
* Multi-tier provenance tracking (`SourceTag`: `DefaultSource`, `YamlSource`, `CliSource`).
* Automated Markdown documentation generation (`showDocumentation`).
* JSON/YAML merging and partial overriding (`fromJSONAs`).
* Automated CLI option parser synthesis via `optparse-applicative` (`parseRecFromCLI`).
