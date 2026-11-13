# QR Maker and Label Maker (iOS)

Two native iOS apps from one project:

- **QR Maker** makes QR codes and charges per code through Apple In-App Purchase. It also
  includes the label maker as its **Labels** tab.
- **Label Maker** is the label maker on its own (target `LabelMaker`). It makes printable
  sticker-sheet labels with an LLM, from a product page link or from spoken or typed
  instructions.

## Label Maker

- **From a product page:** paste a link. The page is read on the phone (schema.org product
  data, Open Graph tags and visible text), then the model writes a short title, subtitle,
  up to three useful details, the price, the SKU or barcode number, and a QR code back to the
  page.
- **From your voice:** tap the mic and say something like "pantry labels for flour, sugar
  and rice with today's date" or "garage sale stickers: lamp $5, bike $25". Dictation runs on
  the device when supported.
- **Edit by asking:** "make 10 of each", "the bike is $20 now", "remove the QR code". You can
  also edit any label by hand.
- **Print:** PDF sheets for Avery 5160, 5163, 5164, 5167, L7160, L7163, L7165 and full
  sheets. Choose a start position to reuse part-used sheets. Pick a look (clean, bold, shelf
  tag) and choose whether to show QR codes, prices and codes. Print with AirPrint or share
  the PDF.
- **Your own LLM:** the app calls any OpenAI-compatible endpoint you run (llama.cpp, Ollama,
  vLLM). [`llm/`](llm/README.md) has the dataset format, seed data, a LoRA fine-tune script,
  an evaluator and serving steps. With no model set up, an on-device rules engine writes the
  labels, so the app works on its own.
- **Training flywheel:** with *Save training examples* on, every printed sheet becomes a
  fine-tuning example made of the prompt and the labels as you corrected them.

`LabelKit/` is self-contained (no QR Maker types), and both app targets include it through a
synchronised folder. To show it in any SwiftUI app, use `LabelMakerView()`.

## QR Maker

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
QRMaker.xcodeproj/          Xcode 16 project (folder-synchronised): targets QRMaker and LabelMaker
LabelKit/                   The label maker, shared by both targets
  Models/                   LabelContent (what the model writes), LabelTemplate (sheets), LabelDesign
  Sources/ProductPage.swift Fetch a product page and extract ProductFacts (JSON-LD, Open Graph, text)
  Model/                    LabelPrompt (shared prompt + reply parser), LabelModel protocol,
                            RemoteLabelModel (your LLM), OnDeviceLabelModel (rules fallback)
  Rendering/                LabelRenderer (auto-fit text + QR), LabelSheet (multi-page PDF), LabelQR
  Services/                 LabelStudio (state), Dictation (speech), TrainingLog, Keychain
  Views/                    LabelMakerView (root), LabelEditView, sheet settings/preview, model settings
LabelMakerApp/              Standalone app entry point, icon and privacy manifest
llm/                        Make, evaluate and serve your own label model (see llm/README.md)
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
2. Select the **QRMaker** or **LabelMaker** scheme and an iPhone simulator, then Run.
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
