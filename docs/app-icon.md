# 应用图标：极简终端

从 v0.1.1 起采用 B 方案：暖白圆角底板、黑色刘海、白色终端提示符与珊瑚红状态点。应用图标、首次引导和设置中的图标预览使用同一设计。

图标由内置 `image_gen` 生成并修整透明边缘。导出时通过原生 CoreGraphics 套用标准透明圆角轮廓，保留内部图案，避免生成图边缘的零散像素。PNG 和图标配置均随源码发布；候选草稿只保存在本地。

最终 1024 像素图标位于 `boringNotch/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`。图标集包含 macOS 的 16、32、128、256、512 pt 及各自 2x 表示。

选定 B 方案后使用的修整提示词：

> Make ONLY the alpha silhouette clean and production-ready. Remove stray isolated white specks, thin white fringes, ragged alpha edges and detached pixels outside the warm ivory rounded-square tile. Keep the outside transparent. Preserve the composition, proportions, warm ivory tile, central charcoal notch, thick white terminal chevron, short white cursor, coral-red status dot and subtle internal shadow. Do not redesign, recolor, move or add decoration.

如果再次使用 B 的原始生成稿导出，请从仓库根目录运行：

```sh
xcrun swift scripts/export-app-icon.swift /path/to/selected-B.png
```

导出脚本的透明轮廓针对 B 原稿的留白比例设置，其他图标设计需要先调整轮廓参数。
