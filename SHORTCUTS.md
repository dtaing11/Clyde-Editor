# Keyboard Shortcuts

All shortcuts implemented in Clyde Editor so far. Tool shortcuts resolve
through the tool registry, so this table stays accurate as tools are
added.

> macOS uses **Cmd**; Windows/Linux use **Ctrl**. Both are bound.

## File

| Shortcut | Action |
|---|---|
| `Cmd/Ctrl + N` | New document |
| `Cmd/Ctrl + O` | Open… (File menu) |
| `Cmd/Ctrl + S` | Save (File menu) |
| `Shift + Cmd/Ctrl + S` | Save As… (File menu) |

## Edit

| Shortcut | Action |
|---|---|
| `Cmd/Ctrl + Z` | Undo |
| `Shift + Cmd/Ctrl + Z` | Redo |

## Tools

| Shortcut | Tool | Behaviour |
|---|---|---|
| `V` | Selection | Click selects the topmost shape; drag a selected shape to move the whole selection; drag on empty space draws a marquee |
| `H` | Hand | Drag to pan the canvas |
| `Z` | Zoom | Click zooms in; right-click zooms out (anchored at the cursor) |
| `R` | Rectangle | Drag to size; releases creates the shape |
| `O` | Ellipse | Drag to size; releases creates the shape |
| `P` | Polygon | Drag to size; creates a pentagon (5 points) |
| `T` | Text | Click to place; a dialog asks for the content |
| `I` | Eyedropper | Click a shape to sample its fill; applies to selected shapes' fills (or just samples when nothing is selected) |

## Selection modifiers

| Shortcut | Action |
|---|---|
| `Cmd/Ctrl + Click` | Toggle a node in/out of the selection (canvas and scene tree) |
| `Shift + Click` | Range-select between the anchor and the clicked row (scene tree) |
| Click empty canvas | Clear the selection |

## Animation

| Shortcut | Action |
|---|---|
| `Shift + Cmd/Ctrl + A` | New animation on the active artboard |
| `K` | Keyframe the selected shape's X/Y at the playhead (creates an animation first when none exists) |

## Curve editor

| Gesture | Action |
|---|---|
| Drag empty space | Box-select control points |
| Drag a selected point | Move the whole selection (frames + values) |
| `Alt/Option + drag` a selected point | Scale the selection in time around its first frame |
| Drag an orange square | Reshape the cubic ease (tangent handle) |

## Playback

| Shortcut | Action |
|---|---|
| `Space` | Play / pause the selected animation |

## Canvas navigation

| Input | Action |
|---|---|
| Scroll wheel / trackpad | Zoom in/out anchored at the cursor |
| Zoom controls (bottom right) | Zoom out · current % (click resets) · zoom in · fit artboard |

## Scene hierarchy

| Input | Action |
|---|---|
| Double-click a row | Rename |
| Right-click a row | Context menu: Rename, Duplicate, Lock/Unlock, Hide/Show, Delete |
| Drag a row onto another | Reparent (blocked into own subtree and onto locked nodes) |

## Inspector

| Input | Action |
|---|---|
| Drag a property label horizontally | Scrub the value (one undo entry per drag) |
| Click a property field | Type an exact value; Enter commits |

## Timeline

| Input | Action |
|---|---|
| Click / drag the ruler | Scrub the playhead |
| Drag a keyframe diamond | Retime the keyframe |
| `f` / `s` toggle (header) | Switch time display between frames and seconds |
