# Product Specification — Rive-Based Visual Editor (Flutter)

> **Status:** Living document. This is the single source of truth for scope, architecture, and engineering rules.
> **Rule:** No feature is started until it exists in this spec. No feature is marked done until this spec is updated.

---

## 0. Product Thesis

This is **not** an animation editor. It is a **game-engine-style editor** that happens to author animation.

The correct mental model is Unity or Godot — not Figma. The Rive Engine ships a runtime, a scene graph, an animation system, a state machine, a data-binding layer, and a renderer. The editor is a front end over that runtime, and its architecture must reflect that.

**Consequence for every design decision:** the editor manipulates a *live document model* that the runtime can render at any moment. There is no "export step" that reconciles two different representations. What you see is the runtime, driven by the editing session.

### Non-goals (v1)

- Not a general vector illustration tool competing with Illustrator.
- Not a video editor.
- Not a code IDE. Scripting is a Phase 5 surface, not a core loop.

---

## 1. Target Platforms

| Platform | Priority | Notes |
|---|---|---|
| macOS (desktop) | P0 | Primary development target |
| Windows (desktop) | P0 | Must ship with macOS |
| Linux (desktop) | P1 | Best-effort, same codebase |

Flutter is the UI layer for all of them. Platform-specific code lives behind interfaces (see §4.6).

---

## 2. System Breakdown

Twenty systems. Each is a **feature module** (see §4.2). Each has an owner section here, an acceptance checklist, and a phase assignment.

---

### 2.1 Project / File Management — *Phase 1*

Everything around opening, persisting, and managing `.riv` files and the editor's own project format.

**Features**
- New / Open / Save / Save As
- Autosave with crash recovery journal
- Import assets (images, fonts, audio, SVG)
- Export (`.riv`, plus per-platform artifacts)
- Version history (local snapshots in v1; cloud in Phase 5)
- Undo / Redo (see §4.4 — this is a core system, not a file feature)
- Multiple artboards per document
- Components / Libraries (shared, reusable definitions)

**Acceptance**
- [ ] A document can round-trip: open → edit → save → reopen → byte-stable for untouched subtrees
- [ ] Killing the process mid-edit loses ≤ 5 seconds of work
- [ ] Import of a 200 MB asset does not block the UI thread
- [ ] All file operations are cancellable and report structured errors (§4.7)

---

### 2.2 Scene Hierarchy — *Phase 1*

Equivalent to Unity's Hierarchy panel.

```
Artboard
 ├── Background
 ├── Character
 │    ├── Head
 │    ├── Body
 │    ├── Left Arm
 │    └── Right Arm
 └── UI
```

**Features**
- Tree view with virtualised rendering (must handle 10k+ nodes)
- Expand / collapse, with persisted expansion state
- Rename (inline edit, validated, undoable)
- Drag / drop reorder and reparent
- Parent / child relationships with transform inheritance
- Lock, Hide, Duplicate, Delete
- Search / filter by name and by type
- Multi-select with shift-range and cmd/ctrl-toggle

**Acceptance**
- [ ] Every mutation goes through the command system — no direct model writes from the widget layer
- [ ] Reparenting preserves world transform by default; local transform on modifier key
- [ ] Tree scrolls at 60 fps with 10,000 nodes
- [ ] Selection state is shared with Canvas and Inspector via a single selection service

---

### 2.3 Canvas (Viewport) — *Phase 1*

The centre of the editor and the highest-risk performance surface.

**Features**
- Pan, Zoom, Rotate view
- Grid, Snap, Guides, Rulers
- Selection box (marquee), multi-select
- Infinite canvas
- Multiple artboards laid out in the same canvas space
- Overlay layer for gizmos, handles, bones, mesh vertices

**Architecture requirement**
The canvas is composed of three stacked layers, each independently invalidated:
1. **Content layer** — Rive runtime render output.
2. **Overlay layer** — selection outlines, transform gizmos, bone handles, mesh vertices. Drawn in screen space, transformed by the view matrix.
3. **Interaction layer** — hit testing, pointer routing, active tool delegate.

**Acceptance**
- [ ] Sustains 60 fps while dragging a selection of 500 nodes
- [ ] Overlay never repaints when only content changes, and vice versa
- [ ] Hit testing is O(log n) via spatial index, not a linear scan of the scene graph
- [ ] View transform is a single source of truth consumed by all three layers

---

### 2.4 Toolbar — *Phase 1 (basic) / Phase 4 (rigging tools)*

