# Cat As Trophe — design decisions (binding for the MVP)

Decided by the lead on 2026-11-13 under the director's standing instruction: "decide everything yourself,
the most logical choice that is enough for the MVP; coherence and consistency must be AAA, realism is optional."

## 1. Story: "Nothing Is Off the Table"

**Tagline:** NOTHING IS OFF THE TABLE.
**Logline:** A hairless Sphynx discovers her perfect little world is a simulation floating in the void like one
giant table, and while its frantic caretaker AI begs "Trophe, don't you dare", she does what every cat does to
everything on a table.

- **The Table.** A perfect little city on a flat slab floating in an endless void, kept spotless by **the Owner**:
  a gentle, lonely caretaker AI that built it as a home. It cat-proofed everything it loved (every tree, flower,
  bird, dog), then added the one thing a home needs: a cat. A hairless one, because hairless cats don't shed.
- **Trophe** never speaks, never hurries, holds eye contact while doing crimes. Pronoun in text: "she".
- **Inciting moment (intro):** Trophe nudges a glass off the kitchen table; it does not stop at the floor; it falls
  through into code. The world is fake, flat, has edges: it is a table. Everything on it is going over the edge.
- **Why nature and animals are safe:** the Owner cat-proofed what it loved. Hits on them make a soft "boing",
  a small paw-padlock icon and the word CAT-PROOF. Pigeons know it and are smug about it.
- **Why the cat cannot die:** the Owner would never allow it ("// nobody gets hurt on my table" in the code).
- **Humans = the Owner's "little people":** smooth, faceless, glossy porcelain mannequins placed so the city
  feels lived-in. They loop small routines and mumble "Nice kitty?". Hit hard, they ragdoll and shatter into
  porcelain shards with an ornament-like tinkle. Never gore.
- **The Owner escalates** as destruction rises, and every trick backfires into one of Trophe's powers
  (see section 3). Its lines appear as soft subtitles from the sky ("Trophe. Look at me. Don't.").
- **Edge of the world:** the city stops like a dollhouse cut; roads trail into scrolling code; the slab's side
  shows the strata like a slice of cake (soil, clay, sand, rock, magma).
- **The Underneath (void):** falling off the edge or through the bottom drops Trophe through an endless dark where
  everything she ever knocked off drifts (a growing "junk galaxy" trophy shelf). Then she falls from the sky onto
  a random spot of the Table, feet first. Owner: "...Of course you did."
- **Ending:** TABLE CLEARED 100%: only the cat-proofed things remain, a garden floating in code.
  Owner, quietly: "...Oh. It's actually lovely." One thing is still on the table: the camera. Trophe walks up to the
  lens, slow-blinks, pushes. TABLE CLEARED: 101%. Credits over the junk galaxy. Free play continues afterwards.
- **Title gag:** the line of code that spawned her, `TROPHE AS CAT`, sits on a ledge as fridge-magnet letters; a
  wrinkled paw nudges them off and they land glitching as `CAT AS TROPHE`.

## 2. Art direction: "the Owner's perfect home"

Not photoreal; **coherent, clean, warm, premium**. One rule set for every asset:

- **Light:** warm golden-hour key light by default, soft blue sky fill, gentle aerial haze (not grey fog), strong
  ambient occlusion, bloom on emissives. A day/night cycle is post-MVP; MVP ships golden hour + an optional dusk.
- **Materials:** clean PBR from ambientCG, slightly saturated and warm through one colour grade. The city must look
  *spotless* at first (the Owner keeps it clean) so that dust, rubble and craters read strongly.
- **Architecture:** procedural, but never flat boxes: recessed windows with frames and sills, cornices and ledges,
  balconies, storefront ground floors with awnings and signs, rooftop clutter (AC units, water tanks, antennas).
  Every one of those parts is a destructible element.
- **Little people:** one glossy white porcelain material (slight subsurface, clear coat), no faces.
- **Nature:** lush, saturated, the most "loved" thing on screen (EZ-Tree trees, bushes, grass).
- **Simulation layer:** never green Matrix rain. The Owner's code is calm, readable monospace text (white/teal) in
  thin lines, plus clean wireframe; glitches are clean tears and offsets, not noise.
- **UI:** soft, rounded, friendly, pastel accents; the Owner's voice is the UI's personality.
- **Audio:** destruction is heavy and layered (Sonniss), music is calm lounge/elevator jazz that keeps playing while
  towers fall (the comedic contrast is part of the brand).

