# Decision Log

> Condensed decision history from the design conversations that produced the research documents in `docs/research/`. Each entry captures: the question, the options considered, the decision, and the reason.

> Most decisions distilled across **five "single-point" discussions** during product design (May 2026). Full reasoning lives in `docs/research/01-system-design.md` and adjacent docs.

---

## SP-1: Haptic output source

**Question:** Which wireless wearable do we send vibration commands to?

**Options considered:**
- Bangle.js 2 smartwatch — open-source Espruino, BLE high-level command `Bangle.buzz(strength, ms)`, IMU + compass + HR included
- bHaptics TactSleeve / Tactosy for Arms — multi-motor VR haptics, official Unity/C# SDK
- buttplug.io / Intiface — largest open-source haptic-control library (750+ devices)
- Joy-Con × 2 — HD Rumble

**Decision:** Bangle.js 2 × 2 (both wrists).

**Reason:** smart endpoint (logic on watch) vs dumb peripheral; low BLE packet rate → high stability. Joy-Con's own IMU reports its vibration as motion → BLE packet flood under continuous dual-unit use. buttplug.io technically excellent but adult-product ecosystem is bad optics for an accessibility product. bHaptics is the productization-phase candidate (legitimate VR accessory, can layer multi-motor directional haptics).

---

## SP-2: Compute platform

**Question:** Where do we run YOLO + Depth Anything + decision logic?

**Options considered:**
- Android flagship phone (Snapdragon 8 Gen 3 / Elite, ~45–73 TOPS NPU)
- iPhone (Core ML, efficient but iOS sandbox restrictive)
- Jetson Orin Nano / NX / AGX Thor
- Horizon RDK X5 / Ultra
- Raspberry Pi 5 + Hailo-10H

**Decision:** Android flagship phone.

**Reason:** flagship NPU (~50–70 TOPS) already meets or exceeds Jetson Orin Nano (67 TOPS, $249); phone bundles camera + IMU + GPS + Bluetooth + screen + battery for free. iOS is more efficient per watt but sandbox blocks continuous background camera + free BT — exactly what this app needs; iPhone is a productization bonus, Android is for validation. Jetson reserved for "resident large VLM + multi-camera/LiDAR fusion + SLAM" simultaneously, which we never need in V0–V3.

---

## SP-3: Wearing form and glasses deployment

**Question:** Where on the body, and how do we extend from phone to glasses?

**Options considered:**
- Phone neck-hang
- Phone chest harness
- Glasses Route A: phone-only
- Glasses Route B: glasses input + phone compute + output
- Glasses Route C: model runs on glasses temple SoC

**Decision:** Phone chest harness for V0–V2; Route B (glasses input + phone compute) for V3.

