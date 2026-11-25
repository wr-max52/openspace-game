# Hyper3D prompts for the player, guard and cantina owner (issue #79)

Three whole-body costumes for the character kit, built the way the locals and
the issue #48 kit were (`content/look/character_models.json`, `local` and `kit`):

1. Generate each costume whole with Rodin Gen-2.5 (`rodin_generate`).
2. Rig it with the human template, turn it to the base body's rest pose, fit it
   onto the base body and cut it at the base body's head/torso/legs seams
   (`tools/look/fit_parts.gd`, `dress`). That keeps every outfit's cuts in the
   same place, so pieces mix.
3. Colour variants are texture recolours (`tools/look/recolor_fitted.gd`), not
   new generations, so each accent is one clean saturated hue.

What the prompts do for the split, since Rodin can't hand back labelled pieces
with a rig (BANG splits lose the rig, see DECISIONS.md):

- Ask for a hard visual break at the two seams the fitter cuts at: a collar ring
  at the base of the neck and a thick belt at the waist. The cut then lands on a
  material edge instead of through the middle of a jacket or a cape.
- Keep everything that belongs to one piece on that side of the seam: the guard's
  cape stops above the belt, the hat brim stays a head item.
- A-pose with space under the arms and between the legs, so arm and leg triangles
  don't fuse with the body (the issue's "arms and body are separate").
- Lead with silhouette and main colour, keep it short (round 2 of #25 showed long
  prompts drift to familiar archetypes). Each full prompt fits Rodin's 1024
  character limit.

Settings for all three: `tier` Gen-2.5-High, `mesh_mode` Raw, `quality_override`
60000 (the fitter decimates to 40–45k; the 500k defaults had to be cut down
before), `geometry_file_format` glb.

## Shared tail

Appended to every prompt:

> Full-body game character in a relaxed A-pose, arms angled down and away from
> the body with clear space under the arms, legs apart, empty gloved hands. Face
> fully covered, no skin showing. A distinct collar ring at the base of the neck
> and a thick belt at the waist give clean horizontal breaks between head, upper
> body and lower body. Gritty painterly realism, simple bold shapes, worn dusty
> finish, matte materials, no greebles, no text, no logos. Original design.
> Single character, centred, neutral background.

## 1. Player (`player`)

> A rugged, battle-worn space pilot. A worn dark brown-black leather jacket,
> open at the front, over a cream undershirt. Khaki cargo pants with side
> pockets, tucked into dark lace-up combat boots, black gloves, a dark leather
> belt. His face is fully covered by a dark cloth mask pulled up to the eyes,
> with bright glowing cyan round goggles. A dark hat with a modest brim that
> stays close to the head and a glowing cyan band around the crown; the head and
> hat are normal human scale.

Input: the concept's front and back views, cropped, plus this prompt. The
concept's colours win (owner's call), and the brim is kept modest so the head
piece fits on the guard's body.

## 2. Guard (`guard`)

> An interstellar marine in slim, close-fitting gunmetal grey armour plates over
> a dark undersuit, with armoured boots. Red accent paint on both shoulder pads
> and the upper chest plate. A matching gunmetal helmet covers the whole face,
> with one narrow horizontal eye slit glowing red and a short antenna on one
> side. A short ragged red cloth half-cape hangs from the shoulders down the back
> and ends above the belt. Dark utility belt with pouches.

Input: the concept's front and back views, cropped into two images, plus this
prompt. Concept and text agree, and the face is covered in both views.

## 3. Cantina owner (`cantina_owner`)

> A space-born adventurer woman. A rounded grey pilot helmet with ear cups and a
> short antenna, a full-face breathing mask with ribbed hoses curving down to the
> collar, and a wide ski-goggle visor in reflective yellow. A short mustard
> yellow tunic with a draped cowl hood around the shoulders, over a long-sleeved
> dark brown leather jacket; the tunic ends at the waist under the belt, nothing
> hangs below the belt. Brown leather pants, worn grey lace-up boots, grey
> gloves.

Input: the concept's front and back views, cropped, plus this prompt. The
concept's tunic is long and references tend to win over the prompt, so if it
still comes back long it gets trimmed at the belt in the fit step
(`trim_below`), keeping her legs mixable with anyone's.

## Decisions (owner, before generating)

