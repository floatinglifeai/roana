# NOTICE

Roana — assistive navigation system for blind and low-vision users.
Copyright (C) 2026 The Roana Authors.

This program is free software: you can redistribute it and/or modify
it under the terms of the **GNU Affero General Public License version 3**
as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

---

## Per-file copyright header

Each source file should carry the following short SPDX header. The full
license text lives in [LICENSE](LICENSE).

**Kotlin / Java / TypeScript / JavaScript:**

```kotlin
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.
```

**Python / shell / YAML:**

```python
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 The Roana Authors.
```

**C / C++:**

```c
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.
```

You do not need to repeat the warranty / full license recitation in each
file — the SPDX identifier plus the LICENSE file at the project root is
sufficient under standard SPDX conventions.

---

## Contributing — about the license you grant

By submitting a pull request, an issue with code, or otherwise contributing
to this repository, you agree that **your contribution is licensed under
the same AGPL-3.0-or-later as the rest of the project**.

You retain copyright to your contribution. The Roana project does not
require a separate Contributor License Agreement (CLA) at this stage —
AGPL itself ensures the project remains open and any derivative work
remains under the same terms.

If, at a future date, the Roana project decides to dual-license (offer a
separate commercial license alongside AGPL — e.g., to a non-profit
foundation or company that prefers different terms), all then-current
contributors would be asked individually before any such relicensing.
The current AGPL-only stance is the project's foundational commitment.

---

## Trademark

**"Roana"** and **"漫行"** are the project's names. While the code is
AGPL-licensed and freely modifiable, please do not use these names for
your fork unless you are the official project. Use a different name for
forks intended for separate distribution. This is a courtesy ask — formal
trademark registration in CN/US/EU Nice classes 9, 10, 42 is planned but
not yet completed (see `docs/research/05-domain-and-trademark.md`).

---

## Third-party components

This repository currently contains no third-party source code. When the
implementation phase begins and we add dependencies (TFLite / ONNX
Runtime models, AndroidX libraries, Espruino firmware on Bangle.js 2,
etc.), each will be listed here with its respective license.

Pre-trained models intended to be bundled with the app — notably
YOLO11n-seg (AGPL-3.0, Ultralytics) and Depth Anything V2-Small
(Apache 2.0, ByteDance Research) — will be referenced here with their
upstream licenses and any Qualcomm AI Hub redistribution terms when
they are added to the codebase.
