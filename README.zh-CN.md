<p align="center">
  <img src="assets/banner.svg" alt="Roana 漫行 - 走你自己的路" width="640" />
</p>

<h1 align="center">Roana 漫行</h1>

<p align="center">
  <em>走你自己的路。</em> 一个为盲人和低视力用户设计的开源辅助导航系统。
</p>

<p align="center">
  <a href="https://roana.app/zh/">roana.app/zh</a> ·
  <a href="README.md">English</a> ·
  <a href="mailto:talk@roana.app">talk@roana.app</a>
</p>

Roana 把智能手机，以及未来的智能眼镜，变成实时环境感知伙伴。它用端侧计算机视觉识别障碍物和可行走空间，然后通过当前的语音反馈，以及后续的触觉反馈，为用户提供导航提示。

Roana 增强白盲杖、导盲犬和定向行走训练，但不替代它们。

## 当前状态

Roana 正处于 V0 实现阶段。这个仓库里已经有原生 Android 和 iOS app。

请阅读:

- [STATUS.md](STATUS.md): 当前实现状态和下一步门禁
- [ARCHITECTURE.md](ARCHITECTURE.md): 系统架构地图
- [docs/human/](docs/human/): 面向人的后续说明

## 仓库内容

- `app/` - 原生 Android app
- `ios/Roana/` - 原生 SwiftUI iOS app
- `litert-smoke/` - 独立 Android LiteRT 验证 app
- `scripts/` - 构建、回放、真机验证脚本
- `parity/` - Android/iOS 走廊行为 parity fixtures
- `docs/` - 研究、计划、状态历史和人类说明

## 产品方向

V0 是手机形态:相机、端侧感知、走廊决策和语音反馈。

后续阶段会加入:

- 骨传导音频，保留环境声并改善隐私；
- 腕部震动，用于方向提示；
- 智能眼镜摄像头输入，同时保留同一套决策核心。

## 安全边界

Roana 不是医疗器械，不诊断、不治疗、也不治愈任何疾病。它是辅助出行原型；在目标环境的安全门禁被证明之前，测试应当有 sighted support。

## License

Roana 使用 GNU Affero General Public License v3.0
(AGPL-3.0-or-later)。见 [LICENSE](LICENSE) 和 [NOTICE.md](NOTICE.md)。

我们选择 AGPL，是为了让基于 Roana 的无障碍工作持续开放给盲人和低视力社区。

## 贡献

Roana 现在还不接受大范围代码贡献。欢迎设计反馈和测试反馈，尤其是来自盲人和低视力用户、定向行走指导师、移动 ML 工程师，以及做过无障碍软件的人。

