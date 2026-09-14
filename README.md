# Melee Bots

5-a-side AI robot brawl in Godot 4 (3D) — the armed cousin of [Rock Bots](https://github.com/nathandunn/rock-bots).
The field is strewn with rocks, bats, knives, swords and spears. Pure spectator sim: set each
team's personality and the armoury, watch, or batch-run matches for statistics.

Part of the Precog sim suite (sibling of Rock Bots / Battle Bots / Pack Hunt / War Sim).

## The brawl

| thing | value |
|---|---|
| teams | 5 v 5, last team standing, no clock (headless sims are capped, `--cap=300` s) |
| armoury | editable in *Teams / setup*: default 3 rocks, 2 bats, 2 knives, 1 sword, 2 spears — one thing per robot, scattered at the start. Everything lies where it falls and can be picked up by anyone |
| rocks | thrown: 18 m/s, ~20 m range, three sizes (1.2 / 2 / 3.2 kg); damage from the rock's energy relative to the target (up to 50 % of max HP), always floors you. Friendly fire on |
| bat | reach 2.3 m, wind-up 0.35 s, every 1.0 s, 25 % of max HP, floors 85 % × quality |
| knife | reach 1.6 m, wind-up 0.12 s, every 0.45 s, 14 %, floors 35 % × quality; can be thrown |
| sword | reach 2.4 m, wind-up 0.3 s, every 0.9 s, 32 %, floors 60 % × quality |
| spear | reach 3.2 m, wind-up 0.4 s, every 1.1 s, 22 %, floors 55 % × quality; can be thrown (1.8 kg) |
| fists / feet | as Rock Bots: punch 20 % every 0.6 s (wind-up 0.22 s), kick 20 % every 0.9 s (wind-up 0.3 s, reach 2 m), stomp on the floored 12 % |
| **dropping** | **every knockdown — flop or floor — makes you drop what you hold.** A landed weapon blow always knocks the target down. Being hit cancels whatever you were winding up. So when two robots swing at each other, **he who connects first keeps his weapon and the other loses his: timing is everything** (a knife's 0.12 s wind-up beats a spear's 0.4 s at close quarters; the spear's 3.2 m reach means the knife never gets there if the spearman sees him coming) |
| a blow to a man on the floor | 60 % of the weapon's damage, and he stays down another 0.5 s |
| hitboxes | head, torso, 2 arms, 2 legs; hit quality = parts struck / "full" parts for punches, rocks and close weapon blows |
| eyes | ~190° field of view, no seeing through cover. Rocks, thrown knives and spears, punches, kicks and swings are dodged only if seen coming |
| ragdolls | every knockdown and death; winners dance 2 s, squat over and relieve themselves on the fallen |

All numbers are `const`s at the top of `scripts/robot.gd` and the `DATA` table in `scripts/weapon.gd`.

## Personalities

Seven 0–1 traits (`scripts/personality.gd`): `aggression`, `caution`, `rock_love` (prefers throwing —
rocks, and knives or spears at ≥ 0.6 — over swinging), `teamwork`, `patience`, `survival`, `protect`.
Presets: Brawler, Slinger, Coward, Tactician, Guardian, Balanced, Random. Accuracy is the same for
everyone (`Robot.ACCURACY`).

Weapons on the ground are valued (sword 1.0, spear 0.9, bat 0.85, knife 0.6, rock 0.45 — rocks, spears
and knives more for rock-lovers) and discounted by distance; an unarmed robot goes for the best deal.
A weapon in hand settles the boxing question: whoever holds a bat fights with it (cowards still poke and run).

## Controls / stats / build

Same as Rock Bots: Pause/Play, 1–8×, Teams / setup (presets, sliders, armoury), Live list (shows what each
robot holds), Last results, New match, Batch ×10. Results add weapon swings / hits, weapon damage, and
weapons dropped, per team and per robot.

```
godot --headless --path . -- --sim=20 --red=Brawler --blue=Slinger --seed=1 [--cap=300]
```

Godot 4.4.1+, GL Compatibility, GDScript only, everything built in code (`scenes/Main.tscn` is the only
scene). Web export preset in `export_presets.cfg` (threads off).

## Layout

```
scripts/main.gd           wiring, sim speed, batch mode, CLI args
scripts/match_manager.gd  spawn teams + armoury, winner, stats, celebration phases
scripts/robot.gd          body + hitboxes, movement, utility AI, punch/kick/swing/throw, celebration
scripts/weapon.gd         rocks and weapons: kinds, held/thrown/dropped states, thrown impact damage
scripts/ragdoll.gd        six-part pinned ragdoll
scripts/personality.gd    traits + presets
scripts/arena.gd          floor, walls, cover
scripts/camera_rig.gd     orbit camera (follows the celebration)
scripts/hud.gd            scoreboard, setup, results
```
