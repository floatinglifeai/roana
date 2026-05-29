# Roana

> **Walk your world.** An open-source assistive navigation system for blind and low-vision users.

Roana turns a smartphone (and, later, smart glasses) into a real-time perception companion: on-device computer vision detects obstacles and walkable space; the system then guides the user through **bone-conduction speech** ("what's around you") and **wrist haptics** ("which way to go") — a two-channel feedback split that keeps cognitive load low while preserving environmental sound, which blind and low-vision users rely on.

The name comes from the *roam* root — the freedom and dignity of going wherever you want, on your own pace. In Chinese: 漫行 (màn xíng) — "to walk freely."

---

## Status

🟡 **Pre-V0 — design and planning phase.** No code yet. This repository currently hosts the research, technical design, and decision history that the implementation will be built on.

Implementation begins after the docs in `docs/research/` settle. The roadmap is V0 → V3, summarized below.

---

## What this project is (and isn't)

**Is:**

- An **electronic travel aid (ETA)** that augments — never replaces — the white cane and guide dog.
- A **multi-modal, multi-device** system. Audio and haptic feedback work together. Form factor evolves from phone (V0) to smart glasses (V3).
- **Off-the-shelf hardware only.** No PCB design, no firmware bring-up, no soldering. Everything is a consumer product the user can buy today: an Android phone, a Shokz bone-conduction headset, a Bangle.js 2 smartwatch, eventually a pair of Mentra Live glasses.
- **Built with AI assistance.** A core goal is to validate that a small team (or one person) plus Claude can build, ship, and maintain accessibility software that previously needed a whole engineering org.

**Isn't:**

- A medical device. Roana does not diagnose, treat, or cure anything.
- A replacement for orientation & mobility (O&M) training, the white cane, or a guide dog.
- Yet another VLM-in-a-box. The core safety loop is a lightweight detection + monocular depth pipeline running at ~10 FPS; large vision-language models are called only on demand (e.g., user asks "what's in front of me?").

---

## High-level architecture

```
┌──── Input ────┐   ┌──── Compute ────┐   ┌──── Output ────┐
│ Phone camera  │ → │ Android NPU      │ → │ Bone-conduction │
│ (V3: glasses) │   │ YOLO11n-seg      │   │ TTS (semantics) │
│ Phone IMU     │   │ Depth Anything V2│   │ Bangle.js 2     │
│               │   │ Geometric policy │   │ haptics (direction)│
└───────────────┘   └─────────────────┘   └─────────────────┘
```

Three layers:

1. **Perception** — YOLO11n-seg (detection + walkable-area segmentation, ~6 MB) + Depth Anything V2-Small (~25M params, monocular depth, ~50 ms on Snapdragon 8 Gen 3 NPU). Always-on at ~10 FPS.
2. **Decision** — Project depth + walkable mask into a 15×15 grid; DFS for the longest safe forward corridor; output one of `STRAIGHT / LEFT / RIGHT / STOP` with IMU heading stabilization.
3. **Feedback** — Audio (bone-conduction TTS) for semantics ("step ahead, two meters"); haptics (left/right wrist buzz on Bangle.js 2) for direction and emergency.

Heavy VLMs (SmolVLM2 / Gemini Nano) are triggered on demand, not per-frame.

---

## Roadmap

| Stage | Goal | Hardware delta | Target |
|---|---|---|---|
| **V0** | Walk a known indoor corridor blindfolded, phone speaker reads directions aloud | Android phone in chest harness | 1–2 weeks |
| **V1** | Add bone-conduction Bluetooth headset → preserve environmental sound, fix privacy | +¥600–1500 (Shokz / 韶音) | +1 week |
| **V2** | Add Bangle.js 2 wrist haptics for directional cues; audio carries semantics; on-demand VLM | +¥1200–1500 | +2–3 weeks |
| **V3** | Swap phone camera for Mentra Live smart glasses (open MentraOS SDK); algorithm code 100% reused | +$299 (Mentra Live) | +1–2 months |

