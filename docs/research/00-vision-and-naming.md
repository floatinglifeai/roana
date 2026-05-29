# Vision and Naming

> Where the name **Roana** comes from, what it stands for, and why naming an accessibility product is harder than naming a general consumer product. This document records the design conversations behind the name so future contributors understand the constraints.

---

## 1. Product vision (the one sentence that drove every other decision)

> **"Walk your world."** — Roana is an electronic travel aid that gives blind and low-vision users the freedom to go wherever they want, on their own pace, with their own ear free for the world around them.

Three commitments hide inside that sentence:

1. **Walk** — action, agency, autonomy. Not "be guided," not "be helped," not "be illuminated." The user is the subject; we are infrastructure.
2. **Your** — possessive, personal. The product belongs to the user, not the other way around. A blind user with Roana is still a *traveler*, not a *patient* or a *case*.
3. **World** — the whole world, not "the world built for blind people." We do not build a parallel world; we lower the cost of operating in the existing one.

These three words also explicitly **rule out** the easy-but-wrong framings: "we help the blind see," "we are the eyes of the blind," "we give light to those in darkness." All of those center the deficit. Roana centers the journey.

---

## 2. Why naming was hard

Most product naming optimizes for memorability, brand differentiation, domain availability, and ASO keywords. An assistive technology product for blind users adds **four** more hard constraints — none of which can be skipped:

### Constraint A — Users hear the name, they don't see it

