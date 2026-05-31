<p align="center">
  <img src="assets/banner.svg" alt="Roana - Walk your world. 漫行" width="640" />
</p>

<h1 align="center">Roana</h1>

<p align="center">
  <em>Walk your world.</em> An open-source assistive navigation system for blind and low-vision users.
</p>

<p align="center">
  <a href="https://roana.app">roana.app</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="mailto:talk@roana.app">talk@roana.app</a>
</p>

Roana turns a smartphone, and later smart glasses, into a real-time perception
companion. It uses on-device computer vision to detect obstacles and walkable
space, then gives guidance through speech now and haptics later.

Roana augments the white cane, guide dog, and orientation and mobility training.
It does not replace them.

## Current State

Roana is in V0 implementation with native Android and iOS apps in this repo.

Read:

- [STATUS.md](STATUS.md) for current implementation status and next gates
- [ARCHITECTURE.md](ARCHITECTURE.md) for the system map
- [docs/human/](docs/human/) for human-readable follow-up notes

## What Is In This Repo

- `app/` - native Android app
- `ios/Roana/` - native SwiftUI iOS app
- `litert-smoke/` - isolated Android LiteRT validation app
- `scripts/` - build, replay, and device verification gates
- `parity/` - shared Android/iOS corridor behavior fixtures
- `docs/` - research, plans, status history, and human notes

## Product Direction

V0 is phone-only: camera, on-device perception, corridor decisions, and speech
feedback.

Later stages add:

- bone-conduction audio for privacy and environmental awareness,
- wrist haptics for directional cues,
- smart-glasses camera input while preserving the same decision core.

## Safety Boundary

Roana is not a medical device. It does not diagnose, treat, or cure anything. It
is an assistive travel aid prototype and should be tested with sighted support
until its safety gates are proven for the intended environment.

## License

Roana is licensed under the GNU Affero General Public License v3.0
(AGPL-3.0-or-later). See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

We use AGPL so accessibility work built on Roana stays open to the blind and
low-vision community.

## Contributing

Roana is not yet open for broad code contributions. Design and testing feedback
are welcome, especially from blind and low-vision users, O&M instructors,
mobile ML engineers, and accessibility software builders.