Tools are **plugin-shaped from day one**, even before the plugin API exists (§2.20).

| Tool | Phase |
|---|---|
| Selection | 1 |
| Hand (pan) | 1 |
| Zoom | 1 |
| Rectangle | 1 |
| Ellipse | 1 |
| Polygon | 1 |
| Text | 1 |
| Pen | 2 |
| Pencil | 2 |
| Bone tool | 4 |
| Mesh tool | 4 |

**Contract:** every tool implements a single `EditorTool` interface — `onPointerDown/Move/Up`, `onKey`, `paintOverlay`, `cursor`, `activate/deactivate`. Adding a tool must require **zero** changes to the canvas or toolbar widgets. This is enforced by a registry (§4.5).

---

### 2.5 Inspector Panel — *Phase 1*

Property-grid driven. Every selected object exposes its editable properties.

**Property groups**
- Transform: Position, Rotation, Scale
- Appearance: Opacity, Fill, Stroke, Shadow, Blend Mode, Visibility
- Constraints
- Animation settings

**Architecture requirement**
The inspector is **generated from property metadata**, not hand-written per node type. Each model property declares its type, range, editor widget, animatability, and undo semantics. Adding a property to a node type must automatically surface it in the inspector.

**Acceptance**
- [ ] Multi-select shows shared properties with mixed-value indicators
- [ ] Dragging a numeric field produces a single coalesced undo entry, not one per frame
- [ ] Every animatable property shows a keyframe affordance wired to the timeline
- [ ] No `switch` on node type anywhere in the inspector widget tree

---

### 2.6 Asset Browser — *Phase 1*

**Contains:** Images, Fonts, Audio, SVG, Components, Materials

**Features**
- Drag onto canvas
- Replace asset (all references update)
- Delete asset (with reference-count warning)
- Search, filter by type, grid/list view

**Acceptance**
- [ ] Assets are content-addressed; the same file imported twice stores one copy
- [ ] Deleting a referenced asset is blocked or explicitly confirmed with an impact list
- [ ] Thumbnails generate off the main isolate

---

### 2.7 Animation Timeline — *Phase 2*

The largest single system. Budget accordingly.

**Contains:** Timeline, playback controls, FPS, current frame, keyframes, curves, layers, tracks

**Operations:** Insert / Delete / Copy / Paste / Move / Scale keyframes; Loop, Ping Pong, One Shot

**Architecture requirement**
Time is a first-class domain concept. A `Timeline` owns tracks; a track owns keyframes for exactly one property path. Scrubbing is a pure function: `(document, time) → evaluated pose`. Never mutate the document to preview a frame.

**Acceptance**
- [ ] Scrubbing 10,000 keyframes stays at 60 fps
- [ ] Keyframe operations are undoable as atomic batches
- [ ] Playback is driven by a clock service, not `setState` in a ticker widget
- [ ] The evaluated pose is never written back to the persisted document

---

### 2.8 Curve Editor — *Phase 2*

Shows Position X, Position Y, Rotation, Scale, Opacity — any animatable numeric channel.

- Bezier handle editing with tangent modes (auto, broken, mirrored, linear, stepped)
- Multi-channel overlay with per-channel colour
- Box-select and transform of control points

**Acceptance**
- [ ] Curve evaluation matches runtime evaluation exactly — shared code path, verified by golden tests
- [ ] Handle drag respects time-monotonicity (a keyframe cannot cross its neighbour)

---

### 2.9 Rigging — *Phase 4*

Effectively a sub-application. Do not attempt before Phases 1–3 are stable.

**Features:** Bones, IK, FK, Constraints, Skinning, Weight painting, Mesh deformation

**Acceptance**
- [ ] Bone chains solve deterministically; same input → same output, always
- [ ] IK solver runs off the widget build cycle
- [ ] Weight painting strokes are undoable as one entry per stroke, not per sample

---

### 2.10 Mesh Editor — *Phase 4*

**Features:** Edit / add / remove vertices, bind mesh, weight paint, triangulation

**Acceptance**
- [ ] Triangulation is incremental — editing one vertex does not retriangulate the whole mesh
- [ ] Vertex editing shares the overlay/hit-test infrastructure from §2.3, not a parallel implementation

---

### 2.11 State Machine Editor — *Phase 3*

Rive's biggest differentiator. A visual node graph, closer to Unreal Blueprint than to a timeline.

```
Idle → Hover → Pressed → Released
```