**Reason:** chest harness more stable than head-mount (torso doesn't flap with head turns); off-the-shelf GoPro Chesty-class straps available ¥30–100 (many listings literally market "blind cane training POV" — a positive signal). Route A and B share 100% phone-side compute code (only camera source swaps), so phone-first is **foundation for glasses, not detour**. Route C limited by temple thermal throttling + tiny battery — only suitable for one lightweight task; we wait.

---

## SP-4: Algorithm stack

**Question:** Which models, what runtime budget, how do we decide direction?

**Options considered:**
- YOLO11n + Depth Anything V2-Small (detection + segmentation + depth)
- Combined Mamba-architecture 5MB model (PMC12300176)
- VLM-only (Gemini-1.5-Pro-class, every frame)
- SLAM-based reconstruction

**Decision:** YOLO11n-seg (detection + walkable segmentation, ~6 MB) + Depth Anything V2-Small (FP16, ~50 ms on Snapdragon 8 Gen 3 NPU) + DFS path search on 15×15 grid + IMU heading stabilization. VLM (SmolVLM2 / Moondream / Gemini Nano) on-demand only.

**Reason:** these models all have ready mobile NPU builds; flagship phone NPU can run all three at 10–15 FPS — sufficient for human walking speed. PathFinder paper (arXiv:2504.20976) measures 0.377 s indoor response vs Gemini-1.5-Pro 3–5.75 s; 73% of BLV participants learned in under a minute. VLM cost too high to run every frame and not safety-critical — gate behind user button press.

---

## SP-5: Feedback modality

**Question:** How does the system tell the user what to do?

**Options considered:**
- Phone speaker (TTS external playback)
- In-ear earbuds
- Bone-conduction headset
- Bangle wrist haptics
- Bone-conduction headset doing both audio AND directional haptics via L/R channel

**Decision:** **Two-channel split.** Audio (bone-conduction) for semantics ("what / complex info / VLM output"). Haptics (Bangle) for direction ("where to go / emergency"). Bone-conduction CAN double as on/off emergency haptic via low-frequency pulse (free extra channel), but **cannot encode L/R direction** (skull cross-talk delivers vibration to both cochleae with negligible time difference; per peer-reviewed *"Interference Pattern Caused by Bilateral Bone Conduction Stimulation Impairs Sound Localization"*, PMC12407360, 2025). Direction must come from speech ("left" / "right") or wrist haptics.

**Version evolution:**
- V0: phone speaker TTS (1-line code, zero hardware) — to validate algorithm logic
- V1: + bone-conduction headset — solves environmental sound masking + privacy
- V2: + Bangle haptics — full two-channel split
- V3: + smart glasses — glasses input, phone brain, audio + temple haptics output

---

## SP-6: Web/PWA vs native vs Capacitor

**Question:** Can we skip Android Studio toolchain by using PWA or Termux?

**Options considered:**
- Pure PWA (WebRTC + WebGPU + ONNX Runtime Web)
- Termux local Python server + HTML frontend
- Capacitor (WebView native shell)
- Tauri 2 Mobile
- Pure native Kotlin

**Decision:** **Pure native Kotlin + LiteRT + QNN delegate.**

**Reason:** PWA's three fatal points — backgrounded camera stops, no NPU on Android WebNN (Chromium 2026-02 explicitly excludes Android), Web Bluetooth disconnects on tab-hide — are exactly this app's three hardest needs. Termux can't get camera video stream (only single-photo via Activity), can't access NPU, killed by OEM background policies. Capacitor is decent compromise but still requires Gradle/AndroidManifest knowledge; for a project planning real ML performance on NPU, just go native. (Detailed write-up: `docs/research/03-web-route-evaluation.md`.)

---

## SP-6A: V0 implementation boundary

**Question:** What exactly belongs in V0 implementation, given earlier docs used "V0" for both a minimum closed loop and a full corridor demo?

**Decision:** Split V0 into **V0a** and **V0b**.

- **V0a:** native Android minimum closed loop: CameraX frame capture → YOLO CPU/XNNPACK inference → Android TTS output.
- **V0b:** phone-only known-corridor demo: add Depth Anything, QNN/NPU acceleration, DFS corridor extraction, conservative state machine, and blindfolded testing with a sighted spotter.

**Reason:** the minimum loop and the corridor demo have different risk profiles and acceptance gates. Splitting them preserves the fastest implementation start without weakening the V0 safety/performance target.

**V0 exclusions:** no custom walkable-area training, no BLE, no Bangle.js haptics, no bone-conduction routing, no smart glasses, no VLM query flow, no outdoor navigation, no crosswalk command output, and no unsupervised blind-user testing.

**Safety/privacy gates:** no video-frame upload, no default frame storage, no face recognition, no cloud VLM call, and low-confidence/uncertain geometry must prefer STOP over CLEAR. Full boundary: `docs/plan/v0-implementation-plan.md`.

---

## SP-7: Dev machine

**Question:** Mac or Linux as primary development machine?

**Decision:** **Linux** (May 2026).

**Reason:** Linux is native x86_64 for Android command-line tools and NDK (Google ships only `linux-x86_64` binaries; arm64 Linux builds aren't supported by Google themselves). On Linux, Docker is optional — toolchain can install directly. Apple Silicon path remains documented for future Mac contributor — works via Rosetta but with ~20% overhead and occasional NDK clang quirks.

---

## SP-8: Build & distribution

**Question:** How do we build and distribute without installing Android Studio IDE?

**Decision:** Docker (or direct Linux install) for builds — `cimg/android:2026.03-ndk` with mounted source + Gradle cache. `adb install` for self-test. Google Play first formal distribution channel ($25 one-time, AAB, accessibility-tool declaration); Chinese stores (Huawei, Xiaomi) deferred until a corporate entity exists.

**Reason:** Android Studio is just IntelliJ + Gradle invoker; doesn't add to the build per se. Docker keeps environment reproducible across the team. Google Play accepts individual developers (with 14-day closed test); Xiaomi closed individual registration in late 2024; Huawei accepts individuals but needs software copyright + MIIT App filing — same cost as Xiaomi minus the corporate-subject requirement. Chinese stores' compliance load exceeds code-writing load, so defer until product is validated.

---

## SP-9: Name

**Question:** What do we call this?

**Decision:** **Roana / 漫行**. Domain `roana.app` acquired May 2026; GitHub org `floatinglifeai/roana` created.

**Reason:** modality-agnostic, device-agnostic, screen-reader friendly (`/roʊˈɑːnə/`, 3 clean syllables; 漫行 two common Chinese characters, no polyphony in this compound); empowerment tone (action verb, no help/aid/light framing); clean trademark space (no tech / accessibility / navigation / health collisions found in research); Chinese pairing 漫行 directly inherits "roam" meaning, accidentally bilingual. Earlier favorites Wayfinder / Pace / Vela / Rove rejected due to trademark crowding or generic-word App Store search disadvantage. (Detailed write-up: `docs/research/00-vision-and-naming.md` and `docs/research/05-domain-and-trademark.md`.)
