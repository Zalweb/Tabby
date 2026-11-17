# Situation mascot artwork and animation

2026-11-17T14:30:25.234Z. User supplied five generated transparent PNGs and approved their roles after visual review. Original image bytes are copied unchanged; no generation, recoloring or raster edit was performed. [Exact hashes/dimensions/alpha crop bounds](../../assets/branding/mascot/artwork-manifest.json).

| Asset | Role | Motion |
|---|---|---|
| tabby-thinking.png | Loading/calculating | Soft nod and breath |
| tabby-waiting.png | Submitted/pending | Calm sway and breath |
| tabby-helpful.png | Offline/error/retry/404 | Restrained sway |
| tabby-reminder.png | Friendly due/overdue reminder | Gentle tilt |
| tabby-celebrating.png | Tab created or confirmed payment | Finite three-hop decay, then still |

Existing welcome/notebook images use the same engine; idle/sleeping keep the original blink sprite. Raster1254x1254 originals have transparency. Alpha-derived normalized source rectangles remove unequal gutters at render time; common bottom-center fitting preserves consistent visual anchor. Decode to display/DPR size capped1024 except original multi-frame blink sheet, which needs its full shared1254px source. Repaint isolation keeps surrounding layout quiet.

The supplied images support whole-body transforms, not independent eyes/paws/tail articulation. Existing idle blink works from its supplied eight-frame sheet. If requested later, true waving needs matching arm/paw-up/intermediate/down frames or separated layers, tail swishing needs matching tail positions/layers, and blinking in new poses needs open/half/closed-eye frames with unchanged body registration. None is required for the implemented motion. Static per-pose art is the reduced-motion fallback.

[Implementation plan](../plans/situation-mascot-animation.md), [task](../progress/tasks/QA-031.md). No private original temp paths or financial screenshots in tracked evidence.

2026-11-17T19:07:11.599Z - Superseding user-approved articulation: [five generated frame sheets](articulated-mascot-frames.md) and shared sparse playback are now implemented and installed in private21. Original files remain unchanged as still fallbacks; prior future-frame requirement is now fulfilled for these situation poses.
