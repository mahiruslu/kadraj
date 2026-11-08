# Kadraj Faz 7 — Renk Seçici + Cetvel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ekrandan renk seçip panoya kopyalamak; ekranda mesafe/boyut ölçmek.

**Architecture:** Core: `ColorFormat` + `ColorFormatter.string` (HEX/RGB/HSL), `RulerFormatter.label` — test edilir; `CaptureSettings.colorFormat` (varsayılan HEX). Uygulama: `NSColorSampler` (izin gerektirmez) → panoya + toast; cetvel = seçim overlay'inin `.ruler` amacı (bırakınca ölçüm kalır, Return/✓ "W × H" kopyalar, Esc kapatır).

## Global Constraints
- Kısayollar: `⌥⇧C` renk (kVK C = 8), `⌥⇧M` cetvel (kVK M = 46). URL `kadraj://capture/color`, `kadraj://capture/ruler`.
- Renk sRGB'ye çevrilir; HEX büyük harf `#RRGGBB`; RGB `rgb(255, 59, 48)`; HSL `hsl(3, 100%, 59%)` (yuvarlanmış).
- Cetvel etiketi: `320 × 180 pt · 640 × 360 px`.

### Task 1: Core
- [ ] Tests: `#FF3B30` / `rgb(255, 59, 48)` / `hsl(3, 100%, 59%)` (FF3B30 için); siyah `hsl(0, 0%, 0%)`; beyaz `#FFFFFF`; `RulerFormatter.label(CGSize(320,180), scale: 2) == "320 × 180 pt · 640 × 360 px"`; settings `colorFormat` varsayılan `.hex`, eski kayıt → `.hex`; kısayol testleri.
- [ ] Implement → PASS → commit.

### Task 2: Uygulama
- [ ] Renk seçici + toast (renk örneği simgesiyle), ayarlarda biçim seçimi, cetvel overlay amacı, menü öğeleri, README. Doğrula: cetvelde sürükleme etiketi ekran görüntüsü; Return → pano `W × H`. Renk seçici: sentetik tıklama ile sampler'dan renk alınır, pano HEX içerir. Commit `feat: color picker and ruler`.
