# MTG Table (iPad)

Shared two-player game dashboard for physical Magic: The Gathering. iPad only, landscape and portrait.
The iPad lies flat between the players; the top player's half is rotated 180 degrees.

## What's built (Phase 1: the table)
- Setup: Commander (40), Standard (20), Brawl 2-player (25), Brawl multiplayer (30), Oathbreaker (20), Custom.
  Starting life, commanders per player (0/1/2), commander tax and commander damage are all editable
  (Formats button, top right). Starting player: manual or random animation.
- Life: -1/+1, +/-5, +/-10, "Enter / set..." keypad (lose 17, gain, set to) with a before/after preview.
- Commander tax per commander (0, +2, +4...) with manual correction. Commander damage per commander
  with an optional "also lower my life" (one undo step), 21 warning per commander (never combined).
- Poison, energy, experience, rad counters (poison warning at 10). Monarch and initiative markers.
- Turns: highlighted active player, Next Turn / End my turn, total turns, each player's turn number and
  the round tracked separately; extra turns, skipped turns and active-player correction (Turns menu).
- History with timestamps and turn, undo/redo (related changes undo together), autosave and restore.
- End game: win, draw, concession, unfinished, with warnings and a confirm step. Past games list.

## Added in Phase 3
- Commander picker: type a few letters to get suggestions, or tap "Choose" for the full list. Picking a
  commander fills in its official name and color identity. Bundled: Zimone, The Mimeoplasm, Ashling,
  Sauron, Dwalin, Samut, The Mindskinner, The Odd Acorn Gang, Saruman, Frodo (art and card images included,
  so they work offline). Other commanders can be added with "Look up online" and are remembered.
- Optional commander artwork behind each side (Options, in setup); solid colors are still the default.
- Long-press a name to see the full card facing you (both commanders, both faces of double-faced cards).
- Turn timer (optional turn limit alert) and chess clock (per-player time budgets), Take priority /
  Return clock, pause, game time, and per-player time used. Alerts never end the game.

## Added in Phase 4 (tokens)
- Token board (Tokens button): each player's tokens in groups, facing their owner, with art, quantity,
  current power/toughness, counters, keywords, tapped and summoning-sick status.
- Add tokens by Quick pick (19 bundled common tokens with art, plus recently used), Search (Scryfall), or Custom.
  Noncreature tokens (Treasure, Clue, Food...) need no power/toughness.
- Tap/untap/modify/remove any number from a group; it splits automatically and merges back when identical.
- Summoning sickness uses real turn starts (not guesses); Haste, "can't attack", Defender and "doesn't untap"
  are handled; manual overrides everywhere. Auto-untap each turn (can be switched off) skips "doesn't untap".
- Undo/redo covers all token changes. Still to come: anthems, token math, attacking power (Phase 4b).

## UI redesign
- Each half: life area, always-visible token row with art, and a row of chips (Counters, Commander,
  Monarch, Initiative). Counters and commander tax/damage open as panels on that player's side.
- Counter and commander numbers show as small pills when they matter. Middle bar: history, undo, redo,
  Next Turn, and one menu (turns, timer, tokens, end game). No emojis anywhere (SF Symbols only).

## Drag to attack
Drag from your half toward the opponent's half. Starting on a commander chip (arrow icon under your name)
deals commander damage from that commander; starting anywhere else deals normal damage. An amount panel
opens facing the attacker with a before/after preview; nothing changes until you press Deal. Commander
damage can also lower life in the same step (one undo).
Dragging from a commander card (not just the chip) also deals commander damage. A two-finger drag opens a
special attack: choose Life gain, Double strike, Both or Neither, then the amount; double strike deals the
amount twice and life gain gives the attacker the total damage dealt, all as one undo step.

## Phase 4b: effects, token math, attacking power
- Effects (anthems): a named bonus (+power/+toughness and/or keywords) aimed at all creature tokens, chosen
  types, or specific groups, for your tokens, theirs, or both. Stats are always computed from the active
  effects, so editing, turning off or removing one updates every token at once, new tokens included.
  Effects stay separate from counters and a token's own bonus.
- Token math: starting amount x doublers/triplers, shown before adding, plus a manual override.
- Attack power: pick groups and quantities; flags tapped, summoning-sick and can't-attack tokens;
  double strike counts twice; labeled as attacking power, not guaranteed damage. Can tap the attackers
  (vigilance excepted) or send the total to the damage panel.
- 89 bundled tokens with art, with a filter.

## Notes, reminders, Voltron calculator, celebration, Siri
- Notes: attach to a player, commander, token group or effect. Public notes show to both players; private
  notes stay hidden until their author taps Reveal and hide again after a few seconds.
- Reminders: tap-bubble builder (when, what, how many, whose turn), saved library, phase tracker in the middle
  bar, Event menu, one expandable banner per occurrence, suggestions when the monarch/initiative is taken.
- Voltron calculator (Commander panel): base stats, equipment/auras/counters with contributions, keywords,
  temporary modifiers that expire, attacking power (kept separate from commander damage dealt).
- Winner celebration: drum roll, trumpet, confetti, winner and commander card. Settings in Formats.
- Siri / Shortcuts (App Intents): "<player> is now the monarch in MTG Table", initiative, gain/lose life,
  poison, next turn, undo, life totals.

## Not built yet
Decks and records, tokens, anthems, attack math, stack,
battlefield effects, notes, Voltron calculator, reminders, stats and charts, celebration sounds.

## Open and run
Open `MTGTable.xcodeproj`, pick an iPad simulator or your iPad, press Play.
Signing is already set to your free personal team. Free accounts expire after 7 days: reinstall to renew.

## Testing flags (simulator only)
`-demo` starts a ready-made Commander game. `-forceLandscape` previews the landscape layout.

## Credits and legal
Card names, text and images are property of Wizards of the Coast. This is an unofficial, non-commercial fan
tool and is not affiliated with or endorsed by Wizards of the Coast. Card data and artwork come from
[Scryfall](https://scryfall.com). The bundled sounds (drum roll and trumpet) are synthesized for this app.
