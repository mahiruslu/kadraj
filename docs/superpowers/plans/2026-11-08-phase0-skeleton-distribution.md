# Kadraj Faz 0 — İskelet + Dağıtım Hattı Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boş ama çalışan bir menü çubuğu uygulamasını (izin onboarding'li) imzalı/notarize edilmiş olarak GitHub Releases'e çıkarmak ve tek `curl | bash` komutuyla admin'siz kurulabildiğini kanıtlamak.

**Architecture:** SwiftPM paketi: `KadrajCore` (saf mantık, Swift Testing ile test) + `Kadraj` (AppKit executable). `.app` paketi `scripts/bundle.sh` ile her mimari ayrı derlenip `lipo` ile birleştirilerek oluşturulur (CLT'de xcbuild yok). GitHub Actions tag'de imzalar, notarize eder, `Kadraj.zip` + `.sha256` yayınlar; `install.sh` bunları indirir.

**Tech Stack:** Swift 6.x, SwiftPM, AppKit, Swift Testing, bash 3.2 (macOS'un sistem bash'i), GitHub Actions (macos-14), codesign/notarytool/stapler.

**Spec:** `docs/superpowers/specs/2026-11-08-kadraj-design.md`

## Global Constraints
- Min macOS 14 (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion` = `14.0`).
- Bundle id `com.mahiruslu.kadraj`; uygulama adı `Kadraj`; executable adı `Kadraj`.
- `LSUIElement = true` (Dock ikonu yok).
- Lisans MIT, telif sahibi "Mahir Uslu".
- `install.sh`/`uninstall.sh` hiçbir yerde `sudo` çağırmaz; sadece macOS'ta hazır araçlar: `curl`, `ditto`, `shasum`, `sw_vers`, `pkill`, `open`, `xattr`. Bash 3.2 uyumlu (associative array, `${var,,}` yok).
- Release asset adları her sürümde sabit: `Kadraj.zip`, `Kadraj.zip.sha256` (içerik: `shasum -a 256` çıktısı, dosya adı `Kadraj.zip`).
- Tag biçimi `v<semver>`; `main` kanalı = `nightly` tag'li prerelease.
- Hiçbir dosyada / commit mesajında AI atfı yok.

## Review Focus
1. Kullanıcı `/Applications`'a yazamıyor (standart hesap) → `~/Applications` oluşturulup oraya kurulmalı, hata vermemeli. *(Task 4 testi: `install dir falls back to home`)*
2. Kadraj çalışırken yeniden kurulum/güncelleme → eski süreç kapatılıp yeni sürüm yerine konmalı, yarım kalmış `.app` bırakılmamalı. *(Task 4 testi: `reinstall replaces existing app`)*
3. Ağ kesilir / SHA uyuşmaz / sürüm etiketi yok (404) → anlaşılır hata, mevcut kurulum bozulmadan kalmalı. *(Task 4 testleri: `checksum mismatch keeps old app`, `missing release fails clearly`)*
4. Kullanıcı `v1.2.0` ve `1.2.0` yazar ya da boş bırakır → aynı tag'e çözülmeli. *(Task 4 testi: `resolve_tag`)*
5. Ekran Kaydı izni verilmemiş / MDM ile engellenmiş → uygulama çökmemeli, menüden izin durumunu ve ayar linkini göstermeli. *(Task 2 testi: `PermissionStatus` metinleri + manuel kontrol)*

---

### Task 1: Paket iskeleti + KadrajCore

**Files:**
- Create: `Package.swift`, `.gitignore`, `LICENSE`, `Sources/KadrajCore/AppInfo.swift`, `Sources/Kadraj/main.swift`, `Tests/KadrajCoreTests/AppInfoTests.swift`

**Interfaces:**
- Produces: `public struct AppInfo: Equatable, Sendable { public let version: String; public let build: String; public init(infoDictionary: [String: Any]?); public var displayString: String }` — `displayString` = `"Kadraj \(version) (\(build))"`; sözlük yoksa / anahtar yoksa `version = "dev"`, `build = "0"`.

- [ ] **Step 1: `Package.swift`** — swift-tools-version 6.0, `platforms: [.macOS(.v14)]`, targets: `.target(name: "KadrajCore")`, `.executableTarget(name: "Kadraj", dependencies: ["KadrajCore"])`, `.testTarget(name: "KadrajCoreTests", dependencies: ["KadrajCore"])`. `.gitignore`: `.build/`, `dist/`, `*.xcodeproj`, `.swiftpm/`, `.DS_Store`. `LICENSE`: MIT, 2026, Mahir Uslu. `main.swift` geçici olarak `print(AppInfo(infoDictionary: Bundle.main.infoDictionary).displayString)`.

- [ ] **Step 2: Failing test** (`import Testing`)

```swift
@Test func readsVersionAndBuild() {
    let info = AppInfo(infoDictionary: ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "42"])
    #expect(info.version == "1.2.0"); #expect(info.build == "42")
    #expect(info.displayString == "Kadraj 1.2.0 (42)")
}
@Test func fallsBackToDev() {
    #expect(AppInfo(infoDictionary: nil).displayString == "Kadraj dev (0)")
    #expect(AppInfo(infoDictionary: [:]).version == "dev")
}
```

- [ ] **Step 3:** `swift test` → FAIL (`AppInfo` yok).
- [ ] **Step 4:** `AppInfo`'yu yaz.
- [ ] **Step 5:** `swift test` → 2 test PASS; `swift build` başarılı.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "chore: SwiftPM skeleton with KadrajCore"`

---

### Task 2: Menü çubuğu uygulaması + izin onboarding

**Files:**
- Create: `Sources/KadrajCore/PermissionStatus.swift`, `Sources/Kadraj/App/AppDelegate.swift`, `Sources/Kadraj/App/StatusMenu.swift`, `Sources/Kadraj/App/ScreenCapturePermission.swift`, `Sources/Kadraj/App/OnboardingWindow.swift`, `Tests/KadrajCoreTests/PermissionStatusTests.swift`
- Modify: `Sources/Kadraj/main.swift`

**Interfaces:**
- Consumes: `AppInfo` (Task 1).
- Produces:
  - `public enum PermissionStatus: Sendable { case granted, notGranted }` + `public var menuTitle: String` — granted: `"Ekran Kaydı izni: verildi ✓"`, notGranted: `"Ekran Kaydı izni gerekli…"`.
  - `public enum SystemSettingsLink { public static let screenRecording: URL }` = `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
  - `@MainActor enum ScreenCapturePermission { static var status: PermissionStatus; static func request() }` — `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()`.
  - `@MainActor final class AppDelegate: NSObject, NSApplicationDelegate` — status item (SF Symbol `viewfinder`), menü: `AppInfo.displayString` (pasif), ayraç, izin öğesi (`menuTitle`; tıklanınca notGranted ise onboarding açar), ayraç, `"Kadraj'dan Çık"` (⌘Q). Menü her açılışta (`menuNeedsUpdate`) izin durumunu yeniler.
  - `OnboardingWindow`: kısa açıklama ("Kadraj ekran görüntüsü alabilmek için Ekran Kaydı iznine ihtiyaç duyar. Şirket bilgisayarında bu izin kapalıysa IT ekibinize başvurun."), "İzin Ver" (`request()`), "Sistem Ayarlarını Aç" (`NSWorkspace.open(SystemSettingsLink.screenRecording)`) butonları. İlk açılışta izin yoksa otomatik gösterilir.
  - `main.swift`: `NSApplication.shared` + `setActivationPolicy(.accessory)` + delegate + `run()`.

- [ ] **Step 1: Failing test**

```swift
@Test func menuTitles() {
    #expect(PermissionStatus.granted.menuTitle == "Ekran Kaydı izni: verildi ✓")
    #expect(PermissionStatus.notGranted.menuTitle == "Ekran Kaydı izni gerekli…")
}
@Test func settingsLink() {
    #expect(SystemSettingsLink.screenRecording.absoluteString ==
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
}
```

- [ ] **Step 2:** `swift test` → FAIL.
- [ ] **Step 3:** Core tiplerini, ardından uygulama dosyalarını yaz.
- [ ] **Step 4:** `swift test` → PASS; `swift build` uyarısız (Swift 6 strict concurrency).
- [ ] **Step 5: Commit** — `feat: menu bar shell with screen recording onboarding`

(Uygulamanın gerçekten çalıştığı Task 3'te `.app` paketiyle doğrulanır — `LSUIElement` ve izin kimliği paket gerektirir.)

---

### Task 3: `.app` paketleme + imzalama scripti

**Files:**
- Create: `Resources/Info.plist`, `scripts/bundle.sh`, `scripts/version.sh`

**Interfaces:**
- Produces: `scripts/bundle.sh [--version X.Y.Z] [--build N]` → `dist/Kadraj.app` ve `dist/Kadraj.zip` + `dist/Kadraj.zip.sha256`. Env: `KADRAJ_SIGN_IDENTITY` (yoksa `-` = ad-hoc). Varsayılan version `scripts/version.sh` çıktısı (`git describe --tags --match 'v*'`'den `v` atılmış, yoksa `0.0.0-dev`), build = `git rev-list --count HEAD`.

- [ ] **Step 1: `Info.plist` şablonu** — `CFBundleIdentifier` com.mahiruslu.kadraj, `CFBundleName`/`CFBundleExecutable` Kadraj, `CFBundlePackageType` APPL, `LSUIElement` true, `LSMinimumSystemVersion` 14.0, `NSHumanReadableCopyright` "© 2026 Mahir Uslu — MIT", `CFBundleShortVersionString` `__VERSION__`, `CFBundleVersion` `__BUILD__` (script `sed` ile değiştirir).
- [ ] **Step 2: `bundle.sh`** — `set -euo pipefail`; `swift build -c release --triple arm64-apple-macosx14.0` ve `--triple x86_64-apple-macosx14.0`; `lipo -create` → `Contents/MacOS/Kadraj`; Info.plist kopyala+doldur; varsa `.build/*/release/*.bundle` kaynak paketlerini `Contents/Resources`'a kopyala; `codesign --force --options runtime --timestamp -s "$IDENTITY"` (ad-hoc'ta `--timestamp` yerine `--timestamp=none`); `ditto -c -k --keepParent dist/Kadraj.app dist/Kadraj.zip`; `(cd dist && shasum -a 256 Kadraj.zip > Kadraj.zip.sha256)`.
- [ ] **Step 3: Doğrula**
  - `scripts/bundle.sh --version 0.0.1 --build 1` → hata yok.
  - `lipo -archs dist/Kadraj.app/Contents/MacOS/Kadraj` → `x86_64 arm64`
  - `codesign --verify --deep --strict --verbose=2 dist/Kadraj.app` → `valid on disk`
  - `plutil -extract CFBundleShortVersionString raw dist/Kadraj.app/Contents/Info.plist` → `0.0.1`
  - `(cd dist && shasum -a 256 -c Kadraj.zip.sha256)` → `Kadraj.zip: OK`
  - `open dist/Kadraj.app` → menü çubuğunda vizör ikonu, Dock'ta ikon yok, menüde "Kadraj 0.0.1 (1)", izin yoksa onboarding penceresi açılır, "Sistem Ayarlarını Aç" doğru panele gider. Çık ile kapanır.
- [ ] **Step 4: Commit** — `build: app bundling and signing script`

---

### Task 4: `install.sh` + `uninstall.sh` + testleri

**Files:**
- Create: `install.sh`, `uninstall.sh`, `tests/install_test.sh`

**Interfaces:**
- Consumes: `Kadraj.zip` / `Kadraj.zip.sha256` düzeni (Task 3).
- Produces (`install.sh`):
  - Kullanım: `install.sh [latest|main|<version>]`.
  - Env: `KADRAJ_REPO` (vars. `mahiruslu/kadraj`), `KADRAJ_BASE_URL` (verilirse indirme `"$KADRAJ_BASE_URL/<tag>/Kadraj.zip"`; `latest` için `"$KADRAJ_BASE_URL/latest/Kadraj.zip"`), `KADRAJ_INSTALL_DIR`, `KADRAJ_NO_LAUNCH=1` (açmaz, `pkill` yapmaz — testler için), `KADRAJ_SOURCE_ONLY=1` (sadece fonksiyonları tanımlar, `main` çalışmaz — testler için).
  - Fonksiyonlar: `resolve_tag <arg>` → `latest` | `nightly` | `v<ver>`; `download_url <tag> <file>` → GitHub için `https://github.com/$REPO/releases/latest/download/<file>` veya `https://github.com/$REPO/releases/download/<tag>/<file>`; `pick_install_dir` → `KADRAJ_INSTALL_DIR` ya da `/Applications` (`-w` ise) ya da `$HOME/Applications` (`mkdir -p`).
  - Akış: macOS ≥ 14 kontrolü (`sw_vers -productVersion` major) → `mktemp -d` + `trap` temizlik → `curl -fsSL` zip ve sha256 → `shasum -a 256 -c` (geçici dizinde) → `ditto -x -k` → `Kadraj.app` var mı kontrol → `pkill -x Kadraj || true` → hedefte `Kadraj.app` varsa önce `Kadraj.app.old`'a taşı, yeniyi taşı, sonra `.old`'u sil (taşıma başarısızsa `.old`'u geri al) → `xattr -dr com.apple.quarantine` (hata yutulur) → `open` → kurulum yolu ve "İlk açılışta Ekran Kaydı izni istenecek" mesajı.
  - Hatalar `error: …` ile stderr'e, çıkış kodu 1. Renkli çıktı sadece TTY'de.
- Produces (`uninstall.sh`): `pkill -x Kadraj`; `/Applications/Kadraj.app` ve `~/Applications/Kadraj.app` (hangisi varsa ve yazılabilirse), `~/Library/Application Support/Kadraj`, `~/Library/Preferences/com.mahiruslu.kadraj.plist`, `~/Library/Caches/com.mahiruslu.kadraj` silinir; `/Applications`'taki silinemiyorsa uyarı verir (sudo önermez; "yöneticinize başvurun" der). `KADRAJ_INSTALL_DIR` destekler.

- [ ] **Step 1: Failing test scripti `tests/install_test.sh`** — saf bash; `dist/`'e sahte bir `Kadraj.app` (içinde `Contents/Info.plist` ve marker dosyası) oluşturup ziplenir; fixture dizini `fixtures/v1.2.0/`, `fixtures/latest/`, `fixtures/nightly/`, `fixtures/vbad/` (yanlış sha) düzeninde hazırlanır; `KADRAJ_BASE_URL=file://$FIXTURES` (curl `file://` destekler → HTTP sunucusu gerekmez), `KADRAJ_NO_LAUNCH=1`, `KADRAJ_INSTALL_DIR=$TMP/apps`. Testler (her biri `pass`/`fail` yazar, biri bile fail ise çıkış 1):
  - `resolve_tag`: `""`→`latest`, `latest`→`latest`, `main`→`nightly`, `1.2.0`→`v1.2.0`, `v1.2.0`→`v1.2.0`, `V1.2.0`→`v1.2.0`.
  - `download_url` (BASE_URL yokken): `latest Kadraj.zip` → `https://github.com/mahiruslu/kadraj/releases/latest/download/Kadraj.zip`; `v1.2.0 Kadraj.zip` → `.../releases/download/v1.2.0/Kadraj.zip`.
  - `installs specific version`: `bash install.sh 1.2.0` → `$TMP/apps/Kadraj.app/marker` içeriği `1.2.0`.
  - `installs main`: `bash install.sh main` → marker `nightly`.
  - `reinstall replaces existing app`: önce 1.2.0, sonra latest → marker `latest`, `Kadraj.app.old` yok.
  - `checksum mismatch keeps old app`: 1.2.0 kur, sonra `bash install.sh bad` → çıkış ≠ 0, stderr `checksum` içerir, marker hâlâ `1.2.0`.
  - `missing release fails clearly`: `bash install.sh 9.9.9` → çıkış ≠ 0, stderr `9.9.9` içerir.
  - `install dir falls back to home`: `KADRAJ_INSTALL_DIR` boş, `HOME=$TMP/home`, `KADRAJ_SOURCE_ONLY=1` ile `pick_install_dir` — `/Applications` yazılabilir değilse `$TMP/home/Applications` döner ve dizin oluşur (yazılabilirse `/Applications` döner; test her iki dalı `-w` sonucuna göre doğrular).
  - `piped install works`: `cat install.sh | bash -s -- 1.2.0` → marker `1.2.0` (curl|bash simülasyonu).
  - `no sudo`: `grep -n 'sudo' install.sh uninstall.sh` sadece yorum/mesaj satırlarında; komut olarak `sudo ` çağrısı yok.
  - `uninstall removes app`: `KADRAJ_INSTALL_DIR=$TMP/apps bash uninstall.sh` → `Kadraj.app` yok.
- [ ] **Step 2:** `bash tests/install_test.sh` → FAIL (install.sh yok).
- [ ] **Step 3:** `install.sh` ve `uninstall.sh`'i yaz (`chmod +x`).
- [ ] **Step 4:** `bash tests/install_test.sh` → tümü `pass`; `/bin/bash --version` 3.2 ile çalıştırıldığını doğrula (`/bin/bash tests/install_test.sh`).
- [ ] **Step 5:** Gerçek paketle uçtan uca: `scripts/bundle.sh --version 0.0.1 --build 1`, `mkdir -p $TMP/srv/v0.0.1 && cp dist/Kadraj.zip* $TMP/srv/v0.0.1/`, `KADRAJ_BASE_URL=file://$TMP/srv KADRAJ_INSTALL_DIR=$HOME/Applications bash install.sh 0.0.1` → uygulama açılır, menüde 0.0.1. Sonra `KADRAJ_INSTALL_DIR=$HOME/Applications bash uninstall.sh`.
- [ ] **Step 6: Commit** — `feat: curl installer and uninstaller (no sudo)`

---

### Task 5: GitHub Actions — CI, release, nightly

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/workflows/nightly.yml`, `scripts/ci-import-cert.sh`, `scripts/notarize.sh`

**Interfaces:**
- Consumes: `scripts/bundle.sh` (Task 3), `tests/install_test.sh` (Task 4).
- Secrets (hepsi opsiyonel; yoksa ad-hoc imza + notarization atlanır, log'da uyarı): `DEVELOPER_ID_P12` (base64), `DEVELOPER_ID_P12_PASSWORD`, `DEVELOPER_ID_NAME` (örn. `Developer ID Application: Muammer Mahir Uslu (TEAMID)`), `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8` (base64).
- `scripts/ci-import-cert.sh`: geçici keychain oluşturur, p12'yi import eder, `security set-key-partition-list`, `KADRAJ_SIGN_IDENTITY`'yi `$GITHUB_ENV`'e yazar.
- `scripts/notarize.sh <zip> <app>`: p8'i geçici dosyaya yazar, `xcrun notarytool submit <zip> --key … --key-id … --issuer … --wait`, `xcrun stapler staple <app>`, sonra zip'i ve sha256'yı **yeniden** üretir (staple edilmiş app ile).

- [ ] **Step 1: `ci.yml`** — `on: [pull_request, push: branches-ignore: [main]]`; `runs-on: macos-14`; adımlar: checkout, `swift test`, `scripts/bundle.sh` (ad-hoc), `brew install shellcheck && shellcheck install.sh uninstall.sh scripts/*.sh tests/*.sh`, `bash tests/install_test.sh`.
- [ ] **Step 2: `release.yml`** — `on: push: tags: ['v*']`; `permissions: contents: write`; adımlar: checkout (`fetch-depth: 0`), `swift test`, `bash tests/install_test.sh`, cert import (secret varsa), `scripts/bundle.sh --version ${GITHUB_REF_NAME#v} --build ${{ github.run_number }}`, notarize (secret varsa), `gh release create "$GITHUB_REF_NAME" dist/Kadraj.zip dist/Kadraj.zip.sha256 --generate-notes --verify-tag`.
- [ ] **Step 3: `nightly.yml`** — `on: push: branches: [main]` + `workflow_dispatch`; `concurrency: nightly`; aynı build, version `0.0.0-nightly.<kısa sha>`; `gh release delete nightly --cleanup-tag -y || true` ardından `gh release create nightly … --prerelease --title "Nightly" --target "$GITHUB_SHA"`.
- [ ] **Step 4: Lokal doğrulama** — `brew install shellcheck actionlint` (sadece geliştirici makinesinde), `shellcheck install.sh uninstall.sh scripts/*.sh tests/*.sh` → çıktı yok; `actionlint` → çıktı yok.
- [ ] **Step 5: Commit** — `ci: build, test, sign, notarize and release workflows`

---

### Task 6: README + yayın ve uçtan uca doğrulama

**Files:**
- Create: `README.md` (TR), `README.en.md` (EN), `docs/MDM.md`

**Interfaces:** —

- [ ] **Step 1: Dokümanlar** — README: tek satır tanım, kurulum komutları (latest / sürüm / main — Global Constraints'teki URL'ler), "Neden admin gerekmez?" (`~/Applications`, quarantine), izin bölümü, kaldırma (`curl … uninstall.sh | bash`), kaynaktan derleme (`swift test`, `scripts/bundle.sh`), yol haritası (spec'teki aşamalar), lisans. `docs/MDM.md`: IT için PPPC profil örneği (`com.apple.TCC.configuration-profile-policy`, `ScreenCapture` servisi; Sonoma'da standart kullanıcının izin vermesine olanak tanıyan `Authorization: AllowStandardUserToSetSystemService`), bundle id + Team ID ile `CodeRequirement` (`codesign -dr - Kadraj.app` çıktısı) nasıl alınır.
- [ ] **Step 2: Commit** — `docs: README (TR/EN) and MDM guide`
- [ ] **Step 3: Kullanıcı aksiyonları (önce onay al)** — GitHub'da public `mahiruslu/kadraj` repo'sunu oluşturmak ve push etmek için kullanıcıdan onay; kullanıcı Developer ID Application sertifikasını (p12) ve App Store Connect API anahtarını (p8) oluşturup secret'ları `gh secret set` ile ekler (talimat README'nin "Release" bölümünde).
- [ ] **Step 4: Yayın** — `gh repo create mahiruslu/kadraj --public --source . --push`; nightly workflow'unun yeşil bittiğini `gh run watch` ile doğrula; `git tag v0.1.0 && git push origin v0.1.0`; release workflow yeşil.
- [ ] **Step 5: Uçtan uca** —
  - `curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash` → 0.1.0 kurulur, açılır.
  - `… | bash -s -- v0.1.0` ve `… | bash -s -- main` → başarılı.
  - İndirilen app üzerinde `spctl -a -vv` → `accepted, source=Notarized Developer ID`; `xcrun stapler validate` → `worked`.
  - Admin olmayan standart kullanıcı hesabında aynı komut → `~/Applications/Kadraj.app`, sudo sorulmaz, Gatekeeper uyarısı yok, izin penceresi açılır.
