A macOS menu-bar app that toggles a real Finder window as a visor at the bottom of the screen. Inspired by TotalFinder's Visor. Requires macOS 14 or later.

## Install

1. Download `FinderVisor-<version>.zip`, unzip it, and move `FinderVisor.app` to `/Applications`.
2. This build is not notarized (ad-hoc signed), so macOS blocks the first launch. Either:
   - open it once, then go to **System Settings > Privacy & Security** and click **Open Anyway**, or
   - run `xattr -dr com.apple.quarantine /Applications/FinderVisor.app` in Terminal.
3. Grant **Accessibility** to FinderVisor and allow it to control **Finder** when asked.

Default hotkeys: double-tap **Option**, or **Option+F**. Change them, the Visor height and Launch at Login from the menu-bar icon's Settings.

Building it yourself with a stable signing identity keeps permissions across updates; see the [README](https://github.com/Dennyanne/FinderVisor#readme).

## 한국어

1. `FinderVisor-<버전>.zip`을 받아 압축을 풀고 `FinderVisor.app`을 `/Applications`로 옮깁니다.
2. 공증되지 않은(ad-hoc 서명) 빌드라 처음 실행이 차단됩니다. 한 번 실행한 뒤 **시스템 설정 > 개인정보 보호 및 보안**에서 **그래도 열기**를 누르거나, 터미널에서 `xattr -dr com.apple.quarantine /Applications/FinderVisor.app`을 실행하세요.
3. FinderVisor에 **손쉬운 사용** 권한을 주고, Finder 제어 허용 창이 뜨면 허용합니다.

기본 단축키는 **Option 두 번** 또는 **Option+F**입니다. 메뉴 막대 아이콘의 설정에서 단축키, Visor 높이, 로그인 시 실행을 바꿀 수 있습니다.