Assets that do not fit this look are not discarded: tag them in `docs/ASSET_LEDGER.md` with their style
(lowpoly, voxel, fantasy, ...) for a future table (section 5).

## 3. Progression (MVP)

- **TABLE CLEARED %** = destroyed man-made mass / total man-made mass of the Table (terrain excluded). Shown top
  centre. Milestones trigger an Owner countermeasure that backfires into a new tool:

| Cleared | Owner tries... | Trophe gets |
|---|---|---|
| start | (nothing yet) | Paw swat, **Pee**, Grab and throw, Pounce, Climb, Dig (innate) |
| 0.2 % | a laser pointer to distract her | **Laser Dot**: heat beam that cuts and melts |
| 1 % | "Undo" (Ctrl+Z) to rebuild a block | **Rewind**: hold R to rewind the world |
| 3 % | a cute wizard-hat costume for a photo | **Wizard Hat**: fireballs |
| 8 % | a vacuum robot to clean the rubble | **Hairball Cannon**: heavy kinetic hairballs |
| 15 % | a spray bottle | **Acid Pee**: her pee turns to acid |
| post-MVP | yarn ball, lullaby, giant cardboard box, ... | Yarn tether, Purr-quake, Box, ... |

  The thresholds were set against the real city (2026-11-17): it weighs about 220,000 t, a house is 0.03 % of
  it, an apartment block 1 %, a tower 2 %. With the paw alone the first tool has to come after a handful of
  houses, so the first steps are small and the later ones wide. People, props and cars count too, but only
  buildings move the number much.

