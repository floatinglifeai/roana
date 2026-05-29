# Build and Distribution — Docker-based Headless Build + Google Play / Xiaomi / Huawei

> How to build a native Kotlin Android app in a Docker container without installing Android Studio IDE, deploy locally via adb, and (eventually) distribute through Google Play, Xiaomi App Store, and Huawei AppGallery. Honest about the compliance gap between Google Play and Chinese stores.

---

## TL;DR

- **Docker no-IDE build is technically feasible and recommended.** Android build only needs JDK 17 + Android SDK command-line tools + Gradle Wrapper (+ NDK/CMake for TFLite/ONNX native libs); Android Studio IDE is not required. Use `cimg/android:2026.03-ndk` and run `./gradlew assembleRelease / bundleRelease` in the container; the .apk/.aab is mounted back to host; host's locally-installed `platform-tools` (adb, tens of MB) does `adb install` to a real device.
- **On Linux dev machine (the chosen path): native x86_64 = clean.** Android command-line tools and NDK ship native `linux-x86_64` binaries; on Linux you can even skip Docker entirely and install the toolchain directly. Docker still useful for reproducibility across machines and CI.
- **On Apple Silicon Mac (alternate contributor path): "works but with cost."** Mainstream build images are `linux/amd64` single-arch; must enable Docker Desktop 4.25+ or Colima Rosetta acceleration. Per Patrick Thomas's *"Apple Silicon Docker amd64/x86 emulation via Rosetta is fast(er)"* (patrickwthomas.net/macos-docker/, 2023) Prime Sieve benchmark: native 26s, Rosetta 32s, QEMU 254s — *"Rosetta ran roughly 20% slower than native, and QEMU ran around 85% slower than native"* (~9.8× slower under QEMU). Pure QEMU has occasional aapt2/clang crashes.
- **Chinese app store compliance costs far exceed code-writing.** Google Play: one-time $25 + Data safety + target API 35 + foreground service declaration. **Xiaomi since late 2024 only accepts enterprise developers**, and both Xiaomi and Huawei mandate Software Copyright Certificate (软著) + MIIT App filing. This app's camera + Bluetooth + location + foreground service combination gets scrutinized.
- **Recommended path: first use `adb install` for self-test, target Google Play as the first formal distribution channel; defer Chinese stores until a corporate entity exists.**

---

## Key Findings

| Dimension | Conclusion |
|---|---|
| Is Android Studio required | **No.** Command-line tools + Gradle Wrapper sufficient; IDE is just an editor (VSCode/Cursor + Claude replaces it) |
| Recommended image | `cimg/android:2026.03-ndk` (NDK r26 LTS, CMake 3.22.1, JDK 17; CircleCI-maintained, monthly updates) |
| Linux build | Native x86_64; can skip Docker entirely if desired |
| Apple Silicon build | No native arm64 Android build image; must run amd64 under Rosetta; emulator can't run in container → **adb stays on host** |
| Google Play | $25 one-time, must be .aab, target API ≥35 (Android 15, enforced 2025-08-31), Data safety form required, foreground service type declared in Play Console |
| Xiaomi App Store | **Enterprise developers only since 2024;** software copyright + App filing + ICP required |
| Huawei AppGallery | Individual / enterprise both work, sensitive apps need bank card / corporate-account verification; software copyright + filing + privacy policy URL required; no GMS dependency means no Huawei-side adaptation burden |
| China MIIT App filing | Mandatory since 2024-04: subject docs, APK signature, domain, China cloud server, 20 working-day review |
| Risk ranking | **Xiaomi > Huawei > Google Play** (Xiaomi individual-subject blocker is biggest) |

---

## Part One: Docker-based No-IDE Native Android Build

### 1.1 Clarifying: IDE, SDK, and Gradle are three separate things

Many people unconsciously equate "doing Android development = installing Android Studio." Decomposed:

- **Android Studio:** IDE based on IntelliJ IDEA — code editor, visual layout, debugger, profiler. **Essentially a graphical editor + Gradle invoker.**
- **Android SDK Command-Line Tools (`cmdline-tools`):** Google's separate package with `sdkmanager` (download/manage SDK components), `avdmanager`, etc. Per official docs:
  > *"The sdkmanager tool is provided in the Android SDK Command-Line Tools package... If you don't have Android Studio installed, or it is for a CI server or other headless Linux device without a GUI installed, do the following from the command-line..."*
  > — developer.android.com/tools/sdkmanager
