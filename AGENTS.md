# AGENTS.md — Always-On Rules

> Place at repo root. Read this before **every** task. The full scope lives in `PRODUCT_SPEC.md`.

## Before you write any code

1. Read the relevant section of `PRODUCT_SPEC.md`.
2. Confirm the task belongs to the **current phase**. If not, stop and ask.
3. Create the branch: `feature/<system>-<description>`.
4. Search `core/` and `shared/` for an existing solution.

## Non-negotiables

| Rule | Meaning |
|---|---|
| **Robust only** | Never a temporary fix. If the robust fix is out of scope, stop and report — do not ship the hack. |
| **Commands for everything** | Every document mutation is an `EditorCommand`. Serialisable, deterministic, undoable. |
| **Branch + PR per feature** | No direct commits to `main`. Ever. |
| **No cross-feature imports** | Features talk through `core/` services and commands only. |
| **Registries, not switches** | New tool/node/property type = a registration, never an edit to a `switch`. |
| **Domain is pure Dart** | Zero `package:flutter` imports below the presentation layer. |
| **Model first, UI last** | Write the command and its test before the widget. |

## Banned patterns

```dart
Future.delayed(...)          // to "let something settle"
try { ... } catch (_) {}     // silencing errors
// TODO: fix properly later  // merged to main
const _magicOffset = 3.5;    // pixel nudge to fix a layout bug
switch (node.type) { ... }   // inside generic panel code
```

## Flutter standards

- `dart format` + `flutter analyze` clean, zero warnings
- Const constructors by default; stateless by default
- `build` composes only — no logic, no async, no fetching
- Extract sub-widgets past ~50 lines of `build`
- No `!` without a documented invariant
- No magic numbers; named constants in theme/config
- Guard `BuildContext` across `await` with `mounted`
- Every new dependency justified in the PR

## OOP

- One class, one reason to change
- Composition over inheritance; max 2 levels deep
- Immutable domain models with `copyWith`
- Inject dependencies; program to interfaces
- No public mutable fields; expose unmodifiable collection views

## Reuse

- Third occurrence gets extracted; second gets watched
- Shared widgets are feature-agnostic — no `isTimeline` booleans
- Domain logic is never duplicated, not even once

## Tests required

- Every command: `execute → undo` returns a byte-identical document
- Every shared widget: widget test
- Every performance-budgeted surface: benchmark test
- Domain layer: 90%+ coverage

## Performance budgets (blocking)

Canvas ≤16ms @ 5k nodes · Hierarchy 60fps @ 10k nodes · Timeline scrub 60fps @ 10k keyframes · Undo ≤16ms · Cold start ≤2s

Anything that may exceed 16ms runs off the main isolate.

## PR checklist

```
- [ ] Spec section referenced
- [ ] Root cause stated (not symptom)
- [ ] No temporary workarounds
- [ ] All mutations via commands
- [ ] No cross-feature imports
- [ ] Existing abstractions reused
- [ ] Tests added, CI green
- [ ] PRODUCT_SPEC.md acceptance boxes ticked
```

## When blocked

Choose the robust path. If it is out of scope: **stop, describe the correct solution, ask.** Do not substitute a workaround and do not silently expand scope.