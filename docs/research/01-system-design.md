# Roana — System Design (V1.0)

> Integrated technical plan from the five single-point design discussions. Covers system architecture, the V0→V3 staged roadmap, perception/decision/feedback stacks, key selection tables, safety and compliance, and competitive landscape.

**Audience:** engineering team, product decision-makers.
**Next update trigger:** post-V0 measurement data, or breaking changes in major SDKs / hardware.

---

## 1. Overview and design principles

### 1.1 Goal

A camera (on phone or smart glasses) plus on-device vision models perceive the user's environment in real time. The system guides blind / low-vision users through a **two-channel feedback split**:

- **Audio (bone-conduction)** — semantics: "what's around you" (step ahead, person on your right, walk signal is green).
- **Haptics (wrist vibration)** — direction: "where to go" (left / right / stop), low cognitive load.

Roana is an **electronic travel aid (ETA)**. It augments — does not replace — the white cane and guide dog. The effective range is roughly 0.5–10 m, primarily covering **upper-body-height obstacles and walkable-path direction**, which is precisely what canes and dogs cover poorly.

### 1.2 Design principles (apply throughout)

1. **Off-the-shelf only.** Every hardware element must be a consumer product directly orderable on Taobao / JD / Amazon / official stores. No circuit design, no PCB tape-out.
2. **No hardware development.** MVP and early product are software, models, and configuration only. Custom enclosures and mounts wait for the productization stage.
3. **Wireless everything.** All peripherals over BLE. This is a non-negotiable UX baseline for blind users.
4. **Fastest validation.** Each stage produces something a real visually-impaired person can walk with, within 1–2 weeks of stage entry.
5. **Audio and haptics are co-equal main channels** — not "audio is a temporary V0 hack." They form complementary tracks (semantics vs direction).
6. **Phone-first as foundation for glasses.** All compute runs on an Android phone first; the glasses version (V3) is the same algorithm with the camera source swapped — the algorithm, decision, TTS, and haptic-driver code are **100% reused**.

---

## 2. System architecture

### 2.1 Three layers × three elements

Logically three layers; physically three elements: input / compute / output.

```
┌─────────────────────────────────────────────────────────────┐
│  INPUT                  COMPUTE                  OUTPUT     │
│  ─────                  ───────                  ──────     │
│  • phone rear camera    • Android SoC + NPU      • phone speaker (V0)│
│  • phone IMU/compass    • Kotlin/Python app      • bone-conduction headset (V1+)│
│  • GPS (outdoor route)  • LiteRT / ONNX Runtime  • Bangle.js 2 haptics (V2+)│
│  • glasses camera (V3)  • temple SoC (V3, route C)│ • temple haptics / speaker (V3)│
└─────────────────────────────────────────────────────────────┘
        ↓                       ↓                       ↑
   PERCEPTION              DECISION                 FEEDBACK
   ─────────              ────────                 ────────
   ① obstacle det.        ④ depth+walkable →       ⑤ state machine →
      YOLO11n                centerline offset         BT command fan-out:
   ② walkable seg.            + IMU heading hist.      - haptic commands
      YOLO11n-seg              → L/R/STRAIGHT/STOP    - TTS speech
   ③ monocular depth
      Depth Anything V2-S
   (~10 FPS, always-on)    (CPU/JS, very light)   (hard real-time <50 ms)
```

### 2.2 Key architectural rules

- **Lightweight pipeline always-on, VLM on-demand.** The per-frame loop runs only `detection + segmentation + depth` to keep ≥10 FPS as the safety floor. A small VLM (SmolVLM2 / Moondream / Gemini Nano) is triggered only when the user presses a button to ask "what's that?" or at intersections / traffic signals.
- **The wrist haptic is a smart endpoint, not a dumb peripheral.** Bangle.js 2 runs Espruino JavaScript; the phone sends only high-level semantic commands over BLE (e.g., `Bangle.buzz(0.6, 200)`); the watch handles PWM locally. This avoids the millisecond-rate BLE packet flooding that breaks stability.
- **Audio says "what"; haptics say "where".** Strict division of labor to avoid cognitive overload.

---

## 3. Staged roadmap (the core of this document)

The project unfolds in 4 stages by **gradually introducing complexity**. Each stage is an independently demonstrable, testable product form.

### 3.1 V0 — Pure Android phone, single device (target: 1–2 weeks)

> **Core hypothesis:** the algorithm pipeline (detection + segmentation + depth + direction decision) can run at ≥10 FPS on a mainstream Android phone and let a blindfolded user walk safely through a known corridor.

**Form:** user wears an Android phone in a chest harness (GoPro Chesty-class POV strap), camera forward, phone speaker reads directions ("clear ahead," "two steps right," "stop").