**Features:** States, Transitions, Conditions, Triggers, Booleans, Numbers, Blend states, Layers, Listeners, Events

**Architecture requirement**
The graph is a general-purpose node-graph module: nodes, ports, edges, layout, routing, selection, pan/zoom. State-machine semantics are a *consumer* of that module. This pays for itself the moment a second graph surface is needed (data binding, scripting).

**Acceptance**
- [ ] Graph renders 500 nodes / 1500 edges at 60 fps
- [ ] Edge routing avoids node overlap
- [ ] Invalid transitions are rejected at the model layer, not just visually discouraged
- [ ] Graph pan/zoom reuses the same view-transform abstraction as the canvas

---

### 2.12 Data Binding — *Phase 3*

Modern Rive favours data binding over the legacy Inputs system. Objects bind to runtime data:

`Health`, `Username`, `Progress`, `Score`, `Avatar`, `Image`

This lets application state drive the UI directly.

**Features**
- View-model definition (typed properties)
- Binding a node property to a view-model path
- Converters / formatters
- Live preview against mock data

**Acceptance**
- [ ] Bindings are typed; a string cannot be bound to a numeric property
- [ ] Broken bindings surface as document-level diagnostics, not silent failures
- [ ] Mock data sets are saved with the document for reproducible preview

---

### 2.13 Preview Mode — *Phase 3*

Runs the animation exactly as it behaves in the host application.

**Controls:** Play, Pause, Restart, Speed, Trigger state machine, Simulate click, Simulate hover

**Acceptance**
- [ ] Preview uses the shipping runtime, not an editor-only approximation
- [ ] Entering/exiting preview never mutates the document
- [ ] Input simulation goes through the same listener path as production input

---

### 2.14 Layout System — *Phase 4*

Modern Rive supports responsive layout.

**Features:** Rows, Columns, Padding, Margin, Alignment, Stretch, Responsive resizing

**Acceptance**
- [ ] Layout solve is separable and unit-testable without any widget tree
- [ ] Resizing an artboard reflows children within one frame

---

### 2.15 Component System — *Phase 4*

Like Unity prefabs or Flutter widgets. Examples: Button, Icon, Card, Slider, Navigation Bar.

**Features**
- Define a component from a selection
- Instance a component across artboards
- Property overrides per instance
- Propagate edits from definition to instances
- Detach instance

**Acceptance**
- [ ] Editing a definition updates all instances without breaking per-instance overrides
- [ ] Nested components are supported and cycle-detected
- [ ] Instances cost O(1) storage relative to definition size

---

### 2.16 Event System — *Phase 3*

Animation events developers subscribe to from code. Examples: `Footstep`, `PlaySound`, `SpawnParticle`, `ReachedEnd`, `Collision`, `Finished`.

**Acceptance**
- [ ] Events are declared with a typed payload schema
- [ ] Events fire in preview and are logged in an inspectable event console
- [ ] Event names are validated against the runtime binding generator (§2.17)

---

### 2.17 Runtime Integration — *Phase 3*

Preview the runtime APIs and show generated bindings for: Flutter, React, Android, iOS, Unity, Unreal, Web.

**Acceptance**
- [ ] Generated snippets are copy-pasteable and compile against the current runtime version
- [ ] Binding generation is template-driven; adding a target platform is a template, not a code change

---

### 2.18 Collaboration — *Phase 5*

Cloud features: Comments, Shared files, Team workspaces, Live editing.

**Architecture requirement**
Live editing is only viable if the command system (§4.4) is designed for it from Phase 1: commands must be serialisable, deterministic, and rebasable. **Design for this in Phase 1 even though it ships in Phase 5.** Retrofitting it later is a rewrite.

---

### 2.19 Command Palette — *Phase 5*

`Ctrl/Cmd + Shift + P`. Searches Commands, Assets, Animations, States.

**Acceptance**
- [ ] Every command in the registry is automatically discoverable — no separate palette list to maintain
- [ ] Fuzzy search over 2,000 entries returns in under 16 ms

---

### 2.20 Plugin / Scripting System — *Phase 5*

**Features:** Editor scripting, custom tools, macros, batch operations, AI-assisted editing

**Architecture requirement**
The plugin API is the *same* API the editor's own features use. If an internal feature reaches around the public surface, that is a bug in the API design, not a licence to special-case it.

---

## 3. Build Phases

Build in phases. Do not attempt the whole surface at once.

### Phase 1 — Core Editor
File management · Canvas · Hierarchy · Inspector · Selection · Transform tools

