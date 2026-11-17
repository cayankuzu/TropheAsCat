# Trophe As Cat

**A bald cat. A perfect porcelain city. Nothing is off the table.**

On screen the name glitches: TROPHE AS CAT becomes **CAT AS TROPHE**. Read it again.

Trophe As Cat is a 3D chaos sandbox made with Godot 4.7. You are Trophe, a Sphynx cat dropped onto the
Owner's perfect Table: a whole city where everything man-made can be knocked over, shattered, toppled or
driven into a wall, while the trees and the animals stay CAT-PROOF. Dark humour, no gore: the little people
are painted porcelain.

**Play:** https://memode.itch.io/trophe-as-cat (browser demo and the full game for Windows)

Türkçe aşağıda.

## Features

- **A city that comes down for real:** 233 buildings (towers, apartment blocks, houses, shops, malls,
  warehouses, fuel stations) crack, sag and collapse piece by piece; over 5,000 breakable things in the streets
  and 3,700 inside the buildings; doors open, you can walk in anywhere on the ground floor.
- **A city that reacts:** 338 porcelain people walk, sit, film your chaos on their phones (every phone adds
  views), call the police and chase you; chaos stars bring police cars, roadblocks, the fire brigade and SWAT;
  the Owner sends cleanup robots.
- **Drive anything:** press F at a parked or passing car. 110 cars of traffic, a Ferris wheel that rolls away,
  a tower crane, a clock tower.
- **Jobs from the cats under the Table:** fourteen jobs, catnip to spend in the catnip shop (boosts and
  early tools), levels, thirty golden balls of yarn, eighteen achievements, viral milestones.
- **Toys:** paw, pee (and acid pee), laser dot, wizard hat (fireballs), hairball cannon, slow motion and a
  world rewind; the ground can be dug by blasts (desktop).
- **English and Turkish.**

## Controls

| Action | Key |
| --- | --- |
| Move / sprint | WASD / Shift |
| Jump (hold for higher) / pounce | Space / Ctrl + Space |
| Use tool / aim | Left mouse / right mouse |
| Tools | 1-5 or mouse wheel |
| Grab and throw | E |
| Get in / out of a car | F (drive with WASD, Space handbrake) |
| Slow motion / rewind | Q / hold R |
| Meow | M |
| Pause, save, settings, language | Esc |

## Run from source

1. Install Godot 4.7.2 (standard build).
2. Open `project.godot` and press F5. The diggable ground uses Voxel Tools (in `addons/`, Windows and Linux).
3. The ground's texture set `game/terrain/textures/strata_set.res` is stored with Git LFS (`git lfs pull`).

Builds: the export preset "Windows Desktop" is the full game; "Web" is the browser demo (Compatibility
renderer, a smaller city, a ground that is not dug). `python -I tools/package_builds.py` zips both for
itch.io. Tests are scenes in `tests/` (see `docs/ARCHITECTURE.md`, section 7). Design decisions:
`docs/DESIGN.md`.

## Credits and rights

Trophe As Cat © 2026 MeMoDe. The code, design and original content are published here for reference; they
are not open source. Third-party assets and software keep their own licences (CC0, CC BY 4.0, MIT, OFL): see
[CREDITS.md](CREDITS.md) and `docs/ASSET_LEDGER.md`. Made with the help of AI tools; the hero cat model is a
third-party model labelled "Generated with AI".

---

## Türkçe

**Kel bir kedi. Kusursuz porselen bir şehir. Masada olmayan hiçbir şey yok.**

Trophe As Cat, Godot 4.7 ile yapılmış 3D bir kaos oyunu. Sen Trophe'sun: Sahip'in kusursuz Masası'na
bırakılmış bir Sfenks kedisi. İnsan yapımı her şey devrilir, kırılır, yıkılır ya da araba ile duvara girer;
ağaçlar ve hayvanlar ise KEDİ GEÇİRMEZ. Kara mizah var, kan yok: küçük insanlar boyalı porselendir.

- 233 bina parça parça çatlar, çöker; sokaklarda 5.000'den fazla, binaların içinde 3.700 kırılabilir eşya.
- 338 porselen insan yürür, oturur, kaosunu telefonla çeker (her telefon izlenme getirir), polisi arar, peşine düşer.
- Kaos yıldızları: polis, barikat, itfaiye, özel harekât; Sahip'in temizlik robotları.
- F ile istediğin arabaya bin; dönme dolap, kule vinci, saat kulesi.
- Masanın altındaki kedilerden on dört iş, kedi otu dükkânı, seviyeler, otuz altın yumak, on sekiz başarım.
- Türkçe ve İngilizce.

**Oyna:** https://memode.itch.io/trophe-as-cat (tarayıcı demosu ve Windows için tam oyun)

Trophe As Cat © 2026 MeMoDe. Kod ve özgün içerik referans için yayımlanmıştır, açık kaynak değildir.
Üçüncü taraf içeriklerin lisansları [CREDITS.md](CREDITS.md) dosyasındadır.
