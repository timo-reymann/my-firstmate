---
name: board-design
description: >-
  Load before building any HTML board or visual artifact for firstmate, such as a lavish-axi review board, a scout's visual deliverable, or a decision page, and before restyling the Bearings board.
user-invocable: false
metadata:
  internal: true
---

# board-design

The captain approved one look for every firstmate board: orange header band, square corners, material shadow, Source Sans 3, and light and dark mode that follow the OS.
This skill owns that look and the rules for using it.
`assets/board.css` is the complete stylesheet; the rules below say how to use it.
The captain named this design system, so it takes priority over the default look that `lavish-axi design` suggests.

## Usage rule

1. Paste `assets/board.css` once, as the first `<style>` after `<!doctype html>`.
   Do not mix it with DaisyUI or Tailwind.
2. Wrap the page in `<main class="ds-board">` and open with `.ds-header` plus one `.ds-verdict` that states the answer.
3. Take colour only from `--ds-*` tokens and never hard-code a hex value.
4. Status is one class: `is-action` ▶ needs the captain (charcoal), plus `is-pending` 🟠, `is-finalizing` 🔵, and `is-blocked` 🔴, which match the emoji in chat.
5. Use green `is-success` or `is-done` ✓ for passed or finished work, and `is-warning` for risk.
   Never use green for "your move".
6. Badges get their glyph from CSS, so you write only the word.
7. Give each captain question its own `.ds-decision`, with the recommended option marked `.ds-rec` and one Queue button.
8. Render code with `@pierre/diffs` (`github-light` and `github-dark`) inside `.ds-code-frame`.
9. Draw diagrams as inline SVG `.ds-flow`, with nodes as `<g class="n is-*">`.
10. Light and dark follow the OS, and `data-theme="light"` or `data-theme="dark"` on `<html>` forces one.

## Components

| Component | Class |
|---|---|
| Header | `.ds-header` |
| Verdict band | `.ds-verdict` |
| Card | `.ds-card` |
| Decision card | `.ds-decision`, with `.ds-choice` options and a `.ds-rec` marker |
| Option comparison | `.ds-options` and `.ds-option`, `.is-recommended`, `.ds-pro` and `.ds-con` |
| Table | `.ds-table-wrap` and `.ds-table`, `.ds-num` |
| Step timeline | `.ds-steps` and `.ds-step` |
| Code or diff frame | `.ds-code-frame` around `@pierre/diffs`; `.ds-code` for command output |
| Callout | `.ds-callout` |
| Badge | `.ds-badge`, `.is-solid` |
| Button | `.ds-btn`, `.ds-btn--quiet` |
| Flow diagram | `.ds-flow` with `.n`, `.e`, `.e.is-hot`, `.lbl` |

One tone class (`is-action`, `is-success`, `is-done`, `is-pending`, `is-finalizing`, `is-info`, `is-blocked`, `is-danger`, `is-warning`) colours a component and its children.
Without one, a component falls back to neutral.

## Status parity with chat

`bin/fm-status-render.sh` owns the chat emoji.
On a board, pending, finalizing, and blocked print the same emoji as chat, and the action badge is a charcoal ▶ because green means success on boards.
`tests/fm-board-design-parity.test.sh` pins this, so change the glyphs in `assets/board.css` and the renderer together.

## Scope

This look is for firstmate's own boards only.
Do not edit the vendored `lavish` skill to add it, because a reinstall would overwrite the edit.
The review panel in `lavish-url` keeps its own isolated styling.