**Exit criteria:** A user can open a document, build a static scene, save it, reopen it, and undo/redo every action taken.

### Phase 2 — Animation
Timeline · Keyframes · Curve editor · Playback

**Exit criteria:** A user can animate any animatable property and play it back at correct speed with correct easing.

### Phase 3 — Interactivity
State machine graph · Transitions · Data binding · Events · Preview

**Exit criteria:** A user can build an interactive component that responds to input and external data, and preview it as it will run in production.

### Phase 4 — Advanced
Bones · Mesh editing · IK · Constraints · Components · Layout system

**Exit criteria:** A character rig can be built, skinned, animated, and reused as a component.

### Phase 5 — Productivity
Collaboration · Plugin API · AI assistant · Command palette · Version history

**Exit criteria:** Two users can edit the same document concurrently, and a third party can extend the editor without forking it.

**Rule:** A phase is not started until the previous phase's exit criteria are met and its acceptance checkboxes are ticked in this document.

---

## 4. Architecture

### 4.1 Principles

1. **Modular by panel.** Hierarchy, Canvas, Inspector, Timeline, State Machine Graph, Asset Browser, and Preview are independent feature modules.
2. **Communicate through a shared document model and a command system.** Panels never call each other directly.
3. **Robust over temporary.** See §5.3. This is the rule that gets broken most often and costs the most.
4. **Everything the user can do, code can do.** Every user action is a command object. This gives undo, macros, scripting, testing, and live collaboration for the price of one abstraction.

### 4.2 Layering

```
┌──────────────────────────────────────────────┐
│ Presentation   Widgets, panels, tools        │  ← Flutter only lives here
├──────────────────────────────────────────────┤
│ Application    Commands, services, use cases │  ← Zero Flutter imports
├──────────────────────────────────────────────┤
│ Domain         Document model, scene graph   │  ← Pure Dart, zero deps
├──────────────────────────────────────────────┤
│ Infrastructure Rive runtime, file I/O, net   │  ← Behind interfaces
└──────────────────────────────────────────────┘
```

**Hard rule:** dependencies point downward only. The domain layer imports nothing from `package:flutter`. This is enforced in CI by an import-boundary lint (§5.6).

### 4.3 Module Layout

```
lib/
  core/
    commands/          # Command base, history, transaction
    model/             # Document, Node, Property, Artboard
    services/          # Selection, Clipboard, Clock, ViewTransform
    result/            # Result<T,E>, failure types
  features/
    hierarchy/
      domain/
      application/
      presentation/
    canvas/
    inspector/
    timeline/
    state_machine/
    asset_browser/
    preview/
  infrastructure/
    rive/              # Runtime adapter behind an interface
    persistence/
    platform/
  shared/
    widgets/           # Reusable, feature-agnostic widgets only
    theme/
```

Each feature module has the same internal shape. No exceptions, no "this one is small enough."

**Cross-module rule:** a feature module may depend on `core/` and `shared/`. It may **not** import another feature module. If two features need to talk, they talk through a core service or a command.

### 4.4 Command System (Undo/Redo)

This is the spine of the application. Get it right in week one.

```dart
abstract class EditorCommand {
  String get label;              // Shown in undo menu and history
  bool get isMergeable;          // For coalescing drag operations
  CommandResult execute(DocumentContext context);
  CommandResult undo(DocumentContext context);
  Map<String, dynamic> toJson(); // Required for collaboration & macros
}
```

**Requirements**
- Every document mutation goes through a command. No exceptions.
- Commands are **serialisable** from day one (Phase 5 collaboration depends on it).
- Commands are **deterministic** — no wall-clock reads, no RNG without an injected seed.
- Related commands compose into a `CompositeCommand` so a multi-step edit is one undo step.
- Mergeable commands coalesce within a time window so a drag is one history entry.
- The history is bounded and memory-profiled; a long session must not grow unboundedly.

**Anti-pattern (rejected in review):** mutating the model in a widget callback and "adding undo later."

### 4.5 Registries Over Switches

Tools, node types, property editors, commands, and export targets are all registered, not hard-coded.

```dart
ToolRegistry.register(PenTool.descriptor);
PropertyEditorRegistry.register<Color>(ColorFieldBuilder());
NodeTypeRegistry.register(BoneNode.descriptor);
```

If adding a new tool, node type, or property type requires editing a `switch` statement or an `if-else` chain in a panel, the design is wrong. Fix the design.