Full reasoning in [`docs/research/01-system-design.md`](docs/research/01-system-design.md).

---

## Repository layout

```
roana/
├── README.md                            # this file
├── LICENSE                              # Apache-2.0
├── docs/
│   ├── research/                        # six in-depth research reports
│   │   ├── 00-vision-and-naming.md      # product vision + naming research
│   │   ├── 01-system-design.md          # main technical plan (5 single-points → integrated)
│   │   ├── 02-tech-stack.md             # Mac → Android stack selection (native Kotlin recommended)
│   │   ├── 03-web-route-evaluation.md   # PWA / Capacitor / Termux — why we chose native
│   │   ├── 04-build-and-distribution.md # Docker-based headless build + Google Play / Xiaomi / Huawei
│   │   └── 05-domain-and-trademark.md   # name + domain availability landscape
│   └── discussions/                     # condensed decision logs from design conversations
└── .gitignore
```

---

## Design principles

1. **Off-the-shelf only.** Every component must be buyable today on Taobao / JD / Amazon / official stores. No hardware development.
2. **Wireless everything.** No cables. This is a hard UX requirement for blind users.
3. **Fastest validation first.** Every stage produces something a real blind user can walk with, within 1–8 weeks.
4. **Audio and haptics are co-equal channels**, not "audio is a temporary V0 hack." Audio carries semantics; haptics carry direction. Together they keep cognitive load low and the ear free for the world.
5. **Phone-first as the foundation for glasses.** V0–V2 code runs unchanged on V3 when the camera source switches from phone to glasses.
6. **Safety > coverage.** When confidence drops (low-light, glass doors, downward stairs), the system degrades gracefully and tells the user to rely on the cane.

---

## Inspirations & landscape

- **Be My Eyes** (volunteer-based remote sighted assistance)
- **Aira** (professional remote sighted assistance)
- **Envision Glasses** (smart glasses + OCR/object recognition)
- **biped.ai / NOA** (3D camera + spatial audio obstacle warning)
- **.lumen Glasses** (haptic-feedback navigation glasses)
- **WeWALK** (smart white cane augmentation)

Roana sits closest to biped in mission, but trades the dedicated 3D camera for a smartphone NPU plus monocular depth — cost target is roughly **1/5** of comparable commercial devices.

See [`docs/research/01-system-design.md`](docs/research/01-system-design.md) §8 for the full competitive landscape.

---

## License

**GNU Affero General Public License v3.0 (AGPL-3.0).** See [LICENSE](LICENSE).

Why AGPL? Roana is built for blind and low-vision users — a community that has been burned too many times by accessibility tech that gets bought, locked down, or paywalled. AGPL is our way of making one promise concretely:

> **Anyone can use, study, modify, and redistribute Roana — but any modified version, including network services, must also be released under AGPL-3.0.** This means companies cannot take Roana, close it up, add a paywall, and ship it back to blind users as a proprietary product.

We picked AGPL specifically because:

- It is **OSI-approved real open source** — the assistive-tech community (NVDA, Orca screen readers, etc.) has long-standing trust in the GPL family of licenses.
- It is a **strong copyleft**: derivative works and SaaS deployments must also be AGPL. This is how we keep Roana from being absorbed into a closed product.
- It does **not prevent commercial use** in principle — a company can run Roana commercially as long as they share their changes back under AGPL. We just don't want anyone to silently take and never give back.

If you are a non-profit, school, hospital, blind association, O&M instructor, or individual — AGPL imposes no practical burden on you. If you are a company and the AGPL terms don't fit your business model, please reach out to discuss a commercial license.

See [NOTICE.md](NOTICE.md) for the per-file copyright header template and contributor licensing notes.

---

## Contributing

Not yet open for code contributions — there's no code yet. **Design feedback is very welcome**, especially from:

- Blind and low-vision users (the people this is for)
- Orientation and mobility (O&M) instructors
- Computer vision / mobile ML engineers
- Anyone who has shipped accessibility software

Open an issue or start a discussion.

— Built with care, with [Claude](https://claude.ai) as a co-designer.