**Bill of materials (~¥3000–6000):**

| Item | Spec | Price | Note |
|---|---|---|---|
| Compute + camera + output host | Android phone with Snapdragon 8 Gen 3 / Gen 5 / Elite or Dimensity 9400, ≥12 GB RAM | ¥3000–6000 | NPU in the 45–73 TOPS range, sufficient |
| Chest harness | GoPro Chesty-compatible POV chest strap with J-hook | ¥30–100 | Many Taobao listings literally market this as "blind cane training POV" |
| Spare | Power bank + short cable | ¥50 | Continuous camera capture drains battery |

**Software / model / SDK selection:**

- **App framework:** Kotlin + Jetpack Compose; CameraX for frame capture; foreground Service for persistence.
- **Models:**
  - Obstacle detection + walkable segmentation: `yolo11n-seg.tflite` (Ultralytics official `model.export(format="tflite")`, INT8-quantized, ~6 MB).
  - Monocular depth: `Depth-Anything-V2-Small` — Qualcomm AI Hub pre-compiled assets (QNN context binary / TFLite), or HuggingFace `NexaAI/depth-anything-v2-npu-mobile` (Snapdragon 8 Elite Gen 4 NPU optimized).
- **Inference backend:** LiteRT (TFLite) + **QNN Delegate** (Qualcomm) or NeuroPilot Delegate (MediaTek). From Maven Central:
  ```gradle
  implementation 'com.qualcomm.qti:qnn-runtime:2.34.0'
  implementation 'com.qualcomm.qti:qnn-litert-delegate:2.34.0'
  ```
  Fallback: ONNX Runtime + QNN Execution Provider.
- **TTS:** Android `android.speech.tts.TextToSpeech` (Google TTS engine, offline voice pack 50–200 MB). Low latency, zero dependencies.
- **Decision algorithm:** DFS corridor extraction + IMU heading stabilization (see §4.2).

**Measured performance expectations** (from public Qualcomm AI Hub benchmarks):

| Model | Device (NPU) | Inference latency | Implied FPS |
|---|---|---|---|
| YOLOv8n-Detection (w8a8 QNN) | Snapdragon 8 Gen 3 / Galaxy S24 | ~0.9 ms | far above need |
| YOLO11n-Detection (TFLite NPU) | Snapdragon 8 Gen 3 / Galaxy S23 | ~5.5 ms | ~180 FPS |
| Depth Anything V2-Small (TFLite NPU, FP16) | Snapdragon 8 Gen 3 / Galaxy S24 | ~50 ms | ~20 FPS |
| Depth Anything V2-Small (TFLite NPU, FP16) | Snapdragon 8 Elite / Galaxy S25 | ~36 ms | ~28 FPS |

→ Depth is the bottleneck; the full chain (detection + segmentation + depth + decision + TTS queue) stably hits **10–15 FPS** on a flagship phone — sufficient for navigation.

**Hypotheses to validate:**

1. Does the decision-layer algorithm output "useful-to-a-human" direction commands on real streets (non-jittery, not flapping)?
2. How stable is monocular *relative* depth on hard cases (ground / steps / glass doors)?
3. Does 30 minutes of continuous camera + NPU inference thermal-throttle?

**Expected pain points:**

- Direct sunlight on screen → phone auto-dims / overheating protection kicks in.
- TTS queue piling up → use `QUEUE_FLUSH` (not `QUEUE_ADD`) so urgent commands preempt.
- Chest-mounted phone has a 5°–15° offset between camera axis and body axis → decision layer must calibrate "image centerline" → "body centerline."

---

### 3.2 V1 — Add Bluetooth bone-conduction headset (target: +1 week)

> **Core hypothesis:** routing voice from phone speaker to bone-conduction headset solves both the "ambient sound masking" and "privacy / social" problems, with controllable BLE latency (<150 ms).

**Why bone-conduction is required:**

- Blind users depend far more on environmental sound (traffic, footsteps, echolocation) than sighted users. In-ear earbuds block the ear canal, reducing both subjective safety and actual safety. Bone-conduction transmits via the temporal bone directly to the cochlea while **keeping the ear canal fully open**, and is explicitly recommended by LS&S, Braille Institute, and other blind-assistive-tech organizations.
- Phone speakers create strong social pressure on subways, elevators, and meetings.

**BOM delta (+¥600–1500 on V0):**

| Item | Spec | Price | Note |
|---|---|---|---|
| Bone-conduction headset | Shokz OpenRun / OpenRun Pro 2 | ¥800–1500 | BT 5.1/5.3, IP67, 8–10 h battery |
| Low-cost alt | 韶音 OpenMove / 塞那 Z10 etc. domestic brands | ¥300–600 | Same BT direct, zero extra dev |

