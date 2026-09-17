# Melee Bots

5-a-side AI robot brawl in Godot 4 (3D) — the armed cousin of [Rock Bots](https://github.com/nathandunn/rock-bots).
The field is strewn with rocks, bats, knives, swords, spears, bottles — and a cat and a baby,
which are for throwing. Pure spectator sim: set each team (or each individual robot) a **type**
and a **personality**, set the armoury, watch, or batch-run matches for statistics.

Part of the Precog sim suite (sibling of Rock Bots / Battle Bots / Pack Hunt / War Sim).

## The brawl

| thing | value |
|---|---|
| teams | 5 v 5, last team standing, no clock (headless sims are capped, `--cap=300` s) |
| armoury | editable in *Teams / setup*: default 3 rocks, 2 bats, 2 knives, 1 sword, 2 spears, 2 bottles, 1 cat, 1 baby — scattered at the start. Everything lies where it falls and can be picked up by anyone |
| rocks | thrown: 18 m/s, ~20 m range, three sizes (1.2 / 2 / 3.2 kg); damage from the rock's energy relative to the target (up to 50 % of max HP), always floors you. Friendly fire on |
| bat | reach 2.3 m, wind-up 0.35 s, every 1.0 s, 25 % of max HP, floors 85 % × quality |
| knife | reach 1.6 m, wind-up 0.12 s, every 0.45 s, 14 %, floors 35 % × quality; can be thrown |
| sword | reach 2.4 m, wind-up 0.3 s, every 0.9 s, 32 %, floors 60 % × quality |
| spear | reach 3.2 m, wind-up 0.4 s, every 1.1 s, 22 %, floors 55 % × quality; can be thrown (1.8 kg) |
| bottle | reach 1.5 m, wind-up 0.16 s, every 0.5 s, 18 %, floors 50 % × quality; can be thrown (0.8 kg) — and **it shatters on the first blow it lands**, thrown or swung, leaving you with nothing. A pub weapon: one good swing is all it owes you |
| cat | thrown only (4.5 kg). Claws: 70 % of the thrown-damage model, and it **floors anyone** whatever the sums say. Lands, screeches, and scampers a few metres off under its own steam, so it is somewhere new next time anyone wants it |
| baby | thrown only (3.5 kg). 28 % damage — it barely hurts — but it floors anyone too, and it **bounces** (0.72 restitution) and giggles. A swaddled cartoon bundle in a bobble hat; nothing in this game is drawn to look real, least of all this |
| fists / feet | as Rock Bots: punch 20 % every 0.6 s (wind-up 0.22 s), kick 20 % every 0.9 s (wind-up 0.3 s, reach 2 m), stomp on the floored 12 % |
| **dropping** | **every knockdown — flop or floor — makes you drop what you hold.** A landed weapon blow always knocks the target down. Being hit cancels whatever you were winding up. So when two robots swing at each other, **he who connects first keeps his weapon and the other loses his: timing is everything** (a knife's 0.12 s wind-up beats a spear's 0.4 s at close quarters; the spear's 3.2 m reach means the knife never gets there if the spearman sees him coming) |
| a blow to a man on the floor | 60 % of the weapon's damage, and he stays down another 0.5 s |
| hitboxes | head, torso, 2 arms, 2 legs; hit quality = parts struck / "full" parts for punches, rocks and close weapon blows |
| eyes | ~190° field of view, no seeing through cover. Rocks, thrown knives and spears, punches, kicks and swings are dodged only if seen coming |
| ragdolls | every knockdown and death; winners dance 2 s, squat over and relieve themselves on the fallen |

All numbers are `const`s at the top of `scripts/robot.gd` and the `DATA` table in `scripts/weapon.gd`.

## Types — what a robot *is*

Five properties that always add up to 1 (`scripts/robot_type.gd`), the same budget idea as the
builds in Dodgeball Bots: `brawn` (damage dealt), `speed` (movement), `grit` (HP), `reflex`
(wind-ups and reactions), `aim` (throwing accuracy and lead). An even 0.2 share reproduces the
original constants exactly — 200 HP, 6 m/s, 0.7 accuracy — so a field of Even robots fights
precisely the match it always did. Below an even share a property falls away on a curve
(`CURVE`, 0.8) rather than off a cliff; above it the return is linear.

Presets: Even, Bruiser, Runner, Tank, Sniper, Ghost, Random.

**Levelling.** Each specialist was played against Even, 20 matches at a time, Balanced
personality both sides. The first pass had reflex and speed running away with it — in a game
where the man who connects first keeps his weapon, a short wind-up beats a big hit — and brawn
and aim worth almost nothing, so their spans were widened and the other two reined in, and
`CURVE` was raised from 0.45 to 0.8 to make specialising cost something. Where it landed
(specialist win rate vs Even, n = 20 each, so ±11 points is one sigma):

| | Bruiser | Runner | Tank | Sniper | Ghost |
|---|---|---|---|---|---|
| wins vs Even | 60 % | 45 % | 40 % | 55 % | 30 % |

Mean 46 %, everything inside about 1.5σ of even. A first pass, not a finished calibration —
there is no `calibrate.py` here yet (Dodgeball Bots has one, and this wants the same treatment).

## Personalities

Seven 0–1 traits (`scripts/personality.gd`): `aggression`, `caution`, `rock_love` (prefers throwing —
rocks, and knives or spears at ≥ 0.6 — over swinging), `teamwork`, `patience`, `survival`, `protect`.
Presets: Brawler, Slinger, Coward, Tactician, Guardian, Balanced, Random. Accuracy is the same for
everyone (`Robot.ACCURACY`).

Weapons on the ground are valued (sword 1.0, spear 0.9, bat 0.85, knife 0.6, rock 0.45 — rocks, spears
and knives more for rock-lovers) and discounted by distance; an unarmed robot goes for the best deal.
A weapon in hand settles the boxing question: whoever holds a bat fights with it (cowards still poke and run).

## Sound

Every sound is synthesised in GDScript at startup (`scripts/sfx.gd`) — there is not an audio
file in this repo, for the same reason there are no mesh assets. Each cue is a PCM recipe: an
envelope over some mix of sines, sweeps and filtered noise, rendered once into an
`AudioStreamWAV` and played from a round-robin pool of twenty `AudioStreamPlayer3D`s, so a
ten-robot brawl never runs out of voices. Thirteen cues: swing, thud, clang, bonk, smash, meow,
screech, giggle, boing, clatter, death, cheer, pickup. Repeats of the same cue inside 45 ms are
dropped as duplicates. **Sound on / off** is in the button row; headless builds nothing at all.

## Controls / stats / build

Pause/Play, 1–8×, Teams / setup, Live list (shows what each robot holds), Last results, New
match, Batch ×10, Sound on/off. Results add weapon swings / hits, weapon damage, and weapons
dropped, per team and per robot, and name each robot's type as well as its personality.

**Teams / setup** sets each side two ways. The two pickers at the top set the *whole team*'s
type and personality at once; the row of five below gives any single robot its own (the ring
icon means "follow the team"). Every icon has its meaning on the hover, and the **?** beside
each team opens the whole key. The sliders under each team edit that team's personality traits
and type properties directly — dragging one type slider takes the difference out of the other
four in proportion, because the budget is the point.

```
godot --headless --path . -- --sim=20 --red=Brawler --blue=Slinger --seed=1 [--cap=300]
godot --headless --path . -- --sim=20 --redtype=Bruiser --bluetype=Ghost   # or --type= for both
godot --headless --path . -- --sim=20 --loadout=cat:6,baby:6,rock:0        # point it at one weapon
```

A browser has no command line, so on the web the query string stands in for one:
`index.html?loadout=cat:4,rock:0&redtype=Sniper` does the same thing — handy for screenshots.

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