### 4.6 Platform & Runtime Isolation

The Rive runtime, file system, clipboard, and native menus are accessed through interfaces defined in `core/` and implemented in `infrastructure/`. Reasons: testability, web/desktop divergence, and the ability to upgrade the runtime without touching feature code.

```dart
abstract class RiveRuntimeAdapter {
  Future<Result<RiveDocument, LoadFailure>> load(Uint8List bytes);
  void render(Canvas canvas, RenderContext context);
  void advance(Duration delta);
}
```

### 4.7 Error Handling

- Public APIs return `Result<T, Failure>`. Exceptions are for programmer errors only.
- Failures are typed sealed classes, never bare strings.
- Every failure that reaches the user has: what happened, why, and what to do next.
- No silent catches. No `catch (_) {}`. Ever.

### 4.8 State Management

- One state solution across the whole codebase (Riverpod recommended; whichever is chosen is chosen once and documented here).
- Widgets hold **no** business logic. If a widget file contains a domain rule, it belongs in the application layer.
- No global mutable singletons. Dependencies are injected.

### 4.9 Performance Budgets

These are requirements, not aspirations. Violating a budget blocks merge.

| Surface | Budget |
|---|---|
| Canvas frame time | ≤ 16 ms with 5,000 visible nodes |
| Hierarchy scroll | 60 fps at 10,000 nodes |
| Timeline scrub | 60 fps at 10,000 keyframes |
| Document open (10 MB) | ≤ 1,000 ms to first paint |
| Undo / Redo | ≤ 16 ms |
| Command palette search | ≤ 16 ms over 2,000 entries |
| Cold start to usable editor | ≤ 2,000 ms |

Any operation that may exceed 16 ms runs off the main isolate.

---

## 5. Engineering Rules

These are binding. Code that violates them does not merge, regardless of whether it works.

### 5.1 Flutter & Dart Standards

- **Style:** `flutter_analyze` clean. `dart format` applied. `very_good_analysis` or equivalent strict lint set enabled.
- **Null safety:** sound. No `!` on nullable values without a documented invariant directly above it.
- **Const:** const constructors wherever possible. Widgets are `const` by default.
- **Widget size:** if a `build` method exceeds ~50 lines, extract sub-widgets.
- **No logic in build:** `build` composes; it does not compute, fetch, or decide.
- **Stateless by default:** reach for `StatefulWidget` only when local ephemeral state is genuinely local.
- **Keys:** used deliberately in reorderable and virtualised lists, not sprinkled.
- **Async:** no `async` in `build`. Guard `BuildContext` across await boundaries with `mounted` checks.
- **Naming:** files `snake_case.dart`, types `PascalCase`, members `camelCase`, private `_prefixed`. Names say what a thing *is*, not how it is implemented.
- **Comments:** explain *why*, never *what*. Public APIs get dartdoc.
- **Magic numbers:** banned. Named constants in a theme or config class.
- **Dependencies:** every new package needs a justification in the PR description. Prefer the standard library and first-party packages.

### 5.2 OOP & Design

- **Single Responsibility:** one class, one reason to change. A class that both parses a file and updates the UI is two classes.
- **Program to interfaces.** Concrete types are injected, not constructed inline.
- **Composition over inheritance.** Inheritance is for genuine "is-a" polymorphism, not for code reuse. Deep hierarchies (>2 levels) require justification.
- **Open/Closed:** new node types, tools, and property editors are added by registration, never by editing existing switch statements (§4.5).
- **Immutability:** domain models are immutable with `copyWith`. Mutation happens through commands.
- **Encapsulation:** no public mutable fields. Collections are exposed as unmodifiable views.
- **Dependency Inversion:** high-level modules do not depend on low-level ones. Both depend on abstractions.
- **Law of Demeter:** `a.b.c.d()` is a design smell. Fix the design.

### 5.3 Robust Over Temporary — *the most important rule*

**Never resolve to a temporary solution.**

When a problem appears, fix the cause. Do not paper over the symptom.

**Banned outright:**
- `Future.delayed` to "let something settle" — fix the lifecycle instead
- `try { ... } catch (_) {}` to make an error go away
- Magic offsets and hardcoded pixel adjustments to correct a layout bug
- Copy-pasting a class and changing three lines
- `// TODO: fix properly later` merged into `main`
- Special-casing one node type inside generic code
- Disabling a lint or a test to make CI pass
- `setState` in a place that forces a full-tree rebuild to work around a stale value

