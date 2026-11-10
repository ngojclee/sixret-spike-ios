# SpikePhotoHide — Phase 0 test app

App iOS tối giản để verify 3 giả định sống còn của spec (xem doc spec, mục 11)
trước khi build MVP. **Chỉ chạy trên iPhone thật + ảnh test — không chạy trên
máy chính** vì S2/S4 xóa ảnh thật.

## Không có Mac? Build bằng GitHub Actions

Mục này là đường chính nếu anh chỉ có Windows. **Đã chạy thành công** — xem
[run 42907038938](https://github.com/ngojclee/sixret-spike-ios/actions/runs/42907038938).

1. Repo public đã có: **https://github.com/ngojclee/sixret-spike-ios**
   (standard macOS runner miễn phí cho repo public).
2. Vào tab **Actions** → *Build iOS IPA* → **Run workflow** (hoặc tự chạy khi
   push `main`).
3. Tải artifact `sixret-spike-ios` → giải nén được `Sixret-Spike-iOS.ipa`.
4. Cài bằng **Sideloadly** trên Windows với Apple ID miễn phí
   (Settings → General → VPN & Device Management → tin tưởng profile).
   App hết hạn sau 7 ngày, ký lại là xong.

Workflow ở [.github/workflows/ios-build.yml](.github/workflows/ios-build.yml),
build không ký (`CODE_SIGNING_ALLOWED=NO`) rồi ký ad-hoc cho Sideloadly.

Thông số bản build đầu tiên: bundle id `com.spike.SpikePhotoHide`, iOS 17.0,
arm64, Xcode 26.5, build trong ~1 phút.

> Lưu ý khi fork/chạy trên máy Windows: workflow này dùng runner `macos-26`.
> Repo **private** thì macOS runner bị tính phí theo phút — dùng public như
> đã định.

## Yêu cầu

- Một trong hai: Mac + Xcode 15 trở lên, **hoặc** GitHub Actions như trên.
- iPhone iOS 17+.
- Free Apple ID provisioning là đủ (Personal Team) — không cần Developer $99.
- Ảnh test trên máy: ~50 ảnh thường, vài ảnh "nhạy cảm" test, và **ít nhất 3 ảnh
  nằm trong ≥2 album khác nhau** (cho S4).
- Nếu test iCloud sync: 1 device thứ 2 cùng Apple ID bật iCloud Photos.

## Mở project

### Cách A — XcodeGen (khuyên dùng)

```bash
brew install xcodegen
cd SpikePhotoHide
xcodegen
open SpikePhotoHide.xcodeproj
```

### Cách B — thủ công (5 phút)

1. Xcode → Create New Project → iOS → App → Interface: SwiftUI, Language: Swift,
   đặt tên `SpikePhotoHide`, deployment iOS 17.
2. Xóa `ContentView.swift` mặc định, kéo toàn bộ file trong thư mục
   `SpikePhotoHide/SpikePhotoHide/` vào target (tick "Copy items if needed",
   tick target).
3. Trong target → Info tab → thêm 2 key: `Privacy - Photo Library Usage
   Description` và `Privacy - Photo Library Additions Usage Description`
   (copy text từ file `Info.plist` đi kèm).
4. Chọn team cá nhân trong Signing & Capabilities → Run trên iPhone.

## Chạy test theo thứ tự

| Tab | Task | Làm gì | PASS khi |
|-----|------|--------|----------|
| S1 Hidden | isHidden writable | Bấm 1→2→3, check Hidden album trong Photos | set/unset được, không dialog per-asset |
| S2 Delete | Consent UX | Xóa batch 5→50, đếm dialog + tap, check Recently Deleted + device 2 | 1 dialog/batch, ảnh vào Recently Deleted |
| S3 Model | Benchmark | Drop `NSFW.mlmodel` vào bundle rồi chạy | ≥150 ảnh/phút; đánh giá FPR tay trên list flagged |
| S4 Restore | Album mapping | Load ảnh → chọn ảnh ≥2 album → Vault+Delete → Restore | đúng 100% album + date/loc giữ |
| Log | — | Xem/copy kết quả làm bằng chứng S5 | — |

## Model NSFW cho S3

App tự load file tên `NSFW` trong bundle (`.mlmodel` / `.mlmodelc` /
`.mlpackage`). Gợi ý:

- `open_nsfw` CoreML port (Yahoo, BSD).
- MobileNetV2 NSFW classifier bất kỳ trên Core ML community.

Chưa có model → `SkinToneScorer` chạy pipeline, nhưng đó chỉ là stub để
smoke-test, **không** dùng để pass G3.

## Ghi chú quan trọng

- **S1 bẫy phổ biến:** fetch mặc định loại trừ ảnh hidden — verify phải dùng
  `includeHiddenAssets` (code đã xử lý).
- **Cancel = data:** nếu user hủy dialog xóa, đó là bằng chứng consent flow
  hoạt động — ghi vào report, không phải lỗi.
- **Vault của S4** dùng AES-GCM nhưng key giữ trong memory per-install — đủ cho
  spike, production dùng Keychain.
- Mọi kết quả → tab **Log → Copy** → paste vào report S5 / decision matrix.

## Cấu trúc

```
SpikePhotoHide/
├── project.yml              # XcodeGen spec
├── README.md
└── SpikePhotoHide/
    ├── Info.plist
    ├── SpikePhotoHideApp.swift   # entry point
    ├── ContentView.swift         # TabView + LogView
    ├── PhotoLibrary.swift        # PhotoKit helpers (fetch/thumbnail/data/albums)
    ├── LogStore.swift            # log chung cho mọi test
    ├── HiddenTestView.swift      # S1
    ├── DeleteTestView.swift      # S2
    ├── BenchmarkView.swift       # S3
    ├── NSFWScorer.swift          # protocol + CoreML scorer + stub
    └── RestoreTestView.swift     # S4 + VaultStore
```
