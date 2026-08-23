# Layout limitations

What the built-in layout strategy in `PS.DrawIO.Core` does **not** do.

v1 ships a **defined, deterministic** placer — not a good graph-drawing algorithm
(`CORE.md` §9, Explicitly NOT in v1).

## Not implemented

- **No edge routing** — edges receive no waypoints; routing is a later pass.
- **No crossing minimisation** — edge crossings are not considered.
- **No hierarchical / Sugiyama ranking** — call graphs are not layered by depth.
- **No force-directed or organic layout** — positions are grid/stack only.
- **No text measurement** — default width/height are constants, not font metrics.
- **No collision repair beyond the grid** — siblings are placed on a fixed pitch
  so they do not overlap; free-form packing is not attempted.
- **No draw.io Desktop CLI `--layout`** and no `#create` / `applyLayouts` back-end
  (both Explicitly NOT in v1).

## What it does

- Assigns flat `X`, `Y`, `Width`, `Height` on every vertex (`IsEdge` nodes skipped).
- Places top-level vertices on a deterministic multi-column grid.
- Honors `LayoutHints` with `Kind = 'Stack'` only: listed `Targets` are ordered
  first among vertices. Unknown hint kinds are ignored.
- Children with a `ParentId` that resolves to a node in the same IR are placed
  **relative to the parent origin** (group padding), not the canvas.
- Same IR in → same coordinates out (stable for a future golden-file corpus).

## Geometry ownership

All numeric geometry constants live under paths matching `Layout` in `src/`.
Providers declare hints; Core decides pixels. Providers never ship placement.