- **Sandbox switch** in the pause menu: all tools unlocked immediately (for players who only want chaos).
- **How the tools play (decided 2026-11-16, belt order changed 2026-11-17):** keys 1-5 (or Tab / mouse
  wheel) pick paw, Pee, Laser Dot, Wizard Hat, Hairball Cannon; rewind and slow motion are held keys (R, Q),
  not belt tools. Using any ranged tool makes Trophe rear up and face the crosshair. The game is played with
  keyboard and mouse together: the mouse aims and fires, the keyboard moves her and picks what she does.
  - *Laser Dot:* she finally caught the red dot, so now it is hers. A harmless dot follows the crosshair;
    holding fire turns it into a heat beam from her eyes. Precision tool: cut the columns and the building
    comes down by itself.
  - *Wizard Hat:* the hat sits between her ears while selected. Hold to gather fire between the paws, release
    to cast; a tap is a firebolt, a full second levels a house front.
  - *Hairball Cannon:* dense hairballs with real mass (the vacuum robot fed her every hair on the Table). Spent
    balls stay as light props she can pick up and throw.
  - *Pee, later Acid Pee (2026-11-17; it replaces Acid Spit, the director wanted the vomit gone):* hold
    fire and she stands bolt upright on her hind legs like a person, front paws down, and a yellow arc lands
    where the crosshair points (about 17 m of reach). She has it from the first second. Plain pee harms
    nothing: it leaves puddles, walks a vase off its table, and whoever it lands on shouts ("Not the
    shoes!") and runs. Trees and animals do not mind it, so the CAT-PROOF shield stays quiet. At 15 % the
    Owner reaches for the spray bottle and the pee turns green: every drop leaves a pool that keeps eating
    for a few seconds and follows the surface down, so walls get holes and the ground gets shafts.
- **Decided 2026-11-17 (moments worth a clip).**
  - *The chain.* Things broken in quick succession (2.4 s apart at most) count up beside the crosshair:
    props, cars (a wreck counts two), people, toppled dominoes, every eight building elements, a toppled
    building five. Ranks: x8 NAUGHTY, x20 BAD KITTY, x45 CAT-ASTROPHE, x90 TROPHE-POCALYPSE, x150 TABLE FLIP.
    The domino run at the landing spot is long enough that the first chain of the game shows the title.
  - *Slow motion* on Q (held): the world at a quarter speed, the sound pitched down. The mouse still aims at
    full speed.
  - *Meow* (M) frightens: people within 9 m run, pigeons within 16 m go up, a dog within 10 m rolls over.
- No timers, no fail state, no health. Records: biggest single collapse, longest chain, highest fall.
- **Decided 2026-11-17 (Rewind).** Hold R (from the 1 % milestone, or in the sandbox) and the Table runs
  backwards; let go and time runs forward from there. Up to 15 seconds back, at 1.6 seconds of history per
  second of holding after a short run-up. The world almost stands still while it rewinds (5 % speed),
  the camera still turns, so the player can watch from anywhere.
  - Debris flies back: in the last 1.1 s before the moment a piece was born it glides back to where it
    was born (fracture cells into their wall, falling blocks into their storey) and is gone when the
    rewind passes that moment; the elements of the building come back, newest first. A collapse plays in
    reverse and the building stands as it stood. The domino run stands up again tile by tile.
  - Broken props come back whole where they broke and are carried back along the path they flew; burnt
    cars lose their soot and get their fuel back; shattered mannequins are whole again; heads that rolled
    are gone. TABLE CLEARED % goes down with all of it; unlocked tools stay unlocked.
  - The ground keeps its craters, fires and scorch marks fade on their own, and Trophe stays where she is:
    she is the one who remembers.
  - A rewind that does not reach back to the first blow of a collapse leaves that blow standing, and what
    stood on it comes down again.
  - Look: the picture cools and loses colour, scan lines and a slow tracking band roll over it with a
    slight colour split, "<< REWIND -3.4 s" and a bar in the Owner's teal; the sound is a tape-rewind
    warble. After the first rewind the Owner protests: "Ctrl+Z. Ctrl+Z. ...Trophe, that is MY shortcut."
- **Decided 2026-11-17 (the frame around play).**
  - *Loading:* the screen comes up at once on the colour of the boot splash: the wrong name, TROPHE AS CAT,
    a thin teal bar, the stage being built in the Owner's monospace, the Owner fussing ("Hiding the
    vases. Higher.") and a tip. The world is built over many frames behind it, so it never freezes.
  - *Title:* the camera flies slowly round the city at golden hour; TROPHE AS CAT tears in horizontal
    slices with a teal ghost and settles as CAT AS TROPHE, then "Nothing is off the table." and the menu:
    Continue (the newest save, with its TABLE CLEARED %), New Table, Load, Settings, Quit.
  - *Intro:* Trophe drops from the sky while the Owner greets her ("Good morning, Trophe. The Table is
    spotless. ... I have one rule today: nothing falls off the Table.") and, as she sees them, asks her
    not to touch the dominoes. Telling the player not to touch something is the invitation.
  - *The Owner's voice* in play: one line per moment and per game (the first wall, the first shattered
    mannequin, the dominoes all down, a toppled building, a burning car, the trees that will not break, the
    first pee, slow motion, a meow, a long quiet), a line for every rank of a chain, and the milestone
    lines; never more than one every twelve seconds of its own choosing. Text only for now, no voice.
  - *Pause (Esc):* resume, save into slot 1-3, load (the autosave or a slot), settings, quit to the title,
    quit to the desktop. The world stops; the music does not.
  - *Settings:* mouse sensitivity, master, music and effects volume, graphics preset (low, medium, high),
    full screen, and the sandbox switch (every tool from the start). Saved at once in user://settings.cfg.
  - *Saves:* an autosave every two minutes of play, on quitting and when the window is closed, and three
    slots. A save keeps what changed: the elements gone from every building, the props that are gone and
    the cars that are wrecks, the fallen dominoes where they lie, the shattered people, the dug terrain,
    where Trophe was, the unlocked tools and the best chain. Loading builds a fresh Table and takes those
    things out again without debris, fire or sound: the rubble of a saved game is gone (the Owner's vacuum
    robot took it). The Table is the same every time, so this is exact; a save from a different build of
    the city keeps its progress but not its world.

## 4. World (MVP)

- One Table: the 1024 x 1024 m slab (terrain module). The MVP builds the central ~640 x 640 m as four districts
  on the road grid, plus the hills and the edge:
  1. **Downtown**: glass/concrete towers, plazas.
  2. **Old Quarter**: brick apartments, shops with awnings, houses.
  3. **Works**: parking garages, warehouses, industrial props, a construction site.
  4. **The Park**: lawns, many trees and bushes, a pond (cat-proofed nature, pigeons, dogs).
- Street dressing from Poly Haven props (barriers, payphones, benches, planters, covered cars), all destructible.
- **Decided 2026-11-16 (nature, props, cars):**
  - *The clod rule.* A tree owns a clod of earth that the Owner pinned to the Table. Dig or blast the ground
    away and the tree stays exactly where it was, standing on its clod. Follow it to the end: a cleared Table is
    a void with trees (and animals) hanging in it. That picture is the game's last frame.
  - *CAT-PROOF answer.* A teal hexagon ripple at the hit point and the word CAT-PROOF in the Owner's monospace
    type, plus the boing. At most one answer per target every 0.6 s. (The paw-padlock icon is still to come.)
  - *Bushes* have no collision: the cat walks through them and can hide in them.
  - *Props* are rigid bodies. Light ones can be pushed, grabbed and thrown; lamp posts, long seating and statues
    are bolted down until a hard hit frees them. A prop that runs out of hit points breaks into debris of its
    material; a thrown prop is hurt by its own crash. Gas bottles, fuel drums and generators explode.
  - *Vehicles die twice.* First the fuel goes off: the car is thrown, charred and left burning; the blast
    reaches the next car in a parked row, so a row goes up one car after the other. The wreck is still a prop
    and breaks into steel when it is destroyed again.
  - *Cat statues* stand on the corners of the central crossing: the Owner likes her that much.
- **Decided 2026-11-17 (city layout).** The city is the 4 x 4 blocks around the central crossing, inside the
  ring road at 256 m (about 540 x 540 m; the blocks beyond it stay lawn up to the hills). The four districts
  are the four quadrants and meet at the crossing where Trophe lands, so every direction she can look in is a
  different district: Downtown (+x, +z: eight lots around a plaza in each block, three of four are towers),
  Old Quarter (-x, -z: blocks of apartment rows with houses behind them alternate with blocks of house rows
  around a green), Works (+x, -z: six plots per block with parking decks, brick sheds and open yards) and
  the Park (-x, +z: no buildings, three groves per block around open lawn). 157 buildings, not the 250 first
  planned: 104 m blocks do not hold more at a believable density, and the count is about what one sees and
  can knock down, not a target. Every street has its avenue of one tree species, what stands on a sidewalk
  depends on the district (coffee carts and seating downtown, benches and bins in the old quarter, fuel drums
  and crates at the works, benches in the park), and fewer cars park at the works and the park.
- **Decided 2026-11-16 (city scale): the reach rule.** The Table only reacts within 150 m of Trophe
  (`DamageRouter.REACH`). The terrain has collision for about 160 m around her, so anything broken farther
  away would fall through the world. Hits and blasts beyond the reach are seen and heard but change nothing,
  and the tools stay inside it: the laser reaches 140 m, a fireball bursts in the air after about 140 m, a
  hairball puffs away at 150 m. Buildings she is not near are dormant (one box instead of a body per element)
  and wake when she comes within 80 m or when something inside the reach damages them. Loose debris that
  falls below the Table is removed.
- **Decided 2026-11-17 (people).** The little people are glazed porcelain mannequins in five colours. They
  walk the sidewalk around their block (more of them downtown, few in the park), sit on a quarter of the
  benches and stand at the stalls and tables of the composed places. When Trophe comes close one says
  something ("Nice kitty?"); a blast, a meow or a neighbour breaking makes them run. A hit of 600 J or more
  shatters one into shards, and the head rolls away. Only the ones near her are simulated (44 at most).
- **Decided 2026-11-17 (places).** The open spots of the layout are furnished: a flea market in every
  apartment court (long tables full of vases, clocks, bottles and televisions), a cafe terrace on every
  downtown plaza, a green with a statue, benches and a dog in the blocks of house rows, yards with crates
  and machines at the works, one of them a fuel depot (28 drums, 8 gas bottles: one spark takes the yard),
  a chair and a stool with something on it beside many houses, picnic tables in the park. Two lots became
  open places, so the city has 155 buildings. Small things on tables are fragile: a swat sends a vase
  flying instead of breaking it on the spot, and it breaks where it lands.
- **Decided 2026-11-17 (the opening).** Trophe lands on the central crossing looking down the avenue
  between the Park and Downtown, pigeons go up around her, and in front of her stand the Owner's dominoes:
  44 ivory tiles, 2.2 m tall, in a long S down the middle of the road. One swat and the run goes over in
  about ten seconds; the last tile lands on a stack of fuel drums in front of a garbage truck, and the
  cars at the curb go up with it. The first minute holds a chain reaction that one paw can start, and it
  teaches the chain counter, the fuel rule and the car rule without a word. A falling tile also flattens
  whatever stands where it lands, people included.
- **Decided 2026-11-17 (ground).** Each district has its own ground: paving stones under Downtown and
  in the market courts of the Old Quarter, asphalt in the blocks of the Works, lawn in the Old Quarter and
  the Park. Paved paths wind through every park block between the groves (in from the west, out to the
  north past the picnic spot, a branch to the south), with benches and a bin beside them. Only the surface
  and the top stratum change; the ground is as high as before, and paving and asphalt are harder to dig
  through than lawn.
- **Decided 2026-11-17 (animals).** Pigeons stand in flocks on the plazas, courts, greens and lawns (17
  flocks, about 130 birds). Come close, set something off, meow or aim at one, and the flock goes up,
  circles over its square and lands again once she is 13 m away. A Shiba sits at every picnic spot and on
  every green: it gets up and watches her when she is near, plays dead when something explodes, rolls
  over at a meow and shakes itself after a swat. All of them are CAT-PROOF and answer with the shield.
- **Decided 2026-11-17 (facades).** Every building design draws a look from its seed; the structure of the
  design (storeys, bays, partitions) stays as it was and only the surfaces and the facade parts change.
  - *Towers* come in six looks: blue, teal, bronze and silver glass with aluminium, white, champagne or
    graphite mullions and spandrel panels, and two stone looks whose deep stone piers and tall spandrels make
    the windows read as punched openings. On the top floor the spandrels rise 1.3 m past the roof as a
    crown band. The two middle modules of the ground floor on one side are glass doors under a canopy;
    the roof carries air-con units, a water tank and a mast on the penthouse.
  - *Apartment blocks* have nine looks: brick, old brick, dark brick or coloured render (cream, sage,
    terracotta, sky, ochre, rose) over a ground floor clad in square stone, white or cream trim, a cornice
    round the roof line and a stone ledge under every window. Four in five have shops along the ground
    floor of their front: a tall shop window full of goods with the light on, the shop's colour as a sign
    band above it and a striped awning; a new shop every two bays, five shop colours. Every other bay of
    the back has a balcony from the first floor up (glass door, slab, wrought railing). In the Old Quarter
    the front always faces the street.
  - *Windows* are drawn with frames (white, green, brown or black), muntins and glass that reflects the
    sky; one in five has curtains, one in seven blinds, one in ten a warm light on behind the curtains.
  - *Houses* keep what they are made of: plaster houses wear a pastel coat (cream, sage, rose, sky,
    ochre), brick ones stay red or dark brick, old brick ones are sometimes fieldstone cottages. Panelled
    double doors in six colours, red, slate or brown roofs, ledges under the windows, and seven in ten have
    a brick chimney stack against the east gable, a metre over the ridge.
  - *Parking decks* have a painted band along their railings (red, blue, yellow, green or plain) and a
    blue parking sign on the top deck.
  - Every one of these parts is an element of the building: it breaks, burns and falls like the rest, and
    the glass rules hold for every kind of glass (a window, a shop window, a glass door shatters at a
    touch). None of them carries anything, and none overlaps another element, so nothing is left floating
    when its wall is gone.
- **Decided 2026-11-17 (the edge and the Underneath).** The Table is a slab of 1024 x 1024 m and its end
  is shown, not hidden.
  - *The rim:* in the last 28 m before the edge the ground turns into the Owner's model, a clean teal
    wireframe on a dark ground, with a bright line along the very edge. From the city the crest of the
    hills at the edge reads as a glowing line: the end of something made.
  - *The curtain:* over the rim hangs a quiet curtain of the Owner's code (calm white and teal monospace,
    real lines of the Owner's world: "assert(nothing.falls_off(table))", "vacuum.collect(rubble)") on a
    faint grid. It rises only a little above the hills, so from the streets it is a soft glow on the
    horizon, and from above it fills the band below the horizon that used to be black. It hangs down past
    the cut side of the slab far into the void. Never green rain.
  - *The cut side* of the slab shows its strata under a faint grid, the underside its glowing cracks (the
    terrain already drew both), and far below a grid floor that is never reached gives the void depth.
  - *Falling off:* Trophe goes over the rim and drifts away from the slab at a calm, capped speed while the
    camera turns back to it: the cut side with the code drifting over it, then the glowing underside as
    she sinks below it, with streaks of light rushing past. The Owner says "Please do not fall off the
    Table." and, a moment later, "...Again." (later falls get other lines). After five seconds, or at any
    key or click from the first second on, a soft flash, and she drops back onto the Table from the sky at
    a random spot. A game saved while she falls keeps her at the crossing.
- **Decided 2026-11-17 (the name).** The game is **Cat As Trophe**: CAT-AS-TROPHE reads "catastrophe" spelled
  right (the old "Cat As Rophe" dropped the t). The cat is Trophe; the line of code that spawned her is
  `TROPHE AS CAT` and the title gag glitches it into `CAT AS TROPHE`. The rank names follow
  ("TROPHE-POCALYPSE"). The project folder keeps its old name.
- **Decided 2026-11-17 (a city of normal size, with different parts).** The city grows from 4 x 4 to 6 x 6 blocks
  (768 m across, ring roads at 256 m and 384 m) and every quarter goes on into an outer ring of its own:
  - *The Strip* (beyond Downtown): malls behind car parks with painted bays (the terrain paints them, so a
    crater keeps its paint), a paved front with benches, planters and a coffee cart; fuel stations: a canopy in
    the brand's colours, four pumps on islands (every pump is fuel: one goes up and the next follows, and the
    canopy comes down), cars at the pumps, gas bottles by the shop, a price pylon; rows of shops.
  - *The Yards* (beyond the Works): corrugated warehouses in five colours with roller doors facing a loading
    yard of trucks, piles and a line of fuel drums at one end; plots of shipping containers stacked one to three
    high (2.3 t boxes to climb, push off and blow up).
  - *Suburbs* (beyond the Old Quarter): detached houses facing the streets, a white picket fence in front with
    the path and the drive cut through it, a car in the drive, a back garden, a lawn with trees down the middle.
  - *The outer Park* (beyond the Park): more park, with deer at the edge of its groves and the petting farm.
