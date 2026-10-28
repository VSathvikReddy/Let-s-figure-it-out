# ENTROPY - sinan/ layout

Everything here is self-contained: scenes reference each other by `res://sinan/...`.

| Folder | What lives there |
|---|---|
| `levels/` | Playable levels (`level.tscn`). |
| `actors/player/` | Player scene + controller (movement, double jump, weapon, machete). |
| `actors/enemies/<name>/` | One folder per enemy: its scene, script and its own projectiles / effects (witch orbs, priest smoke + fire, Forger orbs...). Every enemy is a node scene with an AnimationPlayer, a `Light` node and (fliers) an `AttackTrail`. |
| `actors/enemies/hit_info.gd` | Shared hit data (single vs area hits, blast falloff, stagger rule). |
| `weapons/` | Weapon scenes (one equipped at a time). `weapons/projectiles/` = bullets, rockets, orbs. |
| `world/platforms/` | `hanging_board.tscn` (swinging board) and `chain_rope.gd`. |
| `world/navigation/` | `nav_graph.gd` (enemy routes between boards, floor height). |
| `world/portals/` | Portals and the portal director. |
| `painting/` | The painting: distortion layers, `Paint.hit()` (the one entry point for touching the painting), picking points in it. |
| `fx/core/` | `FxLib` (pooled particle bursts, shared gradients), particle fire, cloth, motion trails. |
| `fx/blasts/`, `fx/marks/` | Explosions / ripples, and marks left behind (slashes, claw marks, paint). |
| `systems/` | Game data (drops), progress + skill tree data, the batched coin field. |
| `ui/` | HUD, menus, aim reticle / guide, F3 debug overlay. |
| `shaders/` | All shaders. |
| `assets/` | Art: `characters/`, `props/`, `items/`, `weapons/`, `painting/` (layer images + frame), `source_sheets/` (original sheets parts were cut from), `_unused/`. |

## Adding things
- **Enemy:** new folder in `actors/enemies/`, a CharacterBody2D scene on collision layer 2, `add_to_group("enemies")`, implement `take_hit(amount, from, info)` and `on_explosion_damage(pos, radius, damage)` (use `HitInfo.blast_damage`).
- **Touching the painting:** always `Paint.hit(...)` - never the layers directly.
- **One-shot particles:** `FxLib.burst(parent, {...}, pos)` - pooled, cheap to call every hit.
- **Platform:** drop `world/platforms/hanging_board.tscn` into the level's `Platforms` node; move its anchor markers; tune Swing / Pushes in the Inspector. Navigation picks it up automatically.