**Required instead:**
- Identify the root cause and state it in the PR description
- If the robust fix is genuinely out of scope, **do not implement the hack.** Stop, open an issue describing the correct solution, and raise it before proceeding.
- Where a temporary measure is unavoidable and explicitly approved, it must be: (a) isolated behind an interface, (b) covered by a test that will fail when the real fix lands, (c) linked to a tracking issue, and (d) noted in this spec.

**Review question, asked on every PR:** *"If we have to change this in six months, how much breaks?"* If the answer is "a lot," the design is wrong.

### 5.4 Reusability

- Before writing a widget, search `shared/widgets/`. Before writing a utility, search `core/`.
- The **third** occurrence of a pattern gets extracted. The second is watched. (Premature abstraction is its own failure mode.)
- Extracted components must be genuinely feature-agnostic — no feature-specific imports, no feature-specific parameters, no `isTimeline` booleans.
- Every shared widget ships with a widget test and an entry in the internal component gallery.
- Duplication of *domain logic* is never acceptable, even once. Duplication of *layout* is tolerable until the pattern is clear.

### 5.5 Testing

| Layer | Requirement |
|---|---|
| Domain | Unit tests, 90%+ coverage, no mocks needed (pure Dart) |
| Application | Unit tests for every command: execute, undo, redo, serialise, deserialise |
| Presentation | Widget tests for every shared widget and every panel's core interaction |
| Integration | One end-to-end test per phase exit criterion |
| Golden | Canvas rendering, curve evaluation, layout solve |
| Performance | Benchmark tests asserting the §4.9 budgets |

**Non-negotiable:** every command has a test proving `execute → undo` returns the document to a byte-identical state.

### 5.6 CI Gates

A PR merges only when all of these pass:

1. `dart format --set-exit-if-changed`
2. `flutter analyze` — zero warnings, zero infos
3. All tests pass
4. Coverage does not decrease
5. Import-boundary check: no `package:flutter` in `core/model/`, no cross-feature imports
6. Performance benchmarks within budget
7. At least one approving review
8. Spec updated if scope changed

---

## 6. Git Workflow

**Rule: a branch and a pull request for every feature. No exceptions. No direct commits to `main`.**

### 6.1 Branch Naming

```
feature/<system>-<short-description>
fix/<system>-<short-description>
refactor/<system>-<short-description>
perf/<system>-<short-description>
docs/<short-description>
```

Examples:
```
feature/hierarchy-drag-drop-reorder
feature/timeline-keyframe-insertion
fix/canvas-hit-test-precision
perf/hierarchy-virtualised-scroll
```

### 6.2 Branch Scope

One branch = one feature = one PR. If a branch touches three systems, it should have been three branches.

A branch is too big if:
- It changes more than ~400 lines of non-generated code
- Its description needs the word "and" more than once
- It cannot be reviewed in under 30 minutes

Split it. Stacked PRs are preferred over one large PR.

### 6.3 Commit Messages

Conventional Commits:

```
feat(hierarchy): add drag-and-drop reordering
fix(canvas): correct hit test at non-unit zoom
refactor(timeline): extract track evaluation into pure function
perf(hierarchy): virtualise tree rendering
test(commands): add undo round-trip tests for transform commands
docs(spec): mark Phase 1 canvas acceptance complete
```

Commits are atomic. Each one compiles and passes tests on its own.

### 6.4 Pull Request Template

Every PR body contains:

```markdown
## What
One-sentence description.

## Spec Reference
Section §X.Y — <system name>. Phase N.

## Why
The problem being solved. If this is a fix, the **root cause**, not the symptom.

## Approach
Key design decisions. Why this approach over the alternatives considered.

## Robustness Check
- [ ] No temporary workarounds introduced
- [ ] No new switch statements on node/tool/property type
- [ ] All mutations go through the command system
- [ ] Commands are serialisable and deterministic
- [ ] No cross-feature imports added
- [ ] Existing abstractions reused where applicable

## Testing
What was tested and how. Benchmark results if a performance budget applies.

## Spec Updates
Which acceptance checkboxes this ticks, or what was added to the spec.

## Screenshots / Recording
For any UI change.
```

### 6.5 Review Standards

Reviewers explicitly check:
1. Does it match the spec section it claims?
2. Is anything here temporary? (§5.3)
3. Could this have reused something existing?
4. Will this need a rewrite when the next phase lands?
5. Are the tests real tests, or coverage theatre?

**Blocking a PR for a temporary solution is always correct**, even under deadline pressure. The rule exists precisely for deadline pressure.

