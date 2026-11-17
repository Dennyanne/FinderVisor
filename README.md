# FinderVisor

A small macOS menu-bar app that brings back the **Visor** from TotalFinder: press a hotkey and a Finder window drops down at the bottom of your screen; press it again and it goes away.

- Uses a **real Finder window**: tabs, tags, Quick Look and Finder extensions all work.
- **No injection into Finder**, no SIP changes. Only public APIs (Accessibility, Apple Events, event tap, `SMAppService`).
- Menu-bar only, no Dock icon. Open source, build it yourself.

[한국어](#한국어)

## Inspiration

FinderVisor is inspired by the [Visor feature of TotalFinder](https://totalfinder.binaryage.com/visor) by BinaryAge. TotalFinder worked by loading code into Finder, which modern macOS security (System Integrity Protection) no longer allows, so its Visor stopped working. FinderVisor rebuilds just that one feature as a separate app that only uses public APIs. It is an independent project, not affiliated with or endorsed by BinaryAge, and it contains no TotalFinder code.

## Behavior

Each trigger (double-tap of a modifier key, or a recorded shortcut) toggles the Visor:

| Visor state | Result |
|---|---|
| Hidden, or never created / closed | **Show**: created if missing (starts in your home folder), placed at the bottom of the screen containing the mouse cursor, full width of that screen's visible area, height set in Settings. It is focused. |
| Visible and not fully covered | **Hide**: the previously frontmost app regains focus. |
| Visible but fully covered by other windows | **Bring to front** (not hidden). |

- Hide is **minimize**, never close: folder, tabs and view state are the same when shown again.
- Closing the Visor yourself (Cmd-W) means the next trigger creates a fresh one at home.
- Other Finder windows are never moved, resized, hidden or closed.
- Hide and show use the macOS minimize/restore animation (about 0.5 s) and the Visor appears as a Dock thumbnail while hidden. This is an accepted trade-off of using a real Finder window with public APIs.
- No always-on-top and no follow-across-Spaces.

## Requirements

- macOS 14 or later (developed on macOS 27)
- Xcode 27 (command line tools)

## Build and install

```sh
make build     # builds build/Build/Products/Release/FinderVisor.app
make test      # runs the VisorCore unit tests (swift test --package-path Packages/VisorCore)
make install   # builds, then copies the app to /Applications/FinderVisor.app
```

Launch it from `/Applications` and always from the same path. Other targets: `make clean`, `make reset-permissions`, `make check-signing`.

### Stable signing (recommended)

macOS ties permission grants to the app's code signature. An ad-hoc signature changes on every build, so grants are lost after each rebuild. Create a stable local identity once.

**Quickest way:** run the script, which creates the certificate in your login keychain and trusts it for code signing (macOS asks for your password), then copy the config in step 4 below:

```sh
scripts/create-signing-cert.sh
```

**Or by hand in Keychain Access:**

1. Open **Keychain Access** > Certificate Assistant > **Create a Certificate...**
2. Name: `FinderVisor Local Signing`; Identity Type: **Self-Signed Root**; Certificate Type: **Code Signing**.
3. Open the new certificate > Trust > set **Code Signing** to **Always Trust**.
4. Copy the config:

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

   It sets `CODE_SIGN_IDENTITY = FinderVisor Local Signing` and `CODE_SIGN_STYLE = Manual`. `Config/Local.xcconfig` is gitignored.

An Apple Development certificate from a free personal team also works (see the comments in the example file).

**Ad-hoc fallback:** without `Config/Local.xcconfig`, or if the named identity is missing or untrusted, `make build` still succeeds but signs ad-hoc and prints a warning. In that case permissions (and possibly the Launch at Login item) reset on every rebuild.

## Permissions

On first launch FinderVisor shows a permissions window. Grant:

| Permission | Why | Where |
|---|---|---|
| **Accessibility** | Position, show and hide the Visor window; detect the hotkeys | System Settings > Privacy & Security > Accessibility |
| **Automation > Finder** | Create the dedicated Finder window | System Settings > Privacy & Security > Automation |

Input Monitoring is normally not needed. Enable it only if the hotkeys do nothing although Accessibility is granted.

On macOS 27 the Privacy & Security list may group or label these panes differently (for example "기기 제어 및 데이터 접근" in Korean). Use the **Grant...** / **Open Settings...** buttons in the permissions window to land on the right pane. The window updates when you grant; no relaunch should be needed.

## Settings

Menu bar icon > **Settings...** has exactly four controls:

1. **Double-tap key**: Option (default), Control, Command, Shift, or Off.
2. **Shortcut**: a recordable key combo (default Option+F); clearable. The combo is consumed and not delivered to the frontmost app.
3. **Visor height**: percent of the screen's visible height (default 50%, range 20-90% in steps of 5).
4. **Launch at Login**.

The menu itself has: Toggle Visor, Settings..., Launch at Login, Quit FinderVisor. Changes apply immediately.

## Limitations and edge cases

- **Tested configuration only:** single display, Dock at the bottom with auto-hide, Stage Manager off. Multiple displays, a left/right Dock and Stage Manager are untested.
- **Finder hidden with Cmd-H**: showing the Visor has to unhide Finder as a whole, so your other Finder windows reappear too (their positions and sizes are not changed). Accepted limitation: macOS has no public API to unhide a single window of a hidden app.
- **Finder > Window > Merge All Windows** while the Visor is key pulls your other windows into the Visor as tabs, and they are hidden with it. FinderVisor does not prevent this.
- **Minimize animation (~0.5 s) and Dock thumbnail** when hiding and showing.
- **Cmd-M** on the Visor: it counts as hidden, so the next trigger restores it at the bottom of the mouse's screen.
- Hotkeys do not work while **Secure Event Input** is active (for example in password fields).
- After a **Finder relaunch**, FinderVisor re-attaches to the restored Visor: a Finder window (minimized or on screen) at the Visor's last frame ±4 pt, with all its tabs. If several windows match, the last known Visor folder breaks the tie. It retries 1, 3 and 6 s after Finder launches and again on the next trigger. If no single match is found, the next trigger creates a new Visor at home, and the old window (if any) stays behind as an ordinary Finder window.
- Moving or rebuilding the app can require re-approving Launch at Login (System Settings > General > Login Items); re-toggle it after moving the app.

## Troubleshooting

**Permission switch is on in System Settings but the hotkeys do nothing** (typical after rebuilding an ad-hoc-signed build): the old grant no longer matches the new binary. Quit FinderVisor, then:

```sh
make reset-permissions
```

Relaunch and grant again. Use stable signing (above) to avoid this.

## Uninstall

1. Turn off Launch at Login, then quit FinderVisor from the menu.
2. `rm -rf /Applications/FinderVisor.app`
3. Optionally `make reset-permissions` first (from the project folder) to clear its permission entries.

## License

[MIT](LICENSE)

---

# 한국어

FinderVisor는 TotalFinder의 **Visor**를 대체하는 macOS 메뉴 막대 앱입니다. 단축키를 누르면 화면 아래쪽에 Finder 창이 나타나고, 다시 누르면 사라집니다.

- **실제 Finder 창**을 사용하므로 탭, 태그, 빠른 보기(Quick Look), Finder 확장이 그대로 동작합니다.
- Finder에 코드를 주입하지 않으며 SIP 변경이 필요 없습니다. 공개 API만 사용합니다.
- 메뉴 막대 전용 앱(Dock 아이콘 없음), 오픈소스, 직접 빌드해서 사용합니다.

## 만든 계기

FinderVisor는 BinaryAge의 [TotalFinder Visor 기능](https://totalfinder.binaryage.com/visor)에서 영감을 받아 만들었습니다. TotalFinder는 Finder에 코드를 불러오는 방식이었는데, 최근 macOS 보안 정책(System Integrity Protection)이 이를 허용하지 않아 Visor를 더 이상 쓸 수 없게 되었습니다. FinderVisor는 그중 Visor 기능 하나만, 공개 API만 쓰는 별도 앱으로 다시 만든 것입니다. BinaryAge와 관련이 없는 독립 프로젝트이며 TotalFinder의 코드는 포함하지 않습니다.

## 동작

| Visor 상태 | 동작 |
|---|---|
| 숨김 / 없음 / 닫힘 | **표시**: 없으면 홈 폴더로 생성, 마우스 커서가 있는 화면 아래쪽에 전체 너비로 배치(높이는 설정값), 포커스됨 |
| 보이고 완전히 가려지지 않음 | **숨김**: 이전에 사용하던 앱으로 포커스 복귀 |
| 보이지만 다른 창에 완전히 가려짐 | **맨 앞으로** 가져옴 (숨기지 않음) |

- 숨김은 닫기가 아니라 **최소화**입니다. 다시 열면 폴더, 탭, 보기 상태가 그대로입니다.
- Visor를 직접 닫으면 다음 호출 때 홈 폴더로 새로 만듭니다.
- 다른 Finder 창은 이동, 크기 변경, 숨김, 닫기를 하지 않습니다.
- 숨기기/표시 시 macOS 최소화 애니메이션(약 0.5초)과 Dock 썸네일이 나타납니다. 공개 API로 실제 Finder 창을 쓰기 위해 받아들인 절충입니다.
- 항상 위 표시, Space 간 따라다니기는 지원하지 않습니다.

## 요구 사항

macOS 14 이상, Xcode 27

## 빌드 및 설치

```sh
make build     # build/Build/Products/Release/FinderVisor.app 생성
make test      # VisorCore 단위 테스트 실행
make install   # 빌드 후 /Applications/FinderVisor.app 으로 복사
```

항상 `/Applications`의 앱을 실행하세요.

### 안정적인 서명 (권장)

권한은 앱의 코드 서명에 묶입니다. ad-hoc 서명은 빌드마다 바뀌어 재빌드 후 권한이 초기화됩니다.

**가장 빠른 방법:** 아래 스크립트가 로그인 키체인에 인증서를 만들고 코드 서명용으로 신뢰 설정까지 합니다(Mac 암호를 물어봅니다). 그다음 아래 4단계의 설정 파일 복사만 하면 됩니다.

```sh
scripts/create-signing-cert.sh
```

**키체인 접근에서 직접 만들려면:**

1. **키체인 접근** > 인증서 지원 > **인증서 생성...**
2. 이름 `FinderVisor Local Signing`, 신원 유형 **자체 서명 루트**, 인증서 유형 **코드 서명**
3. 생성된 인증서 > 신뢰 > **코드 서명**을 **항상 신뢰**로 설정
4. `cp Config/Local.xcconfig.example Config/Local.xcconfig`

**ad-hoc 대체:** `Config/Local.xcconfig`가 없거나 인증서가 없으면 경고와 함께 ad-hoc으로 빌드되며, 재빌드할 때마다 권한(및 로그인 시 열기 항목)이 초기화될 수 있습니다.

## 권한

- **손쉬운 사용(Accessibility)**: 창 배치/숨김, 단축키 감지. 시스템 설정 > 개인정보 보호 및 보안
- **자동화 > Finder**: 전용 Finder 창 생성

macOS 27에서는 개인정보 보호 및 보안 항목의 그룹/이름이 다를 수 있습니다(예: "기기 제어 및 데이터 접근"). 앱의 권한 창에 있는 **Grant...** / **Open Settings...** 버튼으로 해당 패널로 이동하세요. 입력 모니터링은 보통 필요 없으며, 손쉬운 사용을 허용해도 단축키가 동작하지 않을 때만 켜세요.

## 설정

메뉴 막대 아이콘 > **Settings...** 에는 정확히 4가지가 있습니다.

1. **더블탭 키**: Option(기본), Control, Command, Shift, Off
2. **단축키**: 직접 녹화하는 조합(기본 Option+F), 지울 수 있음
3. **Visor 높이**: 화면 높이의 비율(기본 50%, 20-90%, 5% 단위)
4. **로그인 시 실행**

## 제한 사항

- **테스트된 환경만**: 모니터 1대, Dock 아래쪽 자동 숨김, Stage Manager 끔. 그 외 구성은 검증되지 않았습니다.
- Finder가 **Cmd-H**로 가려진 상태에서 Visor를 표시하면 Finder 전체를 다시 보이게 해야 하므로 다른 Finder 창도 함께 나타납니다(위치·크기는 변경되지 않음). 숨겨진 앱의 창 하나만 보이게 하는 공개 API가 없어 감수하는 제한입니다.
- Visor에 **Cmd-M**(최소화)을 누르면 숨김으로 간주되어, 다음 단축키 입력 때 마우스가 있는 화면 아래쪽에 다시 나타납니다.
- Visor가 활성일 때 **Finder > 윈도우 > 모든 윈도우 병합**을 쓰면 다른 창이 Visor의 탭으로 합쳐져 함께 숨겨집니다.
- 최소화 애니메이션(약 0.5초)과 Dock 썸네일이 있습니다.
- 보안 입력(Secure Event Input, 암호 입력란 등) 중에는 단축키가 동작하지 않습니다.
- Finder 재시작 후에는 Visor의 마지막 위치·크기(±4pt)에 있는 Finder 창(최소화 여부 무관, 탭 포함)을 다시 Visor로 연결합니다. 여러 개가 맞으면 마지막으로 기록된 폴더로 구분합니다. Finder 실행 1·3·6초 뒤와 다음 단축키 입력 때 다시 시도하며, 하나로 정해지지 않으면 다음 단축키 입력 때 홈 폴더로 새 Visor를 만들고 이전 창(있다면)은 일반 Finder 창으로 남습니다.

## 문제 해결

시스템 설정에서는 허용돼 있는데 단축키가 동작하지 않으면(ad-hoc 재빌드 후 흔함), FinderVisor를 종료하고 실행하세요.

```sh
make reset-permissions
```

앱을 다시 실행해 권한을 다시 허용합니다.

## 삭제

로그인 시 실행을 끄고 앱을 종료한 뒤 `rm -rf /Applications/FinderVisor.app` 을 실행하세요. 권한 항목은 프로젝트 폴더에서 `make reset-permissions`로 지울 수 있습니다.

## 라이선스

MIT
