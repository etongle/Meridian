# Meridian brand assets

Meridian means a line of longitude: a fitting reference to places connected by time.

- `Resources/AppIcon.png`: transparent, high-resolution source icon.
- `docs/assets/app-icon.png`: website icon, from the same source.
- `docs/assets/promo-en.png`: English launch poster.
- `docs/assets/promo-zh.png`: Chinese launch poster.
- `docs/assets/widget.png`: native application screenshot; example time and weather.

Builds generate all macOS icon sizes and AppIcon.icns using `scripts/build-icon.sh`. The menu bar uses the same application icon, reduced to 18 points, instead of the previous globe.

## Palette

Midnight graphite, ice blue and champagne gold. Interface text uses native system fonts.

## Generation notes

Built-in image generation was used, followed by a transparent-background edit for the icon. The product screenshot was captured from the native SwiftUI/AppKit application.

### App icon prompt

A premium macOS world-clock app icon for Meridian: an obsidian rounded-square tile, midnight-blue spherical clock, gold meridian arc and clock hands, ice-blue orbital ring. Soft dimensional glass lighting, simple recognizable silhouette, no text or extra objects. Transparent outside the tile; keep the tile opaque.

### English poster prompt

Premium 16:9 dark editorial launch artwork. Preserve the official icon and actual four-clock product screenshot. Midnight charcoal, an ice-blue planetary horizon and a champagne-gold sunrise. Exact copy: “Meridian”, “Your world. At a glance.”, “World clocks. Full dates. Local weather.”, “Built for macOS”. No prices, awards or store badges.

### Chinese localization prompt

Preserve the icon, composition, product screenshot and colors. Translate only marketing copy to “世界此刻。一眼尽览。”, “多时区时钟 · 完整日期 · 当地天气”, and “为 macOS 设计”. Keep the product’s default-English interface unchanged.