1. **Player colours follow the concept**: dark leather jacket, cream undershirt,
   khaki pants. The concept views go in as references.
2. **Cantina owner's tunic ends at the belt**, so her legs mix with anyone's.
3. **All three characters** are in scope.
4. **The player's head must fit a guard's body**, so the hat brim is modest and
   the head is normal scale.

## Generations

| Piece | Generation | Rig (human template) | Source |
|---|---|---|---|
| player | d8edcd4d-c677-4a2d-a9d6-9bf95511e919 | 87225e2b-cd02-4690-8eea-7b1a0cf82873 | `player_full.glb` |
| guard | 6c15f9cd-8d84-4775-856f-638447246a19 | 2a576a9e-5b48-47d3-8f2e-2fbe975977f7 | `guard_full.glb` |
| cantina owner | ee1da12c-527b-4b87-be46-5ff9d73d57f8 | 2ca5dd83-1250-433d-b08f-e2c3e4750d87 | `cantina_owner_full.glb` |
| cantina owner legs | 593757f4-e787-45ab-b8ee-b0a139aebdd6 | (fitted, no rig) | `cantina_owner_legs.glb` |

Sources are in `assets/characters/kit/source/`.

**Guard: the first, de-lit run is the one used.** It came back white (texture
de-lighting bleached the gunmetal). A re-run without de-lighting
(acc0e2ef-a987-439f-b7a8-1d35db3d09c4) was gunmetal but too detailed for the game's
look, so the owner picked the simple white one. The fit bakes its white armour to
gunmetal grey (`recolor` in the kit's `dress.guard`).

**Player:** an earlier prompt-only run with the issue text's colours
(9412b9a3-0841-4bd0-ac01-6c479a7b2544) went out before decision 1 and is not used.

**Cantina owner's legs are their own piece.** Her tunic came back mid-thigh (the
references won over the prompt) and there is no body under it, so cutting at the
belt left a hole. The tunic hem goes to her upper body (`move` in `dress`, by
colour), front half only: the back of the hem is dropped (`drop_back`), so it hangs
like a tattered apron. Her legs are a separate generation fitted into the legs slot,
so they go under anyone's torso.

They took four tries. "Lower body only" came back on a bare mannequin torso with arms
(2cdc52de-0f37-43a1-aa91-849c8fe00d52), a looser retry had holsters and baggy legs
(7f432ad5-37de-4558-b932-ee42f0fb676e), and the tight leather pair the owner liked
(593757f4-e787-45ab-b8ee-b0a139aebdd6) stood mid-stride and turned, so it sat behind
the hips on every body. The one used (4faf8200-a481-4c44-8a07-68b0b1999d2c) is that
pair regenerated square, from front, side and back renders of it stood up straight,
with this prompt:

> The same pair of skin-tight dark brown leather trousers with lace-up leather combat
> boots as in the reference images, standing perfectly square and symmetric facing
> straight forward: both legs straight, vertical and parallel, side by side, feet
> level and pointing straight ahead, no stride, no turn. Empty trousers on their own
> with a plain waistband at the top; nothing above the waistband, no skin, no body.
> Keep the same leather, stitching, belt loops and boots. Gritty painterly realism,
> matte materials, no text. Single object, centred, neutral background.

The fit lines its waistband up with the hips (`align_top`) and trims the strip above
it (`trim_top`); it stands within 2 cm of the base body's legs at every height.

Raw review sheet: `docs/kit/79_raw.png` (`tools/look/sheets/19_issue79_raw.json`).

## Sand nomad heads (native packs)

The dune nomads' head: round goggles joined at the bridge to a nose-and-mouth
cover, over a full cloth face wrap. Three variations swap one feature in. Each is
a kit part `from` the head, fitted into the goggle head's box (`kit.fit.parts` in
`content/look/character_models.json`), so it goes on any body and shows in the
character builder.

**Re-rendered from prompts alone.** The first renders used crops of
`goggles_head` as references, and the references won over the prompts: four
hollow, holey copies of the brass goggle mask. These have no reference images.
Settings: Gen-2.5-High, Raw, `quality_override` 30000.

Pack head prompt (`nomad_head`):