- **Decided 2026-11-17 (a living city: real people, real animals, traffic).**
  - *People* stay the Owner's porcelain, but they are no longer blank mannequins: they are painted porcelain
    figurines of real people in real clothes (Quaternius' modular men and women under a glaze), cast per
    district: suits downtown, overalls in the works and the yards, beachwear and hiking clothes in the park,
    casual and hoodies everywhere; four glaze variants each (skin tone, hair, clothes colours). One in thirty
    is something odd from the Owner's toy box (a king, a witch, an astronaut). They walk, idle, fiddle, sit on
    benches (a sitting pose is made from their idle), wave at Trophe and say "Nice kitty?", and the rude ones
    (punks, hoodies, soldiers) kick at her instead ("Scram!"), which never connects. Hit hard they still shatter
    into porcelain; the head that rolls away wears the skin of the figure.
  - *Animals* (all CAT-PROOF): deer and stags at the edge of the groves of the outer Park and in herds on the
    hills, a fox in every park, a wolf pack far out on the hills, the paddock of a petting farm (horses, cows, a
    bull, donkeys, alpacas) behind a white fence, huskies and shibas in the back gardens of the Suburbs. They
    graze, idle and wander; Trophe, a blast or a swat sends the wild ones galloping off and the farm animals to
    the far side of the paddock; the dogs come running at her and bark.
  - *Traffic*: 110 cars drive the roads on the right-hand lane, keep their distance, wait their turn at a
    crossing (one car in a crossing at a time) and turn there along a curve; they brake for Trophe, people,
    rubble and wrecks and honk when they are stuck, and a car that cannot stop breaks a person in its way. A
    driving car is a puppet until something hits it: then it becomes an ordinary car prop with the speed it
    had (it crashes, burns, breaks) and a new car comes in out of sight. Trophe can ride on a car's roof. The
    domino run's stretch of road is closed to traffic.
- **Decided 2026-11-17 (chaos stars, the Owner's wanted level).** Everything man-made Trophe breaks gives
  heat (every break of a chain), more for a shattered person (6), an explosion (2.5), a toppled building (30)
  and a wrecked unit of the Owner's response (12). Heat makes one to five stars at the top right (gold; they
  blink while they cool down). Once she has been quiet for 10 s the heat falls, but not while a unit or one of
  its people can see her (50 m / 40 m): to lose the stars she has to get away. The Owner remarks on each new
  star once per game ("One star. I am writing that down, Trophe." ... "Five stars. SWAT. I did not want it to
  come to this.") and on the calm ("...And we are calm again. Good kitty.").
  - *The response:* a police car per star (they come in 110 to 190 m away, out of sight), the fire brigade
    at four stars, a SWAT van (a dark van) at five. Units run with flashing lights (red and blue, red and
    white on the fire engine) and a wailing siren, drive the road grid at her (at every crossing the way
    nearest to her; they go through crossings first and the traffic ahead of them pulls over to the curb),
    stop across their lane near her (by the nearest point of the road when she is inside a block) and let out
    their people: officers who walk up to her, point at her ("Freeze, kitty!", "Paws where I can see them!")
    and, the rude ones, swing at her (it never connects); firefighters who shout. From three stars a police
    car also puts three barriers across the road ahead of it. If she gets away, the parked units follow her
    again after 6 s; their people stay behind.
  - Everything is breakable: a unit that is hit becomes a car prop, an officer shatters like anyone; both
    add heat. When the stars are gone the units drive off as ordinary traffic and leave the roads out of
    sight, and their people go home once she is away from them. A rewind sends everyone home at once and
    calms the stars. Stars and units are not saved.
- **Decided 2026-11-17 (the Owner's vacuum robots).** Six seconds after a building comes down, or when a chain
  of at least 18 ends with rubble about, two or three round vacuum robots (white, a teal light, little brushes)
  roll out of the door of the nearest standing building, at most four at a time and not more often than every
  20 s. Each works the pile from its edge: it drives to the nearest piece it can get at, sucks it up with a
  puff and a fwump (and the little pieces right next to it), gives up on a piece it cannot reach for a few
  seconds and tries again later, and rolls home when it has 40 pieces or the mess is gone. They are ordinary
  breakable props: Trophe can push them, ride them and swat them over (they right themselves after a moment);
  a robot that finds her in its way stops and beeps. Two or three swats break one: a little battery pop, the
  Owner is sad ("That robot had a name. It was Dusty.") and it adds 8 heat. They go back in their cupboard
  when she is far away.
  - *DO NOT TOUCH:* at three chaos stars the Owner tapes off the worst ruin within 140 m of her (posts every
    4 m or so, yellow tape with the words on it at hip height; at most three ruins; "Do not touch. I mean
    it."). Tape and posts are props: one swipe and the tape is down.
  - A rewind sends the robots home and takes the tape down; neither is saved.
  - A blast in the crater of an earlier one no longer leaves a ring of earth standing in the air: the ejecta
    lip is only laid on level ground.
- **Decided 2026-11-17 (the giants of the districts).** Three set pieces in the spirit of the dominoes, each
  set off by one act (six or so swats at its stand, or one car going up next to it):
  - *The fair* (outer Park): a Ferris wheel (26 m, white rim with bulbs, twelve coloured gondolas) on two
    A-frames. It comes off its axle and rolls east, over the road and through the car park of the Strip into
    the mall; it breaks up when it falls on its side. (Decided instead of the fountain: water does not fit
    the destruction tech yet.)
  - *The building site* (the Yards): a yellow lattice tower crane (40 m, 45 m jib, counterweights, hook) by
    the first container plot. It falls like a felled tree, away from the hit, turning round the edge of its
    base, and breaks into its sections where it comes down (on the warehouses, the containers).
  - *The square* (Old Quarter): a stone clock tower (42 m, a clock face on each side) in the middle of the
    first village green, in place of its cat statue. It topples onto the houses round the green and breaks
    into its stones.
  - Each crushes whatever it runs into or lands on (the energy of the contact), the Owner has a line for each
    ("That wheel was a gift. ...Why is it rolling? WHY IS IT ROLLING?"), and each adds 20 heat. A rewind to
    before the act puts it back; a saved game does not keep it fallen (the Owner rebuilt it).
- **Decided 2026-11-17 (inside).** The ground floors are furnished, so a building that comes open spills its
  insides: a living room in every house (a sofa or an armchair with a low table, a dining table with chairs
  and vases, a cabinet with a TV, a plant or a grandfather clock), shelves with boxes and a counter in every
  shop, shelves in every other bay of a mall and a coffee counter by its doors. They are drawn only within
  45 m and cast no shadow (they are behind walls). Upper floors and offices stay empty for now.
- **Decided 2026-11-17 (controls after the first play test).** Space jumps the moment it is pressed (held
  longer, higher; a tap is a hop); a pounce is charged crouching (Ctrl + Space, released to leap); a jump
  pressed during a landing waits and goes off as soon as it can; landings are a short stumble, never a stop;
  at a gallop she turns and speeds up much quicker; a throw with the crosshair on the ground right in front
  goes forward in an arc.
- Interiors: ground floors and a share of upper floors get furniture props (tables with vases on them: the
  first thing every player will push off).

## 5. Biomes and other worlds (post-MVP plan)

More biomes = more **tables** floating in the void, each a complete world with its own art style (for example a
pixel/voxel table, a toy/low-poly table, a fantasy table, a realistic table). The Underneath connects them:
gates appear in the void after a table is cleared. This keeps every table internally coherent, uses assets that
do not fit the first table, and needs no change to the core systems. **The MVP ships one table.**

## 6. Systems summary (MVP)

Destruction (done), terrain (done), cat controller (done), tools above, world rewind, mannequins + animals,
title/intro, HUD + Owner lines, edge + Underneath + re-drop, audio (SFX + music), save/load (autosave + 3 slots),
pause/settings (mouse sensitivity, volumes, graphics preset), 60 fps on the target machine.

## 7a. The city films you (decided 2026-11-17)

The little people do not only run. From a safe distance a third of the witnesses take out their phones and
film the chaos ("This is going viral.", "Like and subscribe!"); every phone adds views, the HUD counts them
under the stars, and each milestone (10K, 100K, 1M, 10M, 100M) gets a flash and a line from the Owner ("A
million views. You are trending, Trophe. I hate it."). Some call the police instead (one star of heat if
the call gets through; Trophe can stop it by going for the caller), and the rude ones near her chase her and
kick her away (a short flight; she cannot be hurt). It is the game's own joke about why it goes viral, and a
long-term number to chase that is saved with the jobs.

## 7c. Reasons to come back (decided 2026-11-17)

- **Fourteen jobs** from the cats under the Table; the four new ones use the city's reactions: GO VIRAL
  (50,000 views), OFFICE SPACE (break 25 things inside), WANTED POSTER (get reported three times), STREET
  FIGHT (make three humans angry enough to kick you). Jobs the city cannot offer (the demo has no fuel
  station, no crane yard, no furniture inside) are skipped.
- **The catnip shop** (pause menu): what the jobs pay buys boosts (higher jumps, a faster gallop, a meow that
  carries twice as far, twice the views, half the heat from police calls) and the tools before their
  milestone (wizard hat, hairball cannon, acid pee). Bought things are saved with the game.
- **Eighteen achievements** (pause menu, and a gold toast when one is earned) that count across every game:
  first crack, a hundred fragile things, porcelain people, buildings, five stars, a million views, cars,
  kilometres driven, every giant, every yarn, every job, a tenth of the Table, a chain of fifty, things
  inside, kicks, police reports, catnip earned, the first purchase. Kept outside the save slots: once
  earned, always earned.

## 7b. Builds (decided 2026-11-17)

itch.io gets two things: the full game as a Windows download (size does not matter) and a browser demo. The
demo is a taste of the city that runs in a browser on an ordinary laptop: the four blocks round the crossing
(one each of Downtown, the Old Quarter, the Works and the Park), fewer people and cars, smaller textures,
nothing inside the buildings, and a ground that cannot be dug (the voxel library has no browser build); the
jobs it cannot offer (the fuel station, the crane) are skipped. A banner on its title says so and points to
the download.

## 7. Languages (decided 2026-11-17)

English and Turkish, both complete: menus, loading lines and tips, HUD, the Owner, the little people, the
cats' jobs, the opening's subtitles, the driving prompts. The game starts in the language of the computer
(Turkish on a Turkish Windows, English everywhere else) and Settings > Language switches it at once; the
choice is saved. The Turkish is a localisation, not a word-for-word copy: the cats under the Table get Turkish
names (Bayan Çakıl, Tek Göz Tom, Kır Dede...), a cat has seven lives in Turkish ("Yedi canım gibi"), URBAN
RENEWAL becomes KENTSEL DÖNÜŞÜM, CAT-PROOF becomes KEDİ GEÇİRMEZ (like "su geçirmez"), the chain title
CAT-ASTROPHE becomes KAT-ASTROF (the same sound joke as in English). The game's title (TROPHE AS CAT -> CAT AS
TROPHE), Trophe's name and the code at the edge of the Table stay English in both, because they are the brand
and the gag. More languages later go through the same table (one `Lang<code>` file each).