### 6.6 Merge

- Squash merge into `main` with the PR title as the commit message.
- Delete the branch after merge.
- `main` is always releasable.

---

## 7. Agent Operating Instructions

For any AI agent building against this spec:

1. **Read this document before starting any task.** Re-read the relevant system section and §5 before writing code.
2. **Identify the spec section** the task belongs to. If there isn't one, stop and ask — do not invent scope.
3. **Create the branch first** (§6.1), before writing any code.
4. **Check the phase.** If the task belongs to a later phase and the current phase's exit criteria are unmet, raise it rather than proceeding.
5. **Search before writing.** Check `shared/` and `core/` for an existing solution.
6. **Write the command and its test before the UI.** The model and command layer come first; widgets come last.
7. **When blocked, choose the robust path.** If the robust path is out of scope, stop and report — never substitute a workaround (§5.3).
8. **Open the PR** using the §6.4 template.
9. **Update this spec** in the same PR: tick acceptance boxes, add anything discovered.
10. **Never merge your own PR without review.**

### Definition of Done

A feature is done when:
- [ ] It works
- [ ] Its spec acceptance criteria are all ticked
- [ ] It has domain, command, and widget tests
- [ ] It introduces no temporary solutions
- [ ] It reuses existing abstractions where they exist
- [ ] It meets its performance budget
- [ ] It passes all CI gates
- [ ] It has been reviewed and merged via PR
- [ ] This spec has been updated

---

## 8. Open Questions

Track decisions that are not yet made. Nothing here may be silently resolved in a PR — resolving one is its own change to this document.