> A single game character head piece: a desert wanderer's full face covering. A close wrap of thick coarse sand-coloured cloth covers the whole head, face, chin and neck like a hood, with layered folds and frayed edges. Over the eyes, big round goggles with dark smoky amber lenses in worn bone-coloured rims, joined at the bridge to a moulded nose-and-mouth cover: a short rounded snout of stiff pale bone-coloured hide with a ribbed breathing filter at the front, strapped onto the cloth. A tan leather strap runs from the goggles around the back of the head. Sun-faded sand, bone and tan tones.

Every head shares the opening ("A single game character head piece: a desert
wanderer's full face covering.") and this tail:

> No skin, no face, nothing human showing. One solid closed shape, no holes or gaps. Only the head and neck, cut off cleanly at the base of the neck, no shoulders, no body. Matte dusty materials, no metal shine, gritty painterly realism, no text. Single object, centred, facing straight forward, neutral background.

Variations (the middle of the prompt):

- `nomad_crest`: A close wrap of thick coarse dusty-tan cloth covers the whole head, face, chin and neck like a hood. A tall stiff ridge of wrapped cloth and bone beads runs over the top of the skull from brow to nape. Round goggles with dark amber lenses in bone rims, joined at the bridge to a short rounded nose-and-mouth cover of pale hide with a ribbed filter, strapped onto the cloth. Sand, tan and bone tones.
- `nomad_maw`: A close wrap of thick coarse sand-coloured cloth covers the whole head and neck like a hood, and a long ragged cloth veil hangs from the nose cover down over the chin and throat. Round goggles with opaque black smoked lenses, completely dark, nothing visible behind them, in bone rims, joined at the bridge to a long nose-and-mouth cover of pale hide, with two ribbed breathing tubes curving from it down into the veil. Sand, rust-brown and bone tones. No eyes, no skin, no face, nothing human showing anywhere.
- `nomad_horn`: A close wrap of thick coarse pale sand cloth covers the whole head, face, chin and neck like a hood. Two short curved bone horns sweep back from the temples through the cloth. Round goggles with dark amber lenses in bone rims, joined at the bridge to a short rounded nose-and-mouth cover of bone-coloured hide with a ribbed filter, tied on with leather cords. Sand, bone and faded brown tones.

The first `nomad_maw` (c15d179c-0ec4-4f47-909e-de0d3acfa81e) showed human eyes
and skin through amber lenses; its retry asks for opaque black lenses and "no
eyes".

| Piece | Generation | Source |
|---|---|---|
| nomad (pack head) | f92e8e0f-e312-47b0-b485-fb12d5691f16 | `nomad_head.glb` |
| nomad_crest | 720deca5-bdb6-4c9f-80c2-ef89beaaaf79 | `nomad_crest_head.glb` |
| nomad_maw | 61ef65ea-3181-4ce6-825e-63f347cb3657 | `nomad_maw_head.glb` |
| nomad_horn | 7a50e1ce-c347-46b7-9052-e03309a1c8f9 | `nomad_horn_head.glb` |

They came back a light beige and fully metallic. The fit bakes each to its own
sand (`recolor`, one swap, brightness kept, so the bone mask stays lighter than
the cloth; `metallic` 0). Textures are shrunk in the fit (`texture_size`: 1024 for
the pack head, 512 for the variations) to keep `parts.glb` under GitHub's 100 MB
file limit (about 95 MB).

**Colours are code, not renders.** Every head has the pack colours as texture
variants (`kit.part_colors`: `nomad`, `nomad_crest`, `nomad_maw`, `nomad_horn`,
each `sand`, `madder`, `slate`, `teal`), using the same target colours as the
cantina owner's tunic, so a head matches its tunic. Each pack style wears the head
in its tunic colour (`content/core/species/dune_nomads.json`). The party barge's
nomads (the `desert_nomad` look, no pack style) are `matched`: head, tunic and
legs take the same random index, and the lists line up by colour.

Review: `docs/kit/nomad_heads.png` (close up, before and after,
`tools/look/sheets/23_nomad_heads.json`), `docs/kit/nomad_heads_body.png` (on a
nomad's body, `24_nomad_heads_body.json`), `docs/kit/nomad_packs.png` (the four
pack styles, member and leader, `25_nomad_packs.json`) and
`docs/kit/nomad_heads_colors.png` (every shape in every colour, as on the barge,
`26_nomad_heads_colors.json`).