- **Actual build dependencies:** JDK 17 + `platform-tools` (adb) + `build-tools;<version>` (aapt2, d8, apksigner) + `platforms;android-35` + Gradle (via project's Gradle Wrapper `./gradlew` — no system install needed) + NDK + CMake (only for native libs).

**Key fact:** AGP 8.x+ requires **JDK 17** to run Gradle Daemon. Gradle official: *"A JVM version between 17 and 26 is required to execute Gradle."* (docs.gradle.org)

For this project's TFLite/ONNX inference: the TFLite Android AAR includes JNI prebuilt `.so`, so usually no NDK needed; if writing JNI (custom ops, OEM NPU SDKs), then yes. Default install NDK in case.

### 1.2 Off-the-shelf Android Build Images (2026)

| Image | Maintainer | Size | NDK | arm64 manifest | Recommendation |
|---|---|---|---|---|---|
| **`cimg/android:2026.03-ndk`** | CircleCI official | ~6 GB | ✅ NDK r26 LTS + CMake 3.18/3.22 | ❌ `linux/amd64` only | ⭐⭐⭐⭐⭐ |
| `mingc/android-build-box:latest` | Community | ~16 GB | ✅ | ❌ amd64 only | ⭐⭐⭐ (includes Flutter, too heavy) |
| `thyrlian/android-sdk` | Community | ~3 GB | Self-install | ❌ amd64 only | ⭐⭐⭐ (lightweight, manual install) |
| Custom Dockerfile | DIY | ~3 GB | Optional | ✅ multi-arch possible | ⭐⭐⭐⭐ (advanced) |

CircleCI's GitHub repo `CircleCI-Public/cimg-android` `build-images.sh` **explicitly only pushes `linux/amd64`**:
```
docker build --file 2026.03/ndk/Dockerfile -t cimg/android:2026.03.1-ndk \
  -t cimg/android:2026.03-ndk --platform linux/amd64 --push .
```

### 1.3 Apple Silicon Reality

Google's official Linux Android command-line tools download is only `commandlinetools-linux-<build>_latest.zip` (x86_64 ELF) — **no linux-arm64**. NDK same. NDK maintainer (groups.google.com/g/android-ndk): *"Why would you need to build on ARM? The NDK is designed for cross compiling..."*

So even with arm64 base, **aapt2, d8, apksigner, ndk-build remain x86_64**, must run under binfmt_misc + Rosetta/QEMU.

**Performance:**
- Docker Desktop 4.25 (2023-10) GA'd "Rosetta for Linux" (docker.com/blog/docker-desktop-4-25/): *"Near-native emulation... nearly on par with native execution... enabled by default on macOS 14.1 and newer."*
- Patrick Thomas Prime Sieve: native 26s, Rosetta 32s, QEMU 254s.
- Docker official "Known issues": *"running Intel-based containers on Arm-based machines should be regarded as 'best effort' only."*

**Expected build time (extrapolated):** mid-size project clean build amd64 + Rosetta: **8–20 min**; incremental: **1–3 min** cache-hot.

**Apple Silicon Docker acceleration (mandatory):**

Docker Desktop: Settings → General → ✅ "Use Rosetta for x86/amd64 emulation on Apple Silicon"; Resources → ≥ 8 GB memory, 4 CPU, 60 GB disk.

Or Colima:
```bash
brew install colima docker docker-buildx
colima start --cpu 6 --memory 12 --disk 80 \
  --vm-type vz --vz-rosetta --mount-type virtiofs
```

### 1.4 Why Emulator Must Stay on Host

Android Emulator needs hardware acceleration (Linux KVM, macOS Hypervisor.framework). In Docker:
1. On macOS, Docker runs in a lightweight Linux VM; container can't reach Mac's Hypervisor.framework.
2. Even with `/dev/kvm` exposed (Linux host only), Apple Silicon's arm64 system image conflicts with Rosetta — nearly unbootable.
3. budtmo/docker-android style solutions on ARM Mac are unusable or unbearably slow.

**Correct approach:**
- **Build in container** — identical artifacts on Mac and Linux.
- **adb + real device on host** — `brew install --cask android-platform-tools` (macOS) or `apt install android-tools-adb` (Linux); ~50 MB; **the only Android tool installed locally**.
- Real device dev-mode + USB debugging, then `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

### 1.5 Complete Workflow

**Recommended project layout:**
```
roana/
├── app/                            # Android module
│   ├── src/main/AndroidManifest.xml
│   ├── src/main/kotlin/...
│   ├── src/main/cpp/               # optional JNI/NDK
│   ├── src/main/assets/            # TFLite / ONNX models
│   └── build.gradle.kts
├── gradle/wrapper/                 # commit Gradle Wrapper
├── gradlew, gradlew.bat            # commit
├── build.gradle.kts
├── settings.gradle.kts
├── gradle.properties
├── local.properties                # ⚠ .gitignore
├── keystore/                       # ⚠ .gitignore
│   └── release.jks
├── Dockerfile                      # optional custom image
├── .dockerignore
└── scripts/
    ├── build-debug.sh
    └── build-release.sh
```

**Simplest approach — use cimg/android directly:**
```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$PWD":/workspace \
  -v gradle-cache:/home/circleci/.gradle \
  -w /workspace \
  cimg/android:2026.03-ndk \
  bash -c "./gradlew assembleDebug"
```

Artifact at `app/build/outputs/apk/debug/app-debug.apk`; `adb install` from host.

**Release AAB (Google Play):**
```bash
docker run --rm --platform linux/amd64 \
  -v "$PWD":/workspace \
  -v gradle-cache:/home/circleci/.gradle \
  -v "$PWD/keystore":/keystore:ro \
  -e KEYSTORE_PATH=/keystore/release.jks \
  -e KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD" \
  -e KEY_ALIAS="$KEY_ALIAS" \
  -e KEY_PASSWORD="$KEY_PASSWORD" \
  -w /workspace \
  cimg/android:2026.03-ndk \
  bash -c "./gradlew bundleRelease"
```
Output: `app/build/outputs/bundle/release/app-release.aab`.

**Release APK (Chinese stores):** swap `bundleRelease` → `assembleRelease`.

`gradle-cache` named volume avoids re-downloading hundreds of MB on every build.

### 1.6 Custom Dockerfile (optional)

```dockerfile
FROM --platform=linux/amd64 eclipse-temurin:17-jdk-jammy

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_VERSION=26.3.11579264 \
    BUILD_TOOLS_VERSION=35.0.0 \
    PLATFORM_VERSION=android-35

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl unzip git ca-certificates && rm -rf /var/lib/apt/lists/*

RUN mkdir -p $ANDROID_HOME/cmdline-tools && \
    curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
      -o /tmp/cmdline.zip && \
    unzip -q /tmp/cmdline.zip -d $ANDROID_HOME/cmdline-tools && \
    mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest && \
    rm /tmp/cmdline.zip

ENV PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

RUN yes | sdkmanager --licenses && \
    sdkmanager \
      "platform-tools" \
      "platforms;${PLATFORM_VERSION}" \
      "build-tools;${BUILD_TOOLS_VERSION}" \
      "ndk;${ANDROID_NDK_VERSION}" \
      "cmake;3.22.1"

WORKDIR /workspace
```

### 1.7 Signing: debug auto, release manual

**Debug:** Gradle auto-uses `~/.android/debug.keystore`. No management needed.

**Release Keystore (one-time generation):**
```bash
docker run --rm -v "$PWD/keystore":/out cimg/android:2026.03-ndk \
  keytool -genkey -v -keystore /out/release.jks \
  -keyalg RSA -keysize 2048 -validity 36500 \
  -alias roana-release \
  -storepass 'PUT_STRONG_PASSWORD' -keypass 'PUT_STRONG_PASSWORD' \
  -dname "CN=Your Name, O=Personal, C=CN"
```

**`release.jks` is the lifeline** — losing it = users must uninstall-reinstall to get updates. Backup ≥ 2 copies (USB + encrypted cloud). Never commit. Passwords in password manager.

**Gradle injection** in `app/build.gradle.kts`:
```kotlin
android {
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("KEYSTORE_PATH") ?: "../keystore/release.jks")
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = System.getenv("KEY_ALIAS")
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
```

**Google Play App Signing (recommended):** uploaded AAB signed with **upload key**; Play re-signs in cloud with Google-held **app signing key**. Lose upload key → contact Play to reset. **Huawei/Xiaomi have no equivalent** — you self-keep.

### 1.8 Gradle Cache Tuning

```properties
# gradle.properties
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=true
android.useAndroidX=true
android.enableJetifier=false
kotlin.code.style=official
```

**First-time:** clean build 8–20 min; incremental 30s–3min. Use virtiofs on macOS (Colima `--mount-type=virtiofs`, Docker Desktop default).

### 1.9 CI/CD Extension — GitHub Actions

Move to **GitHub Actions** (`ubuntu-latest` is native x86_64 Linux, 2–3× faster than local Mac):

```yaml
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    container: cimg/android:2026.03-ndk
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: ~/.gradle
          key: gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
      - run: ./gradlew assembleDebug bundleRelease
        env:
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
      - uses: actions/upload-artifact@v4
        with: { name: artifacts, path: app/build/outputs/ }
```

Per docs.github.com/billing: public repo standard hosted runners free with no cap; GitHub Free private repo 2000 min/month; GitHub Pro 3000 min/month. 2026-01-01 GitHub cut hosted-runner prices up to 39%. Plenty for personal projects.

---

## Part Two: Three-Store Submission Requirements

### 2.0 Cross-Store Comparison

| Dimension | Google Play | Xiaomi | Huawei |
|---|---|---|---|
| Developer fee | **$25 one-time** | Free | Free |
| Individual | ✅ (with ID + 12-tester closed test) | ❌ **Stopped individual registration since 2024** | ✅ (individual / enterprise both) |
| Subject auth | Govt ID + phone | Enterprise only | Individual: ID + bank card; Enterprise: corporate transfer; **sensitive apps require bank card / corporate transfer** |
| Software copyright | Not required | **Required** | **Required** |
| MIIT App filing | Not required | **Required** | **Required** |
| ICP filing | Not required | **Required** | Required |
| Upload format | `.aab` mandatory (since 2021) | `.apk` | `.apk` |
| Target SDK | **API 35 (Android 15)**, enforced 2025-08-31 | Less strict | Same as Google |
| App signing | Play App Signing (cloud key) | Self-managed | Self-managed |
| Privacy policy URL | Required | Required (strict MIIT [2023] 26) | Required |
| Sensitive perm review | Data safety + foreground decl + video | Strict + popup purpose | Extremely strict, "minimum principle" |
| Review cycle | 1–7 days | 1–3 days | 1–3 days |
| GMS dependency | Use directly | Doesn't matter | **Cannot embed GMS deps** |

### 2.1 Google Play (easiest)

**Account registration:**
- One-time $25 USD; lifetime valid.
- **Personal** vs **Organization**: solo dev → Personal; later organize → D-U-N-S needed.
- Real-name mandatory since 2024.
- **Personal account Closed Testing rule** (support.google.com/googleplay/android-developer/answer/14151465): *"If you have a newly created personal developer account, you must run a closed test for your app with a minimum of 12 testers who have been opted-in for at least the last 14 days continuously."* Applies to accounts created after 2023-11-13; was 20, dropped to 12 in 2024-12. **$25 ≠ instant publish**; 14-day closed test is a hard gate.

**Target API Level (mandatory from 2025-08-31):**
> *"New apps and app updates must target Android 15 (API level 35) or higher to be submitted to Google Play; existing apps must target Android 14 (API level 34) or higher to remain available to new users..."*

```kotlin
android {
    compileSdk = 35
    defaultConfig {
        minSdk = 26     // Android 8.0+; CameraX, ML, foreground service all mature
        targetSdk = 35
    }
}
```

**Foreground service declaration (Android 14+ mandatory, Play 2024-08-31 enforced):**

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />

<service
  android:name=".NavigationForegroundService"
  android:foregroundServiceType="camera|connectedDevice"
  android:exported="false" />
```

In Play Console "App content" → "Foreground services" submit declaration: user-visible purpose for each type + demo video.

**Data safety form** (required). For this app:
- Location → Approximate / Precise (navigation)
- Camera & Microphone → "App functionality"
- App activity → user interactions
- Device IDs → if using Crashlytics/Analytics

**Strong recommendation: process camera frames locally, don't upload.** Then Data safety = "Not collected" or "App functionality, processed on device" — extremely friendly review. Per Google Security Blog 2026-02-19: *"In 2025, we prevented over 1.75 million policy-violating apps from being published on Google Play and banned more than 80,000 bad developer accounts."* Don't hide things.

**Accessibility-class app bonus:**
> *"Note: Verified accessibility tools identified with the isAccessibilityTool='true' flag are not subject to these restrictions..."*
> — support.google.com/googleplay/android-developer/answer/10964491

If using `AccessibilityService` API: declare `isAccessibilityTool="true"`, submit accessibility tool declaration in Play Console (with demo video). Partial sensitive permission exemption. **But:** store description must clearly state "primarily serves disabled users." Vague "general AI assistant" won't pass.

**Medical device red line:** This app is **assistive navigation tool**, doesn't "diagnose, prevent, monitor, or treat." Keep marketing free of "diagnose vision," "treat blindness," "medical replacement." Won't be classified as SaMD. Use "assistive mobility / accessibility tool," avoid "medical," "health monitoring."

### 2.2 Xiaomi App Store (individual developers **dead end**)

**Fatal change:**
- Since 2024, Xiaomi App Store **no longer accepts individual + sole-proprietor registration** — **enterprise developers only**. Source: V2EX, CSDN, LandianNews, multiple independent reports + Xiaomi Open Platform registration page.
- Existing individual accounts asked to convert to enterprise.

**If you can get enterprise qualification (~1000-3000 yuan to register an Ltd.):**

1. **Enterprise account:** business license, corporate account, legal rep ID.
2. **Software Copyright Registration Certificate (软著):**
   - DIY: free but slow, 3+ months.
   - Agent: 300–800 yuan, 30–60 days (express 3–10 business days for 1000–3000 yuan).
   - Must match app name + corporate name.
3. **MIIT App filing** (see §2.4).
4. **ICP filing**: subject matches developer.
5. **Privacy policy** strictly compliant with MIIT [2023] 26.

**Sensitive permission review (this app is high-risk):**
- No personal info read before user accepts privacy policy on first launch.
- "Audio/camera/location" permission requests must popup explaining purpose.
- Background sensitive permission calls: MIUI shows floating prompt + notification.
- Privacy policy must declare **all third-party SDK** behaviors.

### 2.3 Huawei AppGallery (individual OK, but sensitive apps high bar)

- Free registration, real-name required.
- Individual developers: sensitive apps (camera/audio/location) require **bank card auth** (manual ID review not accepted).
- Enterprise: corporate-account small-amount (< 1 yuan) transfer auth.

**Same hard requirements:**
- Software Copyright Certificate — required.
- MIIT App filing number — required.
- Privacy policy URL — required (Huawei offers free AppGallery Connect cloud hosting).
- App package name **cannot be changed after publish**.

**Review characteristics:**
1. Permission "minimum" principle extremely strict.
2. Reviewer actually tests on a real device.
3. Age-rating questionnaire required.
4. Review cycle 1–3 business days.

**GMS dependency impact (key for this app):**

Huawei phones (Mate 30+, post 2019-05) **have no Google Mobile Services**. Implications:
- ❌ `com.google.android.gms:play-services-location`
- ❌ `com.google.mlkit:*`
- ❌ `com.google.firebase:*` with FCM/Analytics
- ❌ Google TextToSpeech (depends on Google service)

**Recommendation — minimize GMS dependency:**
- **Location:** use AOSP `LocationManager` directly (cleanest), or AMap / Baidu Maps SDK if needed.
- **TTS:** use Android system `android.speech.tts.TextToSpeech` (Huawei devices have Huawei TTS, Xiaomi has Xiaomi TTS — all good). Don't hard-code Google TTS.
- **Vision models:** TFLite/ONNX on-device — unrelated to GMS, ✅ safe.
- **Crash reporting:** avoid Firebase Crashlytics; use Sentry, Bugly (Tencent), or self-host.
- **NPU acceleration:** general solution is NNAPI delegate (TFLite-built-in); on Huawei consider HUAWEI HiAI Foundation.

One codebase + one artifact works on all three stores.

### 2.4 MIIT App Filing (China mandatory)

- MIIT 2023-08 *Notice on Mobile Internet Application Filing*.
- **New apps from 2023-09-01: must file before listing.**
- **Existing apps must complete by 2024-04-01**.
- Individual AND enterprise developers both file.

**Process (~3–22 business days):**
1. **Prerequisites:**
   - Subject docs (ID / business license).
   - A domain (ICP-filed), ~50 yuan/year.
   - A China cloud server (provides "filing service code"): Alibaba/Tencent/Huawei Cloud lightweight server, 2C2G, ~80–100 yuan/first-year. You don't have to actually run a service — it's a compliance credential.
2. **Submit:** via cloud-provider filing system (Alibaba/Tencent/Huawei Cloud):
   - Subject info;
   - App info: name, icon, Bundle ID (package name), **APK public key + signature MD5** (extract from signed release APK — biggest newbie pitfall);
   - Domain, IP, access info;
   - Network service provider commitment letter.
3. **Platform initial review** (1–2 days, cloud-provider phone verification).
4. **MIIT SMS verification** (within 5 min, verify within 24 hours).
5. **Provincial Communications Administration review** (max 20 days, typical 3–7).
6. **Filing number issued**, must display prominently in app, clickable to MIIT filing query page.

**Extract APK signature info:**
```bash
keytool -printcert -jarfile app-release.apk | grep -E 'MD5|SHA1'
# or modern:
apksigner verify --print-certs app-release.apk
```

This app isn't news/publishing/education/film/religion — **no pre-approval needed**.

### 2.5 Individual vs Enterprise Subject

| Channel | Individual OK | Note |
|---|---|---|
| Google Play | ✅ | Standard choice |
| Huawei AppGallery (China) | ✅ but sensitive needs bank card | Copyright, filing required |
| Xiaomi | ❌ | Enterprise mandatory |
| OPPO | ❌ | Enterprise mandatory |
| vivo | ❌ | Enterprise mandatory |
| Tencent MyApp | ✅ partial categories | Copyright required |
| Coolapk | ✅ | Most individual-friendly, but small reach |

**If only one Chinese channel: Huawei.** Large install base, friendly to individual developers. For Xiaomi/OPPO/vivo: registering an Ltd. is unavoidable (~1000–3000 yuan + ~200–500 yuan/month accounting).

### 2.6 Visually-Impaired Assistive App Qualification Risk

**Key question:** classified as medical device or special license required?

- Per China's *Regulations on Supervision and Administration of Medical Devices* and NMPA *Medical Device Classification Catalog*, "medical devices" mean products for **diagnosis, prevention, monitoring, treatment, or relief**. **Pure assistive mobility tools (obstacle detection, road condition announcement) are not in the medical device catalog.**
- **Forbidden words** in store description, privacy policy, marketing: diagnose, treat, medical, rehabilitate (in physical-therapy sense), correct vision, replace physician.
- **Correct framing:** assistive mobility tool / accessibility navigation tool / visual aid tool / environmental perception tool.
- **Xiaomi/Huawei review:** may request a "not a medical device" statement or similar undertaking — common for enterprise subjects, less common for individuals.
- **Insurance measure:** prominent in-app disclaimer: *"This app is only an assistive tool. It cannot replace vision, cannot replace the white cane, cannot replace professional medical advice or vision rehabilitation services..."*; reference NFB / RNIB public-service framings.

Accessibility tools are **not discriminated against** by Chinese / global stores — actually encouraged. But position clearly as "accessibility tool," not "medical product."

### 2.7 Sensitive Permission Notes (China review)

| Permission | Risk | China review focus |
|---|---|---|
| `CAMERA` (continuous) | 🔴 Extremely high | Foreground service required, user-visible notification required, explain "uploads or not" (locally processed best); privacy policy must state "images processed locally only, not retained, not uploaded" |
| `RECORD_AUDIO` | 🟡 Medium | Not needed for TTS feedback; only if voice control |
| `BLUETOOTH_*` | 🟡 Medium | Android 12+ requires `BLUETOOTH_CONNECT` / `_SCAN` runtime permissions; scanning must explain why |
| `ACCESS_FINE_LOCATION` | 🔴 High | "Navigation" is legitimate, but must explain precise location necessity; offer "while using only" |
| `FOREGROUND_SERVICE_*` | 🔴 High | Must declare by type; notification must clearly show what's happening ("Navigating, using camera") |
| `ACCESS_BACKGROUND_LOCATION` | 🟠 Extremely high | Heavily scrutinized China and global; **don't request unless absolutely necessary** — foreground service + while-using is enough |

**Unified principles:**
1. **Runtime requests** — never permission-on-default in manifest.
2. **Delayed requests** — first launch shows only privacy policy popup; permission requests when entering corresponding function.
3. **Clear purpose** — dialog before each permission request explaining why and what happens without.
4. **Reversible** — in-app "Permission management" entry linking to system settings.

---

## Part Three: End-to-End Distribution Roadmap

### 3.1 Phased Roadmap

```
Phase 0  Local setup (1 day)
├── Install Docker Desktop (enable Rosetta) or Colima [Mac]
│   OR install command-line toolchain directly [Linux]
├── Host install platform-tools (adb)
├── Real device dev mode + USB debugging
└── Prepare Claude Code / Cursor / VSCode

Phase 1  Develop + self-test (weeks to months as needed)
├── Claude writes Kotlin (CameraX, BLE, TFLite/ONNX, foreground service, TTS)
├── docker run ... ./gradlew assembleDebug
├── adb install app-debug.apk → real device → logcat → back to Claude
└── No account / filing / copyright / privacy policy needed this phase

Phase 2  Google Play submission (2–4 weeks)
├── Generate release keystore
├── Prepare icon / screenshots / description / privacy policy (GitHub Pages static)
├── Register Play Console ($25), ID verification
├── Configure Data safety, foreground service declaration, accessibility tool declaration
├── bundleRelease → upload AAB → Closed Testing (12 testers × 14 days)
└── Production release → 1–7 days review → live ✅

Phase 3  China compliance (decide whether to pursue)
Branch A: skip Chinese stores
└── Only website / GitHub Releases APK, users sideload manually
Branch B: pursue Chinese stores
├── Apply software copyright (DIY 3 months / agent ¥500–1500 30 days)
├── Register domain + China cloud server (¥150/year)
├── Submit MIIT App filing → 3–22 business days
├── Register Huawei developer account (individual OK) → submit review
└── For Xiaomi/OPPO/vivo → register Ltd. → copyright re-issued → submit
```

### 3.2 Self-use vs Distribution Boundary

**Pure self-use (adb install):** **NO account, filing, copyright, compliance needed.** Build with this Docker flow → install to your own and a few testers' real devices → iterate freely. **No cost, no gate.** This is critical difference from iOS (iOS needs $99/year Apple ID for 7+ day device install).

**Formal distribution:** faces accounts, store review, filing, copyright, privacy compliance.

**Strong recommendation:** in Phase 1 nail core function reliability (vision recognition accurate, announcement timely, BLE stable) — this is the heart of a blind-assist app. Then think about listing.

### 3.3 Risk and Pitfall Checklist

#### Technical pitfalls (Docker / build side)

1. **Apple Silicon Rosetta not enabled** → first `docker pull cimg/android` slow and build extremely slow. Enable Rosetta in Docker Desktop settings.
2. **JDK version wrong** → AGP 8.x+ requires JDK 17; `Android Gradle plugin requires Java 17 to run`.
3. **Gradle Wrapper not committed** → every fresh clone needs manual init. **`gradle/`, `gradlew`, `gradlew.bat` must commit.**
4. **Target SDK lag** → since 2025-08-31, targetSdk=35 required to submit new versions to Play.
5. **Foreground service type undeclared** → Android 14+ starting FGS without type → `MissingForegroundServiceTypeException`, crash.
6. **Release keystore lost** → users must uninstall-reinstall to get new versions. Lifelong reputation damage. Double-backup.
7. **Gradle cache volume accidentally deleted** → always use named volume `-v gradle-cache:...`, not `--rm` that loses on delete.
8. **`.dockerignore` missing** → `build/`, `.gradle/`, `*.apk` should be in `.dockerignore` to avoid 1+ GB artifacts copied into container.
9. **NDK clang segfaults under Rosetta** → if hit, switch NDK version or move release build to GitHub Actions (native x86_64).

#### Compliance pitfalls (China side)

10. **Xiaomi individual developers dead end** — confirm subject type before listing.
11. **Software copyright name mismatches app name** — review reject. Copyright name → filing → listing name three-place match.
12. **Package name immutable post-publish** — Huawei/Xiaomi treat packageName as unique app ID. Change = new app, no upgrade path. **Lock `applicationId` first.**
13. **Filing missing APK public key/signature** — filing system requires APK public key + signature MD5; extract from release-signed APK. Debug sig not accepted.
14. **Privacy policy non-compliant** — MIIT 2023 [26]: "sensitive permissions distinctly marked," "purpose/method/scope clearly stated." LandianNews reported Xiaomi rejecting apps for policy gaps.
15. **Vague accessibility-tool description** — for `isAccessibilityTool` benefit, store description must explicitly say "primarily serves visually-impaired users."
16. **Medical boundary** — never use "diagnose/treat/medical" anywhere.
17. **First-launch order** — privacy policy popup → user agrees → THEN read any info (Android ID, IMEI, location).
18. **Background permission abuse** — `ACCESS_BACKGROUND_LOCATION` almost always rejected; foreground service is enough.
19. **Third-party SDKs not listed in privacy policy** — e.g., Bugly, Sentry, Umeng — must list SDK name, fields collected, purpose.
20. **Reviewer device issues** — if reviewer uses Huawei/Xiaomi device and hits runtime crash / chaotic permission requests / model-load splash >5s, rejected. Test multiple device models before submitting.

---

## Recommendations

**Phase 1 (act now)** — product validation phase:
1. On Mac: install Docker Desktop (enable Rosetta) or Colima with `--vm-type vz --vz-rosetta`; allocate ≥ 8 GB memory.  
   On Linux: optional — skip Docker entirely, install command-line toolchain directly for fastest iteration.
2. Host install `brew install --cask android-platform-tools` (Mac) or `apt install android-tools-adb` (Linux).
3. Have Claude generate a Gradle project skeleton (you don't have to open Android Studio); `./gradlew wrapper` generates wrapper.
4. Run `cimg/android:2026.03-ndk` + commands above for `assembleDebug`; `adb install` to real device.
5. **Spend 1–3 months on the product**: CameraX capture + TFLite/ONNX inference + Bluetooth BLE + foreground service + TTS coupling. **Don't touch any listing/compliance work this phase.**

**Phase 2 (when product is basically usable)** — Google Play first:
6. Register Google Play Console ($25), complete ID verification.
7. Recruit ≥ 12 testers for Closed Testing (colleagues, friends, blind NGO communities — the latter is also valuable real-user feedback) — opted-in ≥ 14 days.
8. Concurrently prepare Data Safety form + foreground service declaration + accessibility tool (`isAccessibilityTool`) declaration + privacy policy (GitHub Pages static recommended).
9. Production release.

**Phase 3 (decide based on distribution need)** — three strategies:

- **Strategy A (simplest):** skip Chinese stores. Distribute via your own website + APKPure-class neutral platforms + WeChat public account download link. Caveat: blind users may struggle to sideload alone; need pairing tutorials.
- **Strategy B (medium cost):** Huawei only. Register Huawei developer (individual ✅), apply software copyright (agent 30 days ¥1500 express), apply filing (3–22 business days), align privacy policy. ~¥2000 + 1 month.
- **Strategy C (most complete):** Huawei + Xiaomi + OPPO + vivo + Tencent. **Register an Ltd. mandatorily** (~¥1500–3000, ~¥2400/year accounting). ~¥5000 + 2–3 months. Suits projects with commercial or foundation backing.

**Triggers to upgrade from A to B/C:**
- Stable 1000+ active users on Google Play with strong community feedback;
- Partnership invitation from Chinese visually-impaired organizations / Blind Association;
- Charity organization sponsoring corporate-subject registration and compliance costs;
- Project gets external funding that cannot leave the project (Chinese distribution becomes a requirement).

**Core advice:** **don't put the cart before the horse.** First make "recognition accurate, announcement timely, low battery use" so a blind friend wants to use it daily; then think about channels.

---

## Caveats

1. **Based on 2026-05 public info.** Play policies update roughly every April/August; Chinese filing/review rules also shift. Verify policy pages on each store's dev backend before formal submission.
2. **Apple Silicon Rosetta Android Gradle build speed**: this doc cites general benchmarks (Patrick Thomas 2023, claude.nl cross-arch C compile); **no 2024–2026 Android-Gradle-specific public measurements found**. After your first clean build, record your baseline as future optimization reference.
3. **NDK clang + Rosetta** has occasional segfault reports (across Go/Rust/Bun/Android NDK). Move release build to GitHub Actions (native x86_64 Linux) — free and more stable.
4. **TFLite/ONNX on-device NPU acceleration** varies by device: Qualcomm Hexagon, Huawei NPU, MediaTek APU all differ; TFLite NNAPI delegate is general but sometimes falls back to CPU. **Measure inference latency on 1–2 commonly-used blind-user device models in Phase 1** — affects product usability more than any store policy.
5. **Google Play Closed Testing 14 days × 12 people** is harder for solo developers; pair with blind community groups early; also great for usability feedback.
6. **MIIT App filing "APK public key"** must be extracted from **final release-signed APK**, not debug. Changing signing key = new app, must re-file.
7. **Xiaomi individual developer registration closure** comes from community reports (V2EX, CSDN, LandianNews multiple sources) + Xiaomi Open Platform registration page behavior; **no separate official announcement**. If latest page differs, trust the actual platform behavior.
8. **Individual developer legal liability for blind navigation app**: in actual deployment, if accident occurs (missed obstacle), can user sue developer? Chinese law has no clear precedent, but **in-app sufficient disclaimer + explicit "cannot replace cane/dog/professional training"** is essential. Strongly recommend incorporating as a foundation or company at scale to avoid unlimited personal liability.
9. **Huawei GMS absence impact**: this doc advises against hard GMS dependency. If unavoidable (Firebase Cloud Messaging), study HMS Push alternative or Unified Push Alliance — significant work, **avoid in Phase 1**.
10. **GitHub Actions CI/CD migration** is the recommended next step — free and stable. Apple Silicon Mac local build mainly for fast iteration; release build on ubuntu-latest (native x86_64) is more stable and faster.
