# Open Loops Register

**Purpose:** Items that are deliberately unresolved. Each entry carries its
trigger — the concrete artifact whose arrival makes the item decidable — so
that decisions are not quietly settled in code.

**Convention:** A trigger is a file or artifact that must exist before the
item is re-opened for decision. "Not yet" means the item is suspended, not
answers.

**Review cadence:** re-read this register whenever a task packet closes or a
design note section is answered. Remove entries whose trigger is moot because
the path forward no longer exists.

---

## 1. Role-tail implications

**Question:** what does the row-tail judgement machinery (inclusion,
widening, constraint emission on unsolved tails) imply for the plugin's
literal-emission contract and the `RowEq`/`RowShow` spec?

**Why open:** the draft's §3–§4 define the tail contract, but the plugin
and the test spec are written against concrete, fully-known rows. Whether
the plugin has anything to emit when a row carries an unsolved tail, and
whether the test spec should cover that shape, is not yet decided.

**Trigger:** a concrete row shape (or test case) that carries an open tail
and a stated requirement for what the plugin must do when it encounters one.
Until then, the plugin's emission contract is read as bounded to the
fully-known-row cases already in `packages/polytropos-core/test/Main.hs`.

**Status:** suspended.

---

## 2. Third shared layer

**Question:** whether the algebra of shared row machinery (the layer that
several evidence classes or satellite packages draw on) needs a third
variant beyond the two currently anticipated.

**Why open:** this is a structural question that depends on what actually
shows up in code, not on a priori speculation. Settling it now would be
premature.

**Trigger:** two distinct satellite or evidence-class implementations whose
shared-layer needs diverge in a way that can't be absorbed by the existing
two-layer vocabulary. Until then, no third layer is proposed.

**Status:** suspended.
