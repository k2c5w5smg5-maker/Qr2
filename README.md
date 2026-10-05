# QR Maker (iOS)

A simple, native iOS app for the App Store that makes QR codes and charges per code
through Apple In-App Purchase.

## What it does

- **Link types:** Website, Photo (any photo share link or image address), YouTube
  (video, Shorts, playlist, channel or `@handle`), and Meta (Facebook, Instagram,
  WhatsApp, Threads, Messenger). Input is normalised into a clean URL before encoding.
- **Shape and size:** square or rectangle output with adjustable width and height
  (256 to 4096 px) plus ratio presets. The QR grid always stays square and is centred
  on the canvas with a proper quiet zone, so rectangular codes still scan.
- **Styling:** code and background colours, error correction level.
- **Pay per code:** the preview is blurred and badged until the user unlocks it. One
  credit unlocks one code. Credits are consumable in-app purchases (`1 credit` and
  `10 credits` packs). Unlocked codes are kept in **My Codes** for unlimited re-download.
- **Export:** save PNG to Photos, share PNG, share SVG (vector, for print), copy link.

## Project layout

```
QRMaker.xcodeproj/          Xcode 16 project (folder-synchronised, no file lists to maintain)
QRMaker/
  QRMakerApp.swift          App entry; injects StoreManager and CodeLibrary
  ContentView.swift         Tab bar: Create / My Codes
  Models/QRTarget.swift     Link kinds + TargetResolver (URL normalisation)
  Models/QRStyle.swift      Colours, error correction, CanvasSpec (shape + size)
  Models/SavedCode.swift    A purchased code (the recipe, not the image)
  Services/QRRenderer.swift Module grid via Core Image, drawn with Core Graphics; PNG + SVG
  Services/StoreManager.swift  StoreKit 2 consumables and the credit balance
  Services/CodeLibrary.swift   JSON persistence of purchased codes
  Services/PhotoSaver.swift    Save to Photos + temp export files for sharing
  Views/                    BuilderView, ShapeSettingsView, QRImage, PurchaseSheet,
                            LibraryView, CodeDetailView
  PrivacyInfo.xcprivacy     Required privacy manifest (UserDefaults reason CA92.1)
Configuration/Products.storekit  Local StoreKit test products (used by the shared scheme)
```

Requirements: Xcode 16 or newer, iOS 17 or newer.

## Run it locally

1. Open `QRMaker.xcodeproj` in Xcode.
2. Select the **QRMaker** scheme and an iPhone simulator, then Run.
3. Purchases use `Configuration/Products.storekit`, so you can buy credits in the
   simulator without an App Store Connect account.

## Publish on the App Store

1. **Bundle ID and team.** In the target's *Signing & Capabilities*, set your Team and
   change `PRODUCT_BUNDLE_IDENTIFIER` from `com.example.qrmaker` to your own ID.
2. **App icon.** Drop a 1024 × 1024 PNG into `QRMaker/Assets.xcassets/AppIcon.appiconset`
   (Xcode will ask for it; the catalog already has the slots).
3. **App Store Connect.**
   - Create the app record with the same bundle ID.
   - Sign the *Paid Apps* agreement under Agreements, Tax, and Banking.
   - Under *In-App Purchases* create two **Consumable** products with exactly these IDs:
     - `com.example.qrmaker.credit.1` (for example $0.99)
     - `com.example.qrmaker.credit.10` (for example $4.99)
     If you prefer different IDs, change `CreditPack` in `StoreManager.swift` and
     `Configuration/Products.storekit` to match.
   - Add a privacy policy URL and screenshots. The app collects no data and does not
     track, as declared in `PrivacyInfo.xcprivacy`.
4. **Test real purchases** with a Sandbox tester account (App Store Connect → Users and
   Access → Sandbox). In Xcode, edit the scheme and set *StoreKit Configuration* to
   *None* to hit the sandbox instead of the local file.
5. Archive (Product → Archive) and upload with the Organizer, then submit for review.
   In review notes, mention that the blurred preview becomes a full code after an
   in-app purchase, so reviewers know how to test it.

## Changing the price

Prices live in App Store Connect, not in code. Edit the product's price there; the app
shows `Product.displayPrice` in the user's local currency automatically.

## Notes and limits

- Credits are stored in `UserDefaults` on the device. That is fine for a simple
  consumable model, but a determined user with a jailbroken device could edit it. If
  that matters, move the balance to the Keychain or a server with receipt validation.
- Photos are linked, not uploaded. A QR code cannot hold an image, so the Photo type
  expects a shareable link (iCloud link from Photos, Google Photos, Dropbox, etc.).
- Next step for "custom shapes": `QRRenderer` draws each module itself, so rounded or
  circular modules, a circular canvas, or a logo cut-out can be added in the draw loop
  and the SVG path builder without touching the rest of the app.