The primary input channel for our users is the ear, augmented by screen readers (TalkBack / VoiceOver / China's various 旁白 implementations). This rules out a large class of names that would work fine for sighted users:

- **Cute spellings** that screen readers mispronounce ("MySQL" gets read "My S-Q-L", not "my sequel"; ".lumen" forces the developer to teach users to say "dot lumen").
- **Multi-syllable foreign-language words** users can't repeat back to a voice search ("Lazarillo" — wonderful literary reference; unsayable for an English speaker).
- **Chinese names with polyphonic characters (多音字)** — TalkBack often picks the wrong reading.

### Constraint B — Emotional tone: empowerment, not pity

The blind community has been highly explicit about which framings they find offensive. We anchored our research on these primary sources:

- **NFB Resolution 93-01 (1993, Dallas)** rejected "person-first" euphemisms as "totally unacceptable and pernicious… overly defensive, implies shame instead of true equality."
- **Be My Eyes' Inclusive Language Guide (2024, by VP Bryan Bashin, former San Francisco LightHouse for the Blind CEO)** explicitly flagged "Support / Help / Helper" as "emphasizing a perceived power imbalance that is already uncomfortable," and recommended "Partner / Describer / Interpreter / Volunteer — words based on a relationship of equality." It also flagged "Inspirational / Brave / Courageous" as a form of "othering."
- **AppleVis user comments** on a product literally called "Vision: for blind people" — a real user review: *"this is very ablest [sic]… the name makes it sound like it's providing 'vision for blind people'. Sometimes blind people have way more vision than sighted people."*
- **Chinese context, Cai Yongbin (蔡勇斌)**, blind founder/CEO of EQuiet (一同信息), as quoted by China Disabled Persons' Federation: *"I don't think building special products for special groups is sustainable. I also pick a restaurant, the cuisine, use coupons, choose sweetness for milk tea. We may use different methods but the goals are the same."*

Net rule: **never** use Help / Aid / Care / Support / Inspire / Light / Brave / Hope / Vision / See / Sight / Eye / 助盲 / 关爱 / 光明 / 看见 / 希望.

### Constraint C — Modality- and device-agnostic

Roana is multi-modal (audio + haptic) and multi-device (phone → glasses → wristband, see [01-system-design.md](01-system-design.md) for the roadmap). Names anchored to a single sense or device age badly:

- "Seeing / Vision / See / 看见" — locks visual metaphor (and re-centers the deficit).
- "Echo / Sonar / Hear / 听见" — locks audio; once temple haptics arrive in V3, hearing is no longer the only output.
- "Cane / Stick / 拐杖" — locks form factor.

### Constraint D — Open-source repo and consumer product, one name

GitHub naming favors short, pronounceable, coined-OK names (Astro, Vite, Bun, Deno, Linear, Arc, Notion). App-store / China-store naming requires registrable trademarks, clean Nice-class 9 / 10 / 42 space, and ASO keywords carried by the *subtitle* rather than the name itself. The name has to work in both worlds.

---

## 3. Why "Roana"

**Roana** (pronounced /roʊˈɑːnə/, three syllables, soft and clear). Chinese pairing: **漫行** (màn xíng) — "to walk freely / to roam."

The candidate came from a structured search that started from the **"roam" word family** (a direction the founder specifically asked to explore for its freedom-and-dignity connotation), found the obvious choices — Roam, Rove, Roamio, Wander, Wandr, Voya, Voyo, Yondr, Trekka, Nomad — all already taken by major brands (Roam Research, Roam.com, Voya Financial NYSE-listed, Yondr school phone-pouches, Trekka GPS app, HashiCorp Nomad, etc.), and then moved one step into **lightly coined adjacent forms** that retain the roam connotation without colliding.

Roana scored well on every hard constraint:

| Constraint | Roana / 漫行 score | Note |
|---|---|---|
| Screen-reader friendliness | ★★★★★ | English: 3 clean syllables, no consonant cluster, TTS-stable. Chinese: 两字 / 常用字 / 无多音字 |
| Emotional tone | ★★★★★ | No help / aid / pity. "Walk freely" centers user agency |
| Modality / device agnostic | ★★★★★ | Says nothing about sense or hardware |
| Domain availability (roana.app) | ✅ | Acquired by the team in May 2026 |
| Trademark crowding | Low | No tech / accessibility / navigation / health collisions found in research; needs formal CNIPA / USPTO clearance in classes 9, 10, 42 before commercial launch |
| Voice-searchable | ★★★★★ | Phonetic, no spelling traps |
| Chinese pairing | 漫行 (màn xíng) | Direct lineage from "roam"; widely-used characters; no polyphony in this 词组 |

### What the name does NOT say

A useful test of a good name: list what it does NOT promise.

- Roana does not say "we will see for you."
- Roana does not say "you are blind."
- Roana does not say "you need our help."
- Roana does not promise a specific sensor, a specific algorithm, or a specific form factor.
- Roana does not even promise navigation — it just promises **walking**, the broader category.

This is intentional. The name has to last from V0 (phone in chest harness) through V3 (smart glasses + wrist haptics) through whatever V4+ becomes. The narrower the name, the shorter its useful life.

---

## 4. Naming candidates we considered and rejected

Recorded here for future contributors so the conversation doesn't have to be re-run.

### 4.1 First-round candidates (general directions)

| Candidate | Direction | Why not |
|---|---|---|
| `seeing-ear`, `seeing-air` | Clever play on "Seeing Eye dog" with audio | Locks to audio; once V3 haptics arrive it ages |
| `clearpath`, `pathsense`, `walksight`, `depth2dir` | Functional / technical | Locks to function or sense; description not identity |
| `wayfinder` | Path-finding | Founder favorite, but trademark space already crowded — Transfinder Wayfinder (school bus SaaS), ObjectiveEd Wayfinder (visually-impaired education), AbleLink WayFinder, Wayfinder Systems AB (Sweden GPS), Genium Wayfinder; usable as repo codename, not as consumer product trademark |
| `chirrut` (Star Wars blind Jedi) | Sci-fi inspiration | Spelling unsearchable for users; obscure to non-Star-Wars audiences |
| `tars` (Interstellar AI) | Sci-fi inspiration | TARS Inc., TARS robotics, etc. taken |
| `echo` | Bat-style echolocation | Locks audio; Amazon Echo collision |

### 4.2 Second-round (modality-agnostic)

| Candidate | Why not |
|---|---|
| `pace` / 同行 | Loved the partner / pacing connotation; English is a generic word with crowded trademark space; Chinese "行" has polyphony (xíng vs háng) requiring constant disambiguation |
| `vela` (Latin "sail" / sail constellation) | Elegant; Vela Bikes and other brands occupy the .com; .app for sale at premium |
| `rove` | Cleanest roam-family verb; Rove.com (travel rewards), Rove.io (EV comparisons), Roveworld.xyz (Web3) all taken |
| `voya`, `voyo` | Voya Financial is NYSE-listed; Voyo.eu is a major Central European streaming brand |
| `wendr` | The .com is owned by [L]earned Media (their wendr-the-product shut down Feb 8, 2012, namespace effectively freed); 2010s vowel-drop style felt dated |
| `andora` | Italian *andare* root; permanent "Andorra" country-name spelling confusion |
| `andala` | Pure coined word, safest from a trademark perspective; meaning needs more brand storytelling than we wanted at this stage |

### 4.3 Why Roana won

The shortlist after round 2 was: **Roana / Wendr / Andora / Andala**. We picked Roana because:

1. **Cleanest possible search landscape**: no tech / accessibility / navigation / health brand collisions found.
2. **Domain available**: `roana.app` was free and was acquired by the team in May 2026.
3. **Most natural to say across languages**: ro-AH-na flows in English, Chinese, Japanese, Korean, Spanish; no syllable a non-native speaker stumbles on.
4. **Chinese pairing (漫行) is unforced**: many candidates needed a Chinese name that felt translated. 漫行 is independently a strong Chinese name that happens to share the *roam* meaning — accidentally bilingual.
5. **Slogan-friendly**: *"Your path. Your pace. Roana."* / *"你的路，你的步伐。漫行。"* — both work.

---

## 5. Brand operating notes (for future contributors)

A few things to keep in mind as the project grows.

### 5.1 Pronunciation

- English: **/roʊˈɑːnə/** — "ro-AH-na". Three syllables. Stress on the middle.
- Chinese: **漫行** (màn xíng). Both characters are common. *No polyphony in this compound* — TalkBack and most TTS engines read 行 as `xíng` here. If anyone ever shortens to just "行" alone, the reading becomes ambiguous (xíng / háng); avoid the single character standalone.

### 5.2 Capitalization

- Brand: **Roana** (initial capital).
- Lowercase `roana` is fine in code / package names / domains / handles.
- Never ALL-CAPS unless typographically necessary (it sounds shouty when a screen reader reads it).

### 5.3 What slogans we tested

- ✅ "Walk your world."
- ✅ "Your path. Your pace. Roana."
- ✅ "你的路，你的步伐。"
- ⚠️ "We see for you." — violates principle 2.
- ⚠️ "Light for the blind." — violates principle 2.
- ⚠️ "Your second pair of eyes." — locks visual metaphor.

### 5.4 Before any commercial launch, do this

1. **Formal trademark clearance**: CNIPA (China), USPTO (US), EUIPO (EU) in Nice classes **9** (software/hardware), **10** (medical / assistive devices — this is the class HumanWare, Aira, Be My Eyes, Envision all sit in), **42** (SaaS). Hire counsel; do not DIY this.
2. **Real-user voice testing**: have at least 5 blind users hear "Roana / 漫行" read by iOS VoiceOver and Android TalkBack in both English and Mandarin. Verify: (a) audibly clear, (b) voice-search returns the right result, (c) no negative associations, (d) word-of-mouth-able with cane / dog peers.
3. **Defensive registrations**: GitHub org (`floatinglifeai/roana` ✅ already done), npm / PyPI org if there will ever be an SDK, social handles (X / Instagram / TikTok / 小红书 / 微博 / B站).

### 5.5 If Roana ever has to be changed

Triggers that would force a name change:

- Formal trademark clearance comes back blocked in class 9, 10, or 42 in any of the three target jurisdictions.
- A real-user voice test reveals >40% of blind users hear it incorrectly or feel the name carries pity / weakness connotations.
- A major collision emerges (someone files an identical mark with priority before us, or a new product launches in the assistive-tech space using a confusingly similar name).

In that case, the fallback order from the original research was: **Andala** → **Roanna** → start a fresh round.

---

## 6. Inspirations

A few sources of taste worth noting for future contributors:

- **Aira** — small coined word, modality-agnostic, partner framing throughout. UCSD Rady School records confirm it's "AI" + "RA" (remote assistance). Excellent reference.
- **Glide / Glidance** — verb, motion, no help / aid framing. Excellent reference.
- **biped / NOA** — two-tier naming: company name = the form factor it's *not* (humans, not robots), product name = action verb acronym. Good model for future Roana sub-brands.
- **WeWALK** — pronoun + verb, equality + action in 5 letters. Founded by a blind person (Kürşat Ceylan). Excellent reference.

What we deliberately did not imitate:

- **Be My Eyes** — vision metaphor + help framing. Their own 2024 Inclusive Language Guide reads almost as a self-correction.
- **Envision / OrCam / Seeing AI** — all vision-metaphor names. They are successful, but each one had to fight uphill against the user community's discomfort with the framing.
- **.lumen** — beautiful word, but "light" centered on a population that does not experience it. Also forces "dot lumen" pronunciation.

---

## 7. Caveats

This document records the team's reasoning as of May 2026. The blind / low-vision community is not monolithic; individual users will disagree with specific choices, and that's fine — the goal is a name that is **defensible**, not a name that is universally loved. If a future contributor encounters substantive user feedback that contradicts the reasoning here, please open an issue rather than silently overriding it.

The name research drew on Western (NFB, RNIB, AppleVis, AFB AccessWorld, Be My Eyes) and Chinese (CDPF, 中国盲协, 蔡勇斌 interviews) primary sources. Coverage is uneven; non-English / non-Chinese language communities (Korean, Japanese, Arabic, Spanish, Hindi-speaking blind communities) were not systematically consulted and may have different conventions worth incorporating later.
