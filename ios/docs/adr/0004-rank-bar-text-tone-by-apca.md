# Rank bar title text tone by APCA, not the WCAG 2.x contrast ratio

## Status

Accepted.

## Context

Calendar Event Bar titles sit on the Event Color, so their text color must keep them readable on any color Google can deliver. Two candidates exist — Planner's ink and white — and the question is which ranking picks the more readable one per color. The first rule was the Web Experience's YIQ luminance heuristic; the Event Color slice replaced it with "whichever of ink/white yields the higher WCAG 2.x contrast ratio," valued for its guarantee that the better of black/white always clears WCAG AA 4.5:1.

Real use broke that choice: on a mid-dark blue bar (`#5F83E6`, Google Blueberry family) the WCAG ratio prefers ink (4.6:1 over white's 3.6:1) yet the ink title is visibly hard to read — the user reported it against Google Calendar, which renders white there. The failure is a known flaw of the WCAG 2.x luminance ratio: it overvalues dark text on mid-dark saturated backgrounds (relative luminance ≈ 0.19–0.36), the exact band holding Google's blues, tangerine, and flamingo. Human perception, Google Calendar's own rendering, and the W3C's perceptually calibrated APCA (the WCAG 3 candidate contrast method) all rank white higher there.

## Decision

Bar title text tone is ranked by APCA lightness contrast (apca-w3 constants): compute the Lc of Planner's ink and of white against the Event Color and use the candidate with the stronger magnitude. APCA's polarity-dependent exponents model how the eye reads dark-on-light versus light-on-dark pairings, so its ranking matches perception across the whole palette — ink on banana, mint, and light blues; white on the mid-dark saturated band and dark colors. The rule stays a pure function of the Event Color with the same two text candidates.

## Consequences

- On Google's mid-dark saturated colors (Blueberry `#5484ED`, Peacock `#039BE5`, Lavender, Tangerine, Flamingo, Sage) bars now render white titles, matching Google Calendar and the reported readability expectation; light colors keep ink titles.
- The earlier "always above WCAG AA 4.5:1" guarantee language is retired: the picks optimize perceived readability, not the WCAG 2.x ratio, and on the affected colors the chosen white rates below 4.5:1 while reading better (APCA Lc 54–87 against the Lc 60 spot-text guidance).
- The iOS rule now diverges from the Web Experience twice over (web still uses YIQ): aligning web's bar text is a separate, deliberately deferred decision.
- APCA is a published W3C candidate algorithm, not a ratified standard; the apca-w3 constants are pinned in code, so a future revision is a deliberate update, not drift.

## Considered options

- **Keep the WCAG 2.x best-of-ink/white ratio.** Rejected: it provably mis-ranks the mid-dark saturated band (ink on `#5F83E6` at 4.6:1 chosen over white at 3.6:1, against perception and Google) — the guarantee optimizes a number, not readability, and produced the reported bug.
- **A luminance threshold forcing white below a cutoff.** Rejected: no single cutoff separates the bad blues (`#5F83E6` 0.244, `#039BE5` 0.291) from colors where ink is genuinely right (`#51B749` 0.361, `#FF887C` 0.403); the boundary is hue-dependent, which is what APCA's exponents model and a raw threshold cannot.
- **Mimic Google Calendar's per-palette text choices.** Rejected with the Event Color rule itself: it needs a hardcoded palette (wrong for custom calendar colors like the reported one) and couples Planner's presentation to Google's undocumented UI choices.
- **Stay with the Web Experience's YIQ rule.** Rejected earlier in the Event Color slice: it mis-picks in both directions (white on `#00AA00`-class greens, and it shares the mid-dark problem by threshold luck rather than principle).