**Software delta:** 1–2 lines — route `AudioManager` output to the BT device, TTS follows automatically; no audio stack rewrite needed.

**Optional layer: bone-conduction low-frequency pulse as emergency haptic cue**

- A bone-conduction headphone is fundamentally a temporal-bone vibrator; low-frequency signals produce a **physically perceptible vibration on the temple** (Shokz's DualPitch technology was specifically designed to suppress this — but did not eliminate it).
- We can use this for "emergency stop" — play a 50–80 Hz low-frequency pulse, **getting a zero-extra-hardware haptic channel for free**.
- **Physics caveat: cannot encode direction.** Skull cross-talk delivers vibration to both cochleae with negligible time difference. The peer-reviewed study *"Interference Pattern Caused by Bilateral Bone Conduction Stimulation Impairs Sound Localization"* (PMC12407360, 2025) confirms bilateral bone-conduction creates "cochlear-level waveform interference" causing "non-monotonic lateralization responses and even perceived directional reversal." **Direction must come from speech ("left" / "right") or wrist haptics; never from left/right audio channels on a bone-conduction headset.**

**Hypotheses to validate:**

1. Is the bone-conduction headset's BT latency within 100–200 ms (acceptable for direction commands)?
2. Can users hear TTS clearly on a noisy street (bone-conduction loses noticeable volume above 70 dB ambient noise)?
3. Does the TTS preemption mechanism actually work in emergencies (we cannot have "there's a puddle ahead" still playing when the "STOP" command needs to fire)?

---

### 3.3 V2 — Add Bangle.js 2 smartwatch haptics (target: 2–3 weeks)

> **Core hypothesis:** wrist haptics carry "direction + emergency" (low cognitive load) while audio carries "what / complex semantics" (high information). The two-channel split significantly lowers cognitive load.

**Why Bangle.js 2 over other haptic sources:**

| Candidate | Pros | Cons | Verdict |
|---|---|---|---|
| **Bangle.js 2** (chosen) | Open-source Espruino JS firmware; BLE high-level command `Bangle.buzz(strength, ms)`; built-in IMU, compass, HR; ¥600–750 each | Screen / form factor a bit geek | **First choice**: smart endpoint, low BLE packet rate, stable |
| buttplug.io / Intiface | Largest open-source wireless haptics control library; buttplug-py; connect to `ws://127.0.0.1:12345`; supports 750+ devices | Hardware ecosystem is adult products — bad public optics | **Private validation only** |
| bHaptics TactSleeve / Tactosy | Multiple independent motors per arm; official Unity/Unreal/C#/C++ SDK; TactSleeve $200/pair; Tactosy 6-point $250/pair | VR-toy positioning, awkward for daily blind-user wear | **Production-grade**, keep for productization |
| Joy-Con | Cheap, refined HD Rumble | Single HD Rumble motor per unit needs complex packets; IMU reports its own vibration as "motion" → BLE packet flood collapse (especially two units + continuous rumble) | **Not recommended** |

**BOM delta (+¥1200–1500 on V1):**

| Item | Spec | Price |
|---|---|---|
| Wrist haptics | Bangle.js 2 × 2 (both wrists) | ¥1200–1500 |

**Software delta:**

- **Phone side (Python/Kotlin):** use the Python `bleak` library (native BlueZ, cross-platform) to connect both Bangles and send Espruino REPL commands:
  ```python
  from bleak import BleakClient
  async with BleakClient(LEFT_BANGLE_MAC) as c:
      await c.write_gatt_char(NORDIC_UART_RX, b"Bangle.buzz(200,0.7)\n")
  ```
  Kotlin equivalent uses Android `BluetoothGatt` API.
- **Watch side (Espruino JS):** flash a minimal "command parser" app once that evaluates the incoming string as JS (sandbox limited by Espruino, safe).

**Feedback semantics (proposed v1):**

| Event | Audio (bone-conduction) | Haptic (Bangle) |
|---|---|---|
| Straight ahead, clear | (silent) | (silent) |
| Slight left correction | (silent) | Left wrist short buzz 1×200 ms |
| Slight right correction | (silent) | Right wrist short buzz 1×200 ms |
| Must turn left/right | "Turn left" / "Turn right" | Corresponding wrist 2×200 ms |
| Stop / emergency | "Stop" | Both wrists 1×500 ms strong |
| Intersection / complex scene | "Intersection ahead, crosswalk straight ahead" | (silent; user can press to trigger VLM) |
| User-asked scene (VLM trigger) | VLM output read aloud | (silent) |

**VLM on demand:**

- User presses Bangle physical button → phone grabs 1 frame → calls SmolVLM2-500M / Moondream2 / **Gemini Nano** (on-device) or GPT-4o-mini / Gemini Flash (cloud fallback) → TTS reads result.
- **Gemini Nano** is currently the most stable on-device VLM route on Android — distributed via ML Kit GenAI API through the AICore system service; supported on Pixel 8+, Galaxy S24+, several Xiaomi / Moto models. Per Google ML Kit docs: 4-bit quantization, 1.8B–3.25B parameters; first-token latency <100 ms on NPU-equipped flagships; Pixel 10 Pro measured 940 tokens/s on Gemini Nano v3 (Android Developers Blog, Aug 2025).

**Hypotheses to validate:**

1. Long-term wear comfort of Bangle on both wrists.
2. Multi-device BLE concurrency on the phone (A2DP headset + Bangle×2 GATT).
3. Can a new user internalize the haptic semantics in 1–2 hours of training?

---

### 3.4 V3 — Smart glasses integration (target: 1–2 months)

> **Core hypothesis:** in glasses form, camera angle is more stable (follows head), both hands fully released, overall UX improves significantly — while algorithm and feedback code is fully reused.

**Three glasses deployment routes:**

| Route | Description | Pros | Cons |
|---|---|---|---|
| **A** | Phone does everything (camera + compute + output) | Fastest, cleanest — already V0–V2 | Not "glasses form" |
| **B** (chosen for V3) | Glasses = input (camera + IMU) + phone = compute + output (audio via phone or glasses) | True glasses form; **algorithm code 100% reused from V0–V2** | Need to pick glasses whose camera video stream is readable from the phone app in real time |
| **C** (long-term) | Models run on glasses temple SoC | True all-in-one | Temple thermal throttling (Qualcomm AR1+ Gen1, Meta XR2 Gen2 = 12 TOPS); only one lightweight task |

**Route B glasses candidates:**

| Glasses | SDK / openness | Camera stream to phone | Language | Price | Integration |
|---|---|---|---|---|---|
| **Mentra Live** (recommended starting point) | MentraOS fully open-source (MIT), iOS/Android SDK, single SDK across hardware | Yes — hosted/unhosted RTMP stream, managed-stream API one-line start | TypeScript (cloud mini-app pattern runs on phone) | $299 | Low |
| **Brilliant Labs Frame** | Fully open-source, Python/Flutter SDK, `frame-sdk` pip-installable | Yes — `camera.save_photo()` + streaming; underlying BLE via `bleak` | Python / Lua / Dart | ~$349 | Low; camera is low-power 720p OV09734 + FPGA, limited fps |
| **Meta Ray-Ban / Oakley HSTN** (Wearables Device Access Toolkit) | Meta official SDK; Dec 2025 public preview (iOS+Android); GA planned 2026 | Yes — up to 720p @ 30 FPS (BT bandwidth limited, may auto-degrade) | Swift / Kotlin | $299–499 | Medium; needs Meta AI App bridge, currently org-internal testing only |
| **Rokid Glasses / INMO Air3** | YodaOS (Android 12-based, Snapdragon AR1); CXR-M (phone companion), CXR-S (glasses-side), CXR-L (standalone app) three SDKs | Yes — glasses are Android, can directly use Camera2 API | Kotlin/Java (essentially an Android app) | ¥3000+ | Medium; docs heavily Chinese, fits China market |
| ByteDance Doubao / Baidu Xiaodu / Huawei | Closed, no camera SDK | No | — | — | **Not considered** |

**V3 recommendation:** start the prototype on **Mentra Live** because:

- Open-source OS, complete MIT-licensed SDK, no approval gate;
- One-line `session.camera.startManagedStream()` to get an HLS/RTMP stream;
- $299, hardware spec friendly (12 MP / 119° / 3 mics / dual speakers — **temple speakers can serve as feedback directly, making the bone-conduction headset optional**);
- 43 g all-day wearable;
- MentraOS apps can later run on Even Realities G1, Vuzix Z100 without code change → productization flexibility.

**Software changes:**

- In the app, the "image source" abstraction gets one more implementation: `MentraGlassesCameraSource`, which decodes the RTMP/HLS stream and feeds frames into the existing YOLO/depth pipeline. **Everything else unchanged.**
- Feedback:
  - Primary: bone-conduction headset (V1 setup retained).
  - Optional: glasses temple speakers (open-ear, can layer on top).
  - Haptics: Bangle.js 2 retained (glasses themselves have no temple haptic motors).

**Long-term Route C (model-on-glasses):**

- RayNeo X3 Pro has demoed running Llama-1B-class SLM on temple;
- Qualcomm AR1+ Gen1 / Meta XR2 Gen2 (12 TOPS) can handle always-on keyword spotting + simple gesture recognition;
- Heavy workloads (depth, VLM) stay on phone.

**Hypotheses to validate:**

1. BT video stream (720p@30) end-to-end latency to phone within 100–200 ms (Meta DAT public number)?
2. With glasses camera angle better aligned to body forward direction, does decision-command stability improve materially?
3. User acceptance of the full 4-piece kit: glasses + bone-conduction headset + 2 wrist watches.

---

## 4. Algorithm stack details

### 4.1 Perception layer

#### 4.1.1 Obstacle detection: YOLO11n / YOLOv8n

- **First choice:** `yolo11n-seg.pt` (detection + instance segmentation combined), one-line export via `ultralytics`:
  ```python
  from ultralytics import YOLO
  model = YOLO("yolo11n-seg.pt")
  model.export(format="tflite", int8=True, data="coco128.yaml")
  ```
- **Known issues** (from Ultralytics GitHub issues #17837 / #18522 / #23282, 2025):
  - YOLO11 TFLite export on Android GPU delegate crashes on unsupported `ADD/CAST/CONCATENATION` ops.
  - **Workaround:** ① run **CPU + XNNPACK** or **NPU via QNN delegate** on Android (avoid GPU delegate); ② fall back to YOLOv8n (GPU delegate works); ③ use ONNX Runtime + QNN EP.
- **Quantization:** w8a8 INT8. Qualcomm AI Hub measured YOLOv8n w8a8 at **0.9 ms / frame** on Snapdragon 8 Gen 3 NPU; YOLO11n at **5.5 ms / frame** on Galaxy S23 NPU. Detection is nowhere near the bottleneck.

#### 4.1.2 Walkable-area segmentation

- Share the same `yolo11n-seg` (segmentation head trained together with detection; add classes like sidewalk / tactile paving / grass / puddle / step / stairs).
- Academic combined "detection + segmentation" 5 MB models hit 90+ FPS on desktop GPU (e.g., the Mamba-architecture work reported in PMC12300176); YOLO11n-seg on mobile is more than enough.

#### 4.1.3 Monocular depth: Depth Anything V2-Small

- **Off-the-shelf mobile deployment options:**
  - **Qualcomm AI Hub:** [`qualcomm/Depth-Anything-V2`](https://huggingface.co/qualcomm/Depth-Anything-V2) ships pre-compiled TFLite / QNN context binary; Snapdragon 8 Gen 3 NPU **~50 ms**, Snapdragon 8 Elite NPU **~36 ms**.
  - **NexaAI:** [`NexaAI/depth-anything-v2-npu-mobile`](https://huggingface.co/NexaAI/depth-anything-v2-npu-mobile), optimized for Snapdragon 8 Elite Gen 4 NPU (**note CC-BY-NC license, non-commercial only**).
  - **ONNX Runtime + QNN EP:** most cross-device-stable; falls back to CPU/GPU on MediaTek.
- **Relative vs Metric Depth:**
  - V2-Small by default outputs **relative depth** (per-pixel up to scale), no absolute meters.
  - Depth Anything V2 also offers **Metric Indoor / Outdoor** fine-tuned weights, but Small only has official relative-depth weights; Metric Small requires self-fine-tuning.
  - **Conclusion:** for obstacle avoidance, **relative depth is enough** — we care about "how much closer than ground is the nearest point in the forward corridor," not "is it 1.83 m or 2.05 m." The missing absolute scale can be coarsely calibrated using **known quantities**: eye-level height ~1.6 m, chest-mounted phone height ~1.3 m, ground pixel position.
  - For future "step at 50 cm, lift foot 15 cm" precision, switch to Metric (note Depth Anything V2 Metric in wild measurements MAE ~0.454 m, correlation 0.962 — current SOTA).

#### 4.1.4 Known monocular depth pitfalls and mitigations

| Pitfall | Symptom | Mitigation |
|---|---|---|
| **No absolute scale** | Same object may be estimated near or far | Camera-height + ground-pixel single-frame pseudo-calibration; IMU temporal smoothing |
| **Ground / steps / down-stairs** | Descending stairs often estimated as "flat extension"; down-stairs = death zone | Require "image-bottom quarter must contain a confident ground" — else trigger STOP; add "stair / step" classes to walkable-area model |
| **Glass / reflective** | Glass door may be estimated as "infinite distance, clear" | YOLO detects "door / glass curtain wall" as backstop; "glass" class in walkable area |
| **Strong / back light** | All-white or all-black, depth values flap | Inter-frame variance monitoring; over threshold → degrade to "detection only, ignore depth" |
| **Dynamic objects** | A pedestrian walking past flaps depth values | Decision-layer IoU tracking + 0.5s temporal smoothing |

### 4.2 Decision layer: depth + walkable mask → direction command

#### 4.2.1 Algorithm skeleton (based on PathFinder, arXiv:2504.20976, with our extensions)

**Core idea:** downsample the depth map into a **15×15 patch grid**; starting from the bottom-center cell (under the user's feet), do **DFS** expanding only upward ("forward = deeper in image"), looking for the longest and straightest safe path.

**PathFinder pseudocode (simplified):**
```
function find_path(grid, current_cell, path):
    upper6 = grid's 6 upper neighbors (UL, UUL, U, UU, UR, UUR)
    avg = mean(upper6)
    if avg < threshold or no feasible neighbor:
        return path  # branch ends
    if reached top or intensity discontinuity >> threshold:
        return path
    for neighbor in [up_left, up, up_right]:
        if grid[neighbor] <= grid[current]:  # farther = "deeper" = lower intensity
            recurse(grid, neighbor, path + [neighbor])
    return longest and straightest path
```

**Direction output (3-DOF mode):** horizontal offset of path endpoint → LEFT / STRAIGHT / RIGHT.
**Direction output (13-DOF mode):** clock-face direction (10 o'clock, 12 o'clock, 2 o'clock, etc.).

**Paper measurements** (300 indoor images): avg response time **0.377 s indoor** / **1.332 s outdoor** (including depth estimation; DFS itself near zero cost on 225 nodes); MAE 39.81° (indoor) / 36.45° (outdoor). End-to-end response **"markedly faster than all VLM and LLM-based methods"** (e.g., Gemini-1.5-Pro on the same task: MAE 41.00°, response 3–5.75 s). User study (paper abstract verbatim): *"A usability study with 15 BLV participants confirmed its practicality, where 73% learned to operate it in under a minute, and 80% praised its accuracy, responsiveness, and convenience."*

#### 4.2.2 Our extensions

1. **Fuse walkable segmentation:** DFS neighbor-safety check uses both depth AND YOLO-seg output. A pixel must satisfy both "depth deep enough" AND "belongs to walkable class" to count as walkable.
2. **IMU heading stabilization:** use phone/glasses IMU to estimate "heading change over past 1 s"; prevents per-frame command jitter (mild head-sway must not be translated to "turn left / turn right").
3. **Nearest-obstacle alert:** maintain a separate "nearest obstacle depth in lower-half of image" metric; below threshold → trigger STOP, skip DFS.
4. **State machine:** transition between 5 states (STRAIGHT / SLIGHT_ADJUST / TURN / STOP / QUERY); each state entry requires N consecutive frames (N=3) confirmation — avoids single-frame misjudgment.

### 4.3 Feedback layer

- **State-machine driven:** decision-layer output → feedback dispatcher → fans out to TTS queue + Bangle BLE queue simultaneously.
- **TTS queue management:** emergency commands ("STOP") use `QUEUE_FLUSH` to preempt; normal commands use `QUEUE_ADD`.
- **Haptic throttling:** same-direction commands not re-fired within 500 ms; intensity in 3 levels (light / medium / strong) by distance threshold.
- **Streaming TTS (optional V2+):** Android native `TextToSpeech` does not support streaming; if LLM output needs to play as it generates, integrate Picovoice Orca, Sherpa-ONNX, or open Maise (Kokoro + Whisper). Navigation main loop uses system TTS.

---

## 5. Key selection comparison tables

### 5.1 Haptic / tactile source

| Option | Price (pair/set) | Dev effort | Stability | Production optics | Verdict |
|---|---|---|---|---|---|
| **Bangle.js 2 ×2** (first choice) | ¥1200–1500 | Very low (high-level JS commands) | High (smart-endpoint arch.) | Geek-leaning | ✅ V2 onwards |
| bHaptics TactSleeve | ~$200/pair | Medium (Unity/C# SDK) | High | Legit VR accessory | Productization phase |
| bHaptics Tactosy for Arms | ~$250/pair (6-point ERM) | Medium | High | Legit VR accessory | Productization phase |
| buttplug.io / Intiface | Library free, hardware varies | Low (Python OK) | High (750+ device support) | ❌ Adult-product optics | Private validation only |
| Joy-Con | ~¥300/unit | High (impl. protocol) | ❌ IMU feedback flood | OK | Not recommended |

### 5.2 Compute platform

| Option | TOPS | Price | Built-in camera/IMU/GPS | Background camera freedom | Verdict |
|---|---|---|---|---|---|
| **Android flagship phone** (first choice) | 45–73 TOPS | ¥3000–6000 | ✅ | ✅ foreground Service / ADB sideload | V0–V3 throughout |
| iPhone / Apple Silicon | Same level + efficient Core ML | ¥6000+ | ✅ | ❌ iOS sandbox limits background camera + free BT | Productization bonus |
| Jetson Orin Nano Super | 67 TOPS | $249 | ❌ | — | Not needed |
| Jetson Orin NX | 100–157 TOPS | $400+ | ❌ | — | Only multi-camera + SLAM scenarios |
| Jetson AGX Thor | 2070 TOPS, 130 W | $3499 | ❌ | — | Overkill |
| Horizon RDK X5 | 10 TOPS | ¥430 | ❌ | — | Insufficient compute |
| Horizon RDK Ultra | 96 TOPS | ¥5000 | ❌ | — | More expensive than phone, fewer peripherals |
| Raspberry Pi 5 + Hailo-10H | +40 TOPS<5W | ¥3000+ combo | ❌ | — | Assembly hassle |

**Decision rule:** only leave the phone for Jetson when the system **simultaneously** requires resident large VLM + multi-camera/LiDAR fusion + SLAM full perception.

### 5.3 Glasses route

See §3.4 table.

---

## 6. Risk, safety, and compliance

### 6.1 Safety design principles (non-negotiable)

1. **Does not replace the white cane.** All user documentation, app launch prompts, and product packaging must clearly state: *"This is an ETA (Electronic Travel Aid), not a replacement for the white cane / guide dog."* This is the ETA industry consensus since the 1986 US National Research Council report. The cane remains irreplaceable for ground detection, steps, downward obstacles, and (legally protected) crosswalk right-of-way.
2. **Preserve environmental sound perception.** Forbid in-ear / sealed headphones; only bone-conduction or open-ear glasses temple speakers.
3. **Fail-safe degradation:**
   - When depth-model confidence drops below threshold → auto-switch to "detection-only + walkable-only" mode and voice-notify user.
   - When camera frame loss > 500 ms → immediate voice + strong haptic alert: "Vision system paused, please use cane."
   - Battery < 15% → voice warning 5 minutes in advance.
4. **Do not actively guide user across the street.** In V0–V3, traffic-light / crosswalk recognition is **informational only** ("crosswalk ahead, red light"), not a **command** ("cross now").
5. **Physical boundaries override algorithm.** Things physically impossible to see (descending stairs, wells, suddenly-appearing vehicles) must be assumed unsafe; the cane is the backstop.

### 6.2 Handling false positives and false negatives

- **Over-alarm > under-alarm:** prefer "false stop" over "false clear." State-machine threshold for STOP is looser than for FORWARD.
- **3-consecutive-frame confirmation:** avoids single-frame misjudgment; state-machine cycle held to 200–300 ms (acceptable user reaction latency).

### 6.3 Privacy and compliance

- **Continuous camera capture of others** is a sensitive behavior under both EU GDPR and China's Personal Information Protection Law. Our design choices:
  - **Data localization:** no video frames uploaded; cloud VLM calls (when used) send only one low-resolution screenshot, user-triggered.
  - **No face recognition / no archiving:** YOLO "person" class is treated as dynamic obstacle, no identity recognition.
  - **Public-space indicator:** glasses version (V3) must have a clear "recording" LED or audio cue (Meta Ray-Ban etc. do this by default; in-house version must retain).
- **Legal boundaries (China):** recording forbidden in subways, government facilities, public performance venues; app should have "location-sensitive zone detection + auto-pause recording" feature (GPS + POI database).

### 6.4 Lessons from prior products (brief)

- Early smart canes (I-Cane Mobilo 2013) failed on: poor battery, high false-alarm rate, indoor echo confusing ultrasound. **Lesson: an ETA must survive real streetscapes, not just lab corridors.**
- Multiple VR-vendor "haptic shoes / haptic belts for the blind" failed in 2018–2022. Cause: long custom-hardware cycles, narrow market, high prices. **Reaffirms our "off-the-shelf only" principle.**

---

## 7. Out of scope (briefly)

The following directions are **explicitly excluded** and not discussed further:

1. **Pure custom-hardware route** — long cycle, high risk, conflicts with "fastest validation."
2. **Jetson-based heavy edge box for MVP** — phone already sufficient, adds heat source + battery burden.
3. **Joy-Con haptic** — IMU feedback flood problem unsolvable.
4. **External LiDAR / ToF depth cameras** — 2024–2026 monocular depth is sufficient for navigation; external hardware breaks the "wireless + off-the-shelf" rule.
5. **Indoor navigation requiring pre-installed infrastructure (beacons / RFID)** — scope-limited, cannot generalize to streets.
6. **Pure SLAM mapping route** — slow cold start on unknown environments, texture-dependent — wrong fit for outdoor general navigation.
7. **Closed-ecosystem smart glasses** — ByteDance Doubao, Baidu Xiaodu, Huawei glasses with no open camera SDK, regardless of hardware quality.

---

## 8. Competitive landscape (2025–2026)

| Product | Form | Core tech | Price | Note |
|---|---|---|---|---|
| **Envision Glasses + Ally Solos** | Monocular smart glasses + AI assistant | OCR, object recognition, Be My Eyes video call, Ally LLM assistant | ~$3500 | Strong on text/object; navigation weak |
| **biped** | Shoulder-mounted "guide headphone" | 3D camera + AI, 10 m obstacle detection, haptic + GPS routing | Several $1000s | One of few real obstacle-avoidance products; hardware heavy |
| **.lumen Glasses** | Head-worn + haptic feedback | Computer vision + head haptics, "autonomous-driving-style" pedestrian guidance | €5000–10000 | CES 2025 award; plans 10000 units cumulative by 2026; high price, EU-focused |
| **WeWALK Smart Cane** | Smart white cane | Ultrasound + Microsoft Moovit routing + haptic handle | < flagship phone | Augments cane rather than replacing; complementary to Roana |
| **OrCam MyEye** | Clip-on to regular glasses | Text reading, object/face recognition | $3500–4500 | Strong on reading; almost no obstacle avoidance |
| **Meta Ray-Ban + Be My Eyes** | Regular smart glasses + remote human | Camera + remote volunteer description | $299–499 | APH ConnectCenter (2026-03): Be My Eyes has ~1M visually-impaired users + 10M sighted volunteers — the de facto "remote vision" channel |

**Roana's differentiation:**
- **Price:** V2 complete kit can be controlled to **¥5000–8000**, far below Envision / .lumen / OrCam;
- **Openness:** pure off-the-shelf combination, every element replaceable;
- **Obstacle-avoidance focus:** same lane as biped but at 1/5 the cost, using "phone compute + monocular depth" instead of dedicated 3D camera;
- **Integration path:** can stand alone as an "obstacle-avoidance augmentation module" for Be My Eyes / Ally / WeWALK users — doesn't force replacement of their core functionality.

---

## Appendix A — V0 minimal Demo pseudocode

```python
# Android side could use Chaquopy or pure Kotlin equivalent; this is for illustration
import cv2, time
from ultralytics import YOLO
from depth_anything_v2.dpt import DepthAnythingV2

yolo = YOLO("yolo11n-seg.tflite")
depth = DepthAnythingV2(encoder="vits")  # Small
cap = cv2.VideoCapture(0)
tts = AndroidTTS()  # wrapper around Android TextToSpeech

state = "FORWARD"
while True:
    ok, frame = cap.read()
    if not ok: continue

    det = yolo(frame)[0]                          # detection + segmentation
    dmap = depth.infer_image(frame)               # relative depth 0–1
    walkable_mask = det.masks.data[CLASS_WALKABLE]

    # downsample depth + walkable to 15x15
    grid = downsample_combine(dmap, walkable_mask, 15, 15)
    path = dfs_longest_safe_path(grid, start=(14, 7))
    direction = path_to_direction(path)          # "LEFT" / "STRAIGHT" / "RIGHT" / "STOP"

    # emergency override
    if min_obstacle_distance(dmap, walkable_mask) < EMERG_THRESH:
        direction = "STOP"

    # state machine + throttling
    if direction != state and confirm_3_frames(direction):
        state = direction
        if state == "STOP":
            tts.flush_and_speak("Stop")
            bangle_buzz_both(strong=True)
        elif state in ("LEFT", "RIGHT"):
            tts.speak({"LEFT":"Left","RIGHT":"Right"}[state])
            bangle_buzz_side(state)

    time.sleep(0.05)  # cap at ~20 FPS
```

---

## Appendix B — Development priorities and milestones

| Stage | Duration | Key deliverable | Go/No-Go metric |
|---|---|---|---|
| V0 | 1–2 weeks | Phone-only demo; blindfolded user walks a known corridor | Pipeline ≥10 FPS; no thermal throttling in 30 min continuous |
| V1 | +1 week | Bone-conduction headset added; demoable on noisy street | TTS BT latency <200 ms; environmental sound not masked |
| V2 | +2–3 weeks | Bangle×2 added; complete two-channel feedback | User internalizes haptic semantics in 1 h; multi-device BLE stable |
| V3 | +1–2 months | Mentra Live glasses integrated | Video stream E2E <300 ms; algorithm code runs with zero modification |

---

**Document version:** V1.0 / 2026-05
**For:** engineering team, product decision-makers
**Next-update triggers:** V0 measurement feedback, or breaking changes in major SDKs / hardware.
