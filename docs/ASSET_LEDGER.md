# Asset ledger

Every third-party file in the game is listed here with its source and licence. The credits screen
is built from this file. Downloaded on 2026-11-13 through the director's own Chrome.

Rules that follow from these licences:

- **The repository is public (2026-11-17, the director's call), so raw downloads never go into it.**
  Sonniss and Mixamo terms forbid redistributing raw files: `_downloads/` is git-ignored and only the
  finished game may contain them. Everything under `assets/` is CC0, CC BY 4.0, MIT or OFL, which allow
  redistribution with the credits in `CREDITS.md`.
- **CC BY assets need a credit line** in the in-game credits and the store page (see "Credit" column).
- **AI disclosure:** the hero cat model is labelled "Generated with AI" on Sketchfab. Steam requires the
  AI-generated content disclosure on the store page for pre-generated content like this.
- Raw downloads live in `_downloads/` (git-ignored, Godot-ignored). Only processed copies live in `assets/`.

| Asset | Used for | Source | Author | Licence | Credit |
|---|---|---|---|---|---|
| Sphynx Cat – Rigged & Animated (10 Anims), GLB 4k | Hero cat "Trophe" (`assets/models/cat/sphynx_cat.glb`) | https://sketchfab.com/3d-models/sphynx-cat-rigged-animated-10-anims-0b86bde7a8b64fd7a459035b339a790f | Animal Animator | CC BY 4.0 (commercial use allowed); page marked "Generated with AI" | "Sphynx Cat by https://animalanimator.com" + link https://animalanimator.com/the-ultimate-sphinx-cat-reference-for-animal-animators/ |
| Universal Animation Library [Standard] v3.0 | Human NPC animations (`assets/models/humans/anim/UAL1_Standard.glb`) | https://quaternius.itch.io/universal-animation-library | Quaternius | CC0 | optional |
| Universal Animation Library 2 [Standard] (+ Mannequin_F) | Human NPC animations | https://quaternius.itch.io/universal-animation-library-2 | Quaternius | CC0 | optional |
| Universal Base Characters [Standard] | Human NPC bodies (`assets/models/humans/base/`) | https://quaternius.itch.io/universal-base-characters | Quaternius | CC0 | optional |
| Ultimate Modular Men Pack (Feb 2022), glTF | The people of the city: 11 figures with 24 clips (`assets/models/humans/city/M_*.gltf`; zips in `_downloads/`) | https://quaternius.com/packs/ultimatemodularcharacters.html | Quaternius | CC0 | optional |
| Ultimate Modular Women Pack (Apr 2022), glTF | The people of the city: 10 figures with 24 clips (`assets/models/humans/city/W_*.gltf`) | https://quaternius.com/packs/ultimatemodularwomen.html | Quaternius | CC0 | optional |
| Ultimate Animated Animal Pack (Jul 2021), glTF | Wildlife and farm animals: 12 animals with 12-13 clips (`assets/models/animals/wild/`) | https://quaternius.com/packs/ultimateanimatedanimals.html | Quaternius | CC0 | optional |
| EZ-Tree presets (Oak L/M, Ash L/M, Aspen L, Pine L/M, Bush 1-3), LOD0-2 GLB | Protected nature (`assets/models/nature/`) | https://www.eztree.dev/ (generator output) | Dan Greenheck (EZ-Tree) | MIT (repository https://github.com/dgreenheck/ez-tree, which also ships the bark/leaf textures; no separate texture licence found) | "Trees generated with EZ-Tree (MIT)" |
| 21 Poly Haven models (vases, alarm clock, cardboard box, barrel, wet floor sign, road barrier, covered car, payphone, street seating, planter box, potted plant, armchair, sofa, table, school chair, drawer cabinet, electric stove, hanging lamp, fern) | Breakable props (`assets/models/props/`) | https://polyhaven.com/models | various (Poly Haven) | CC0 | optional |
| HDRI kloofendal_48d_partly_cloudy_puresky (4k) | Day sky | https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky | Poly Haven | CC0 | optional |
| HDRI belfast_sunset_puresky (4k) | Sunset sky | https://polyhaven.com/a/belfast_sunset_puresky | Poly Haven | CC0 | optional |
| 21 ambientCG PBR materials (2K JPG): Concrete048, Concrete034, Concrete044D, Bricks051, Bricks097, Plaster001, PaintedMetal004, Metal063, RoofingTiles013A, Tiles141, WoodFloor064, Asphalt033, PavingStones142, Gravel043, Ground048, Clay005, Ground054, Rock064, Rock058, Lava004, Grass005 | Building materials and ground strata (`assets/textures/`) | https://ambientcg.com | ambientCG (Lennart Demes) | CC0 | optional |
| Voxel Tools GDExtension 1.7 (v1.7x), Windows + Linux binaries | Diggable terrain (`addons/zylann.voxel/`) | https://github.com/Zylann/godot_voxel/releases/tag/v1.7x (sha256 6007375...a1d2d8, verified) | Marc Gilleron (Zylann) | MIT (ship `addons/zylann.voxel/LICENSE.md` notice) | MIT notice |
| GDC 2026 Game Audio Bundle (5 parts, 7.47 GB) | Sound effects | https://gdc.sonniss.com/ | Sonniss vendors | Sonniss #GameAudioGDC licence v2.0 (27 Aug 2026): royalty-free, commercial, no attribution; no redistribution of raw files; no AI training | not required |

| Animated Dog, Shiba Inu (GLB 2k) | Park dog, invulnerable animal (`assets/models/animals/shiba/shiba.glb`) | https://sketchfab.com/3d-models/animated-dog-shiba-inu-9abfce885a834399b2c3ccaed51cd474 | quander | CC BY 4.0 | "Animated Dog, Shiba Inu by quander (Sketchfab), CC BY 4.0" |
| Pigeon (original GLB) | City pigeons, invulnerable (`assets/models/animals/pigeon/`) | https://sketchfab.com/3d-models/pigeon-ddd5ef4a94eb4159937a9de25c45697c | kenchoo, based on "Pigeon #1" by ₦₥₵ ฿₵ (https://skfb.ly/oQsJv) | CC BY 4.0 | credit both authors |
| Cat Purr & Meow (6 WAV) | Trophe's voice (`assets/audio/cat/`) | https://opengameart.org/content/cat-purr-meow | Kerzoven | CC0 | optional |
| Impact Sounds (130 OGG) | Material impacts: glass, plate (porcelain), metal, wood, mining (stone), footsteps (`assets/audio/impacts/`) | https://kenney.nl/assets/impact-sounds | Kenney | CC0 | optional |
| 76 Freesound sounds (collapse, rubble, concrete, bricks, glass, explosion, wood, metal, car crash, fire, laser, sizzle, whoosh, rumble, dig, ceramic, pigeon, cat hiss, boing, thud, wind, park ambience, fireball, squish, boom, rocks, window) | Sound design sources; only files copied into `assets/audio/sfx/` ship | https://freesound.org (ids, authors and per-file URLs in `_downloads/freesound/manifest.csv`) | various Freesound users | CC0 1.0 (each verified on its page on 2026-11-16) | optional |
| 57 more Poly Haven models (street lamps, trash can, air-con unit, power box, security camera, tyre, crates, propane tank, generator, ladder, toolbox, bench, cafe set, coffee cart, concrete cat statue, televisions, tables, chairs, desks, shelves, bed, lamps, frames, mirror, vases, jug, bottles, bowl, pot, microwave, kettle, rubber duck, boombox, bust, grandfather clock) | Street dressing and interiors, all breakable (`assets/models/props/`) | https://polyhaven.com/models | various (Poly Haven) | CC0 | optional |
| Generic passenger car pack (GLB 2k) | Parked and driving cars (`assets/models/vehicles/passenger_cars.glb`) | https://sketchfab.com/3d-models/generic-passenger-car-pack-20f9af9b8a404d5cb022ac6fe87f21f5 | Comrade1280 | CC BY 4.0 | "Generic passenger car pack" by Comrade1280 (Sketchfab), CC BY 4.0 |
| Generic civil service vehicles pack (GLB 2k) | Police, taxi, ambulance, fire truck, buses, garbage and tow trucks (`assets/models/vehicles/service_vehicles.glb`) | https://sketchfab.com/3d-models/generic-civil-service-vehicles-pack-8ff2a13f30914932a70c7950cfa58465 | Comrade1280 | CC BY 4.0 | "Generic civil service vehicles pack" by Comrade1280 (Sketchfab), CC BY 4.0 |
| Fonts: Nunito, Fredoka, JetBrains Mono (variable TTF) | UI text, titles, the Owner's code (`assets/fonts/`) | https://github.com/google/fonts (ofl/nunito, ofl/fredoka, ofl/jetbrainsmono) | The Nunito / Fredoka / JetBrains Mono Project Authors | SIL OFL 1.1 (licence texts in `assets/fonts/OFL-*.txt`, must ship with the game) | licence files |
| Music: Local Forecast - Elevator, Lobby Time, Bossa Antigua, Hep Cats, Sneaky Snitch, Volatile Reaction (MP3) | Lounge soundtrack (`assets/audio/music/`) | https://incompetech.com | Kevin MacLeod | CC BY 4.0 | "<Title>" Kevin MacLeod (incompetech.com), Licensed under Creative Commons: By Attribution 4.0 License, http://creativecommons.org/licenses/by/4.0/ |

Sonniss GDC 2026 bundle: extracted to `_downloads/_staging/sonniss/` (347 files, 122 libraries; index in
`_downloads/sonniss_index.csv`). Only the files copied into `assets/audio/sfx/` ship with the game.

Sound bank on 2026-11-16: `assets/audio/sfx/<kind>/` holds 114 files, all CC0: Freesound files (the id
and author are in each file name; full list in `_downloads/freesound/manifest.csv`), Kenney "Impact Sounds" and
Kerzoven's "Cat Purr & Meow". No Sonniss file is in the bank yet. Per-file gains: `game/audio/bank_gains.json`.

In use on 2026-11-16 (nothing new was downloaded for this step): the 10 EZ-Tree species (scaled to about a
tenth of their authored size), 16 Poly Haven props as street dressing (see `DEFS` in
`game/world/props/street_dressing.gd`), 9 cars of the passenger pack and all 10 service vehicles as parked cars.
The coupe of the passenger pack is left out (modelled in a pose that is 3.7 m wide).

In use on 2026-11-17 (nothing new was downloaded): 66 Poly Haven prop kinds (street set, market and cafe
tables with fragile things on them, furniture, yard machines; see `DEFS` in
`game/world/props/street_dressing.gd`), the Quaternius mannequin with both Universal Animation Libraries as
the porcelain people (`game/npc/people.gd`), the pigeon (standing clip only; its wings in flight are two
flat cards made in code) and the Shiba with its five clips (`game/npc/animals.gd`). The domino tiles and
their faces are generated in code (`game/world/props/domino_run.gd`). Still unused: the Universal Base
Characters bodies, the hanging lamp, the fern and the covered car.

Facades on 2026-11-17 (nothing new was downloaded): ambientCG Tiles141 is now also the stone cladding of
ground floors and stone towers, PavingStones142 the walls of fieldstone cottages, Plaster001 the coloured
render, PaintedMetal004 the shop sign bands. Windows, shop windows, doors, awnings, railings, the deck band
and the parking sign are drawn in code (`game/destruction/facade_textures.gd`), no third-party files.

Sounds still missing (nothing in the bank fits): a trickle for the pee, a dog bark, a domino clack (it
borrows the wood impact), a car alarm.

## TODO before release

- Generate the credits screen and `THIRD_PARTY_NOTICES.txt` (MIT notices: Godot, Voxel Tools, Jolt) from this file.