| # | Question | Owner | Status |
|---|---|---|---|
| 1 | State management: Riverpod vs. Bloc vs. signals — pick one, document here | | Open |
| 2 | Rive runtime binding strategy: FFI vs. platform channels vs. `rive_native` | | Resolved: `rive_native` (PR #1-#7 built on it; revisit only if the package blocks an editor feature) |
| 3 | Document persistence format for editor-only metadata alongside `.riv` | | Open |
| 4 | Web renderer parity — does Phase 1 target web at all? | | Open |
| 5 | Collaboration transport: OT vs. CRDT (constrains §4.4 command design) | | Open |
| 6 | Minimum supported Flutter / Dart versions | | Open |

---

## 9. Change Log

| Date | Change | PR |
|---|---|---|
| 2026-07-24 | Initial specification | — |
| 2026-07-24 | §4.4 command system implemented: `EditorCommand`, `CommandProcessor` (undo/redo, merge coalescing, bounded history), serialisation codec registry, typed `CommandFailure`s. All existing mutations (keyframe retime, rename, hide, reparent, duplicate, delete, add artboard, import asset) routed through commands with execute→undo byte-identity tests. Resolved open question #2 (`rive_native`). | refactor/core-command-system |
| 2026-07-24 | §2.4 tool contract implemented: `EditorTool` interface (pointer/key/overlay/cursor/activate), `ToolRegistry` + `ToolController` (registration, shortcut resolution). Selection (marquee overlay), Hand, and Zoom tools. §2.3 canvas restructured into content/overlay/interaction layers behind separate `RepaintBoundary`s, all consuming one `ViewTransform` (pure Dart, unit-tested). Toolbar strip generated from the registry. | feature/canvas-tool-registry |
| 2026-07-25 | §2.2 selection service implemented: `SelectionService` in `core/services` with replace/toggle/range modes, primary + anchor, structural remap migration. `SceneNodeRef` promoted to `core/model`. Hierarchy rows select through the service (cmd/ctrl-click toggles); inspector derives its subject from the shared primary selection; duplicate per-panel selection state removed. Ticks §2.2 "Selection state is shared with Canvas and Inspector via a single selection service". | feature/core-selection-service |
| 2026-07-25 | §2.4 Rectangle and Ellipse tools implemented via `ShapeCreationTool` base (drag-to-size, ghost overlay preview, minimum-extent guard). `RivShapeFactory` writes the runtime shape recipe (Shape → ParametricPath → Fill → SolidColor with correct parent links); `AddShapeCommand` is serialisable with byte-identity undo. `ToolContext` gained `dispatch`/`activeArtboardOrdinal` so tools mutate only through commands. Engine-decode integration test proves the shipping runtime accepts and resolves created shapes. | feature/canvas-shape-tools |
| 2026-07-25 | §2.3 canvas hit testing + click/marquee selection: `SceneHitTester` (topmost-first point queries, rect queries) over `RivHitRegions` derived from document objects (node translation + parametric path size, accumulated through the tree). Selection tool now selects on click (cmd/ctrl toggles via event modifiers, testable without bindings), marquee-selects from empty space, clears on empty click, and draws selection outlines + corner handles on the overlay. Hit index cached per document epoch, never rebuilt per pointer event. | feature/canvas-hit-testing |
| 2026-07-25 | §2.5 inspector property grid: `PropertyDescriptor` + `PropertyMetadataRegistry` in `core/model` (registration per type key, no per-node-type widget code); `SetComponentPropertyCommand` (serialisable, mergeable so numeric drags coalesce to one undo entry, byte-identity undo); `PropertyGrid` renders groups from metadata with drag-to-adjust + text-entry numeric fields; inspector shows the grid for the primary selection plus animated values when keyed. | feature/inspector-property-grid |
| 2026-07-25 | §2.2 virtualised hierarchy: `SceneTreeFlattener` (pure) flattens trees to visible rows once per state change; panel renders via `ListView.builder` with fixed item extent so only on-screen rows exist. Shift-range selection lands via flattened visual order + the selection service anchor. Benchmark test: flattening 10k visible nodes stays under 16ms. | feature/hierarchy-virtualised-tree |
| 2026-07-25 | Theme: right-click menus, MenuAnchor menus, dialogs, text fields, buttons, and snackbars styled centrally in `EditorTheme.dark()` (popupMenu/menu/menuButton/dialog/input/snackbar themes; no per-widget restyling). Shared `showEditorContextMenu` in `shared/widgets` with compact rows, icons, and destructive styling; scene hierarchy context menu migrated to it. Widget tests per §5.5 shared-widget rule. | fix/theme-context-menus |
| 2026-07-25 | Canvas fixes: pointer routing/cursor/overlay now rebuild on tool switch (canvas observes the ToolController; previously the panel captured a stale tool and shortcuts appeared dead after Z). Artboard content anchored at scene (0,0) and sized to artboard bounds so hit regions, selection outlines, and shape-tool previews align exactly with rendered pixels; view auto-fits per artboard switch and the fit button fits the artboard. | fix/canvas-stale-tool-routing |
| 2026-07-25 | §2.4 Phase 1 toolbar completed: Polygon tool (P, drag-to-size, pentagon ghost, points property) and Text tool (T, click-to-place, themed content dialog, font embedded as FontAsset+FileAssetContents with per-name dedup, TextStylePaint→Fill→SolidColor + TextValueRun recipe). `AddTextCommand` serialisable with byte-identity undo; FontProvider interface isolates asset access (§4.6). Engine-decode integration test for text. Also fixed painter-time notifications scheduling builds during paint (coalesced to post-frame with dispose guard). | feature/toolbar-polygon-text |
| 2026-07-25 | Rendering fix: parametric paths were written with LayoutComponent width/height keys (7/8) instead of ParametricPath keys (20/21), so the runtime saw zero-size paths and painted nothing — shapes existed in the hierarchy but were invisible. Factory and hit regions now use keys 20/21. Every new shape also gets a 2px black Stroke→SolidColor outline so it reads on any background. SHORTCUTS.md added documenting all implemented shortcuts, linked from README. | fix/shape-parametric-size-keys 
| 2026-07-25 | Artboard creation flow: editor now starts with a blank document instead of auto-loading the bundled demo. New Document and Add Artboard prompt via a themed `ArtboardSpec` dialog (name, width/height px, transparent or hex background). `RivDocumentBuilder` writes an optional artboard background as Fill→SolidColor (artboard is a ShapePaintContainer); `AddArtboardCommand` carries size + background and stays serialisable. `EditorDocument.decode` uses `frameOrigin: false` so artboard coordinates equal scene coordinates and shapes render exactly where drawn. | feature/artboard-creation-flow |
| 2026-07-25 | §2.3/§2.4 drag-to-move: selection tool moves the whole selection when dragging a selected component (3px view-space threshold so clicks never nudge). `MoveComponentsCommand` (serialisable, mergeable, byte-identity undo) carries every dragged component so a multi-selection drag is one history entry. `ToolContext.componentTranslation` lets tools read start positions without document knowledge. `RivHierarchy.componentObjects` centralises the component-index resolver formerly duplicated in `RivHitRegions` and `SetComponentPropertyCommand`. | feature/canvas-move-shapes ||