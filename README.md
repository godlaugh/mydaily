# ALog

<img src="Images/Promo.png" style="max-height: 400px" />

## Installation

[![Download ALog on the App Store](./Images/badge_appstore-lrg.svg)](https://apps.apple.com/us/app/alog/id6451082482)

## Transcription Models

Open **Settings → Transcription Models** to choose an engine, then enable transcription in Settings.

- **SenseVoice Small** runs on your device and offers two separately installed variants: **INT8 quantized** (about **240 MB**) and **FP32 floating point** (about **938 MB**). Download a variant, then tap it to select it; downloading does not change your current engine. Both support Mandarin, Cantonese, English, Japanese, and Korean, and work offline without uploading audio after download.
- **Apple Speech** remains available through the system speech recognition service. Language availability and network use depend on the device and Apple's support.
- **OpenAI** remains available through the selected ALog or custom server, with its existing cloud model choices. It requires a network connection and sends audio to that server.

Each local variant has its own download progress, cancellation, retry, and confirmed deletion. You can keep both installed. Deleting the selected local variant switches transcription to Apple Speech; deleting another variant keeps your current selection. A model in use cannot be deleted.

SenseVoice processes completed recordings in offline segments of up to 30 seconds, preferring pauses near segment boundaries and retaining the final short segment. Live streaming transcription is not implemented. Device performance and recognition quality should be evaluated with your own recordings.

## Journal interface

The journal uses a quiet, adaptive light/dark layout. A recording's date and compact play control stay in the list; a shared mini-player appears after playback starts. Open a diary to read its dated timeline and original audio waveform.

Headings are derived from the opening sentence or line, targeting 40 characters and moving the boundary before any word that would be split. Domains and hyphenated terms remain intact; an unusually long first word is kept whole. Remaining text stays in the entry body, and this presentation never rewrites the stored diary.

Use the microphone or writing button at the bottom of a diary to add another dated entry to the same thread. A thread occupies one position on the home screen, ordered by its newest entry while keeping the original date. Its latest entry appears as a small preview with a layers icon, without a visible count label. Each entry can be edited, shared, transcribed, hidden, or deleted separately. Long-press a home entry to select journals for bulk deletion. The optional hold-to-record setting still supports releasing to save and sliding up to cancel.

The version 4 Core Data model adds optional thread relationships through lightweight migration. Existing diaries remain separate until an entry is appended. Removing one date preserves the other entries; removing a whole journal requires confirmation. The independent `ALog Test` bundle keeps its data separate from the official app.

`JournalStoreTests` verifies migration, persistence, grouping, and deletion; `JournalAudioPlayerTests` verifies pause/resume, switching, and closing playback. Run `JournalUITests` with the `SnapshotTests` scheme **in Debug configuration** to verify the native flows and capture light/dark layouts. These UI tests use an isolated `JournalUITests.sqlite` store and generated silent audio; their sample diary content never appears in ordinary launches.

## Building the project

Follow these steps to build the project:

#### 1. Clone the repo

```shell
git clone https://github.com/duxins/alog
```

#### 2. Install xcodegen

```shell
brew install xcodegen
```

#### 3. Install Ruby gems

```shell
bundle install
```

#### 4. Copy .env.example to .env

To setup up the environment variables, copy the `.env.example` file and rename it as `.env`.

```shell
cp .env.example .env
```

Update the keys as needed within the .env file.

#### 5. Generate the Arkana package

```shell
bundle exec bin/arkana
```

#### 6. Generate the project

Finally, generate the project by running:

```shell
xcodegen
```

Open the generated `ALog.xcodeproj`, select the **ALog** scheme and **Debug** configuration, and build for an iOS simulator or a device with your signing settings. The iOS deployment target remains 16.0.

The full scheme embeds the Watch app, so Xcode also needs its matching watchOS platform/runtime installed.

Swift Package Manager resolves the pinned [sherpa-onnx 2.0.1 runtime](https://github.com/k2-fsa/sherpa-onnx/releases/tag/v2.0.1). Model weights are downloaded separately in the app. The INT8/FP32 ONNX exports and tokens are pinned to [revision `2365baeacb507f821a0c8120fcee3d484dba7a07`](https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/tree/2365baeacb507f821a0c8120fcee3d484dba7a07); expected sizes and SHA-256 checksums are recorded in [LocalTranscriptionModel.swift](Sources/Services/Transcription/Models/LocalTranscriptionModel.swift) and verified before installation.

Downloads first use the byte-identical [ModelScope mirror at a fixed revision](https://modelscope.cn/models/WEAAEW/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/files?Revision=59ee0bceb05d61d4148341323e509db2899bd9a2), with the original Hugging Face URL as a fallback. The app shows the active source, downloaded bytes, transfer speed, and connection/verification state. Keep the app open while downloading; downloads are not background transfers, and a retry starts the current file again. Existing verified model installations remain compatible.

### Testing on your iPhone

Generate a separate **ALog Test** app with your own unique bundle identifier:

```shell
python3 scripts/prepare-iphone-build.py --bundle-id dev.yourname.alogtest
open .build/iphone-test/ALogTest.xcodeproj
```

The generated project uses automatic signing and a separate data container. It builds the iPhone app without Watch or widget targets. You can pass `--team YOURTEAMID` to retain a known development team when regenerating it, or select your team in Xcode.

1. Sign in under **Xcode → Settings → Accounts** with your Apple Account.
2. Connect and unlock your iPhone, trust the Mac, and enable **Settings → Privacy & Security → Developer Mode** if Xcode requests it.
3. Open the generated project, select the **ALog** scheme and your iPhone, and choose your team under **Signing & Capabilities**. Keep automatic signing enabled and press **Run**.
4. In **ALog Test → Settings → Transcription Models**, download the desired INT8/FP32 model, select it, then enable transcription. Use the same recordings to compare the two variants.

A free Personal Team can install the app for personal testing; its provisioning profiles expire after seven days, requiring a rebuild/reinstall. TestFlight distribution requires Apple Developer Program membership. See [Apple's account and Personal Team documentation](https://developer.apple.com/help/account/basics/about-your-developer-account).

### Tests

Run the **ALog** scheme's unit tests in Xcode, or use an installed simulator's UDID:

```shell
xcodebuild test -project ALog.xcodeproj -scheme ALog -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>'
```

The model-store and audio-conversion tests use small local fixtures and do not download model weights. The optional `SenseVoiceAudioTests/testOfficialModelTranscribesProvidedSample` test is skipped unless these variables are set in the scheme's **Test → Arguments → Environment Variables**, using absolute paths readable by the test process:

| Variable | Value |
|---|---|
| `ALOG_SENSEVOICE_MODEL_PATH` | Path to `model.int8.onnx` (INT8) or `model.onnx` (FP32) from the pinned export |
| `ALOG_SENSEVOICE_TOKENS_PATH` | Path to the matching `tokens.txt` |
| `ALOG_SENSEVOICE_AUDIO_PATH` | Path to a WAV or AAC recording |
| `ALOG_SENSEVOICE_EXPECTED_TEXT` | Optional text fragment expected in the transcript |

For the settings-page UI tests, use **Debug** explicitly to avoid the Snapshot configuration's sample-data setup:

```shell
xcodebuild test -project ALog.xcodeproj -scheme SnapshotTests -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:SnapshotTests/TranscriptionModelsUITests
```

The real download lifecycle UI tests are opt-in through the test runner environment: `ALOG_TEST_MODEL_DOWNLOAD=1` for INT8 (about 240 MB), and `ALOG_TEST_MODEL_DOWNLOAD_FP32=1` for FP32 (about 938 MB). Each verifies cancel/retry and selection, then deletes that variant and checks the Apple fallback. Use a dedicated simulator for these tests.

## Deploying server-side code to Cloudflare

### Steps: 

#### 1. Create a new Cloudflare worker

* Once logged in, navigate to the "**Workers & Pages**" section.
* Click on "**Create Application**" → "**Create Worker**".
* Rename the Worker as per your requirements.
* Click on "**Deploy**".

#### 2. Configure your worker

* After deploying, you'll see a "**Quick Edit**" button. Click on it.
* Paste the contents of [Server/src/worker.js](Server/src/worker.js) into the Cloudflare Worker editor.
* Click on "**Save and deploy**"

#### 3. Set Environment variables:

* On the Worker's **Settings** tab, navigate to the **Variables** section.
* Set the following variables:

| Variable         |            | Description          |
|------------------|------------|----------------------|
| **`OPENAI_KEY`** | *Required* | Your OpenAI API key. |
| **`HMAC_KEY`**   | *Optional* | This should be consistent with the key used on the client side. If this variable is not set, HMAC validation will not be performed. |
| **`AI_MODEL`**   | *Optional* | Represents the default model. If not set, the model specified by the client will be used.                                           |

#### 4. Update API base URL

* Open `Constants.swift` file.
* Update the `api_base_url` constant to point to the URL of your deployed Cloudflare Worker.

```swift
struct Constants {
    static let api_base_url = URL(string: "https://your-worker-name.workers.dev/")!
}
```

## License

Distributed under the GNU General Public License v2.0. See [LICENSE](./LICENSE) for more information.

Local transcription uses [sherpa-onnx under Apache 2.0](https://github.com/k2-fsa/sherpa-onnx/blob/v2.0.1/LICENSE). The model originates from [FunAudioLLM's SenseVoiceSmall](https://huggingface.co/FunAudioLLM/SenseVoiceSmall), whose model card links to the separate [FunASR model license](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE). The ONNX conversion is published by [csukuangfj](https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/blob/2365baeacb507f821a0c8120fcee3d484dba7a07/README.md).

**Important Note:** This open-source license does not prevent anyone from renaming and repackaging this app for distribution. However, doing so is in direct violation of App Store Review Guidelines, specifically Guideline 4.1 (Copycats) and Guideline 4.3 (Spam). Any attempt to simply rename and repackage this app for submission to the App Store is explicitly prohibited.

## Credits

Thanks to [@onenewbite](https://twitter.com/onenewbite) for his inspiring video "[为什么你应该开始用ChatGPT写日记|做笔记](https://www.youtube.com/watch?v=ZRv0Z-M7NqM)", which has greatly influenced this project.
