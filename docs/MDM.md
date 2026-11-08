# Kadraj on managed Macs (for IT administrators)

Kadraj needs exactly one privacy permission: **Screen Recording** (TCC service `ScreenCapture`). It does not need Accessibility, Input Monitoring, Full Disk Access or admin rights.

Apple does not allow MDM to *grant* Screen Recording silently. What MDM can do is let **standard (non-admin) users approve it themselves** via a PPPC payload with `Authorization = AllowStandardUserToSetSystemService`.

## 1. Get Kadraj's code requirement

```bash
codesign -dr - /Applications/Kadraj.app   # or ~/Applications/Kadraj.app
```

The output looks like:

```
designated => identifier "com.mahiruslu.kadraj" and anchor apple generic and certificate leaf[subject.OU] = "TEAMID" and …
```

Use everything after `designated => ` as `CodeRequirement`.

## 2. PPPC profile

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadIdentifier</key><string>com.example.kadraj.pppc</string>
  <key>PayloadUUID</key><string>REPLACE-WITH-UUID-1</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadDisplayName</key><string>Kadraj Screen Recording</string>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key><string>com.apple.TCC.configuration-profile-policy</string>
      <key>PayloadIdentifier</key><string>com.example.kadraj.pppc.tcc</string>
      <key>PayloadUUID</key><string>REPLACE-WITH-UUID-2</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>Services</key>
      <dict>
        <key>ScreenCapture</key>
        <array>
          <dict>
            <key>Identifier</key><string>com.mahiruslu.kadraj</string>
            <key>IdentifierType</key><string>bundleID</string>
            <key>CodeRequirement</key><string>PASTE-CODE-REQUIREMENT-HERE</string>
            <key>Authorization</key><string>AllowStandardUserToSetSystemService</string>
          </dict>
        </array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
```

## Network access

Kadraj works fully offline (OCR uses Apple's on-device Vision framework). The only network call is the optional update check to `api.github.com` / `github.com`.
