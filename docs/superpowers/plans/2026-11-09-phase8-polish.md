# Kadraj Faz 8 — Cila: Güncelleme + Girişte Başlat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Uygulama içinden admin'siz güncelleme; girişte başlatma; dokümantasyon.

**Architecture:** Core: `SemanticVersion` (karşılaştırma, `v` öneki, prerelease), `ReleaseInfo` (GitHub `releases/latest` JSON). Uygulama: `Updater` — menü "Güncellemeleri Kontrol Et" → yeni sürüm varsa toast "Güncelle" → `Kadraj.zip` + `.sha256` indir, SHA-256 doğrula (CryptoKit), `ditto` ile aç, çalışan `.app`'in yerine koy (yazılabilir klasördeyse), yeniden başlat; yazılamıyorsa curl komutunu öner. Ayarlar: "Girişte başlat" (`SMAppService.mainApp`).

## Global Constraints
- Ağ çağrısı yalnız kullanıcı "Güncellemeleri Kontrol Et" dediğinde (otomatik kontrol yok).
- Geliştirme sürümleri (`0.0.0-dev`, `0.0.0-nightly.*`) güncellemeyi "geliştirme sürümü" diye atlar ve curl `main` komutunu önerir.
- SHA uyuşmazsa hiçbir şey değiştirilmez.

### Task 1: Core
- [ ] Tests: `1.10.0 > 1.9.2`, `v1.2.0 == 1.2.0`, `1.2.0 > 1.2.0-beta.1`, `0.0.0-nightly.ab12 < 0.1.0`, geçersiz `"abc"` → nil; ReleaseInfo örnek JSON → tag `v1.2.0`, `zipURL` ve `checksumURL` doğru asset'ler, draft/prerelease alanları; eksik asset → nil.
- [ ] Implement → PASS → commit.

### Task 2: Uygulama
- [ ] `Updater`, menü öğesi, toast akışı, "Girişte başlat" ayarı, README. Doğrula: sahte `KADRAJ_UPDATE_BASE`? — Hayır: API yanıtı yokken (henüz release yok) "Yayınlanmış sürüm bulunamadı" toast'u; geliştirme sürümünde "geliştirme sürümü" mesajı; ayar anahtarı SMAppService durumunu yansıtır. Commit.
