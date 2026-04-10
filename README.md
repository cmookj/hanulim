# 하늘입력기 (Hanulim) 한국어 입력기

macOS용 한국어 입력기입니다. InputMethodKit(IMK) 프레임워크를 기반으로 하며, 현대 및 옛한글 자판 배열을 지원합니다.

## 저작권 및 라이선스

이 소프트웨어는 [GNU General Public License v2](COPYING)에 따라 배포됩니다.

- 원작자: Copyright (C) 2007-2017 Sanghyuk Suh \<han9kin@mac.com\>
- Swift 포팅 및 추가 개발: Copyright (C) 2026 Changmook Chun \<cmookj@duck.com\>

원본 Objective-C 소스는 Sanghyuk Suh가 작성하였으며, Google Code(`code.google.com/p/hanulim`)에 GPL v2로 공개되어 있었습니다. 이 저장소는 해당 소스를 Swift로 번역하고 현대 macOS(Sequoia)에 맞게 수정한 파생 저작물입니다. GPL v2의 조건에 따라 이 파생 저작물도 동일한 GPL v2 라이선스로 배포합니다.

---

## 목차

1. [프로젝트 구조](#1-프로젝트-구조)
2. [부트스트랩 순서](#2-부트스트랩-순서)
3. [InputMethodKit 아키텍처](#3-inputmethodkit-아키텍처)
4. [한글 조합 엔진](#4-한글-조합-엔진)
5. [ESC 키 전환](#5-esc-키-전환)
6. [약어 확장 시스템](#6-약어-확장-시스템)
7. [입력 소스 등록](#7-입력-소스-등록)
8. [사용자 환경설정](#8-사용자-환경설정)
   - [switchesToRomanOnEsc](#switchestoromanonesc--vivim-사용자를-위한-esc-자동-전환)
9. [디버그 로깅](#9-디버그-로깅)
10. [권한 설정](#10-권한-설정)

[부록: 내장 로마자 모드 시도 이력](#부록-내장-로마자-모드-시도-이력)

---

## 1. 프로젝트 구조

Xcode 프로젝트는 세 개의 타겟으로 구성됩니다.

| 타겟 | 종류 | 역할 |
|------|------|------|
| **Hanulim** | Input Method Bundle | 실제 한글 입력 처리 (핵심 타겟) |
| **AbbrevEdit** | macOS App | 약어 데이터베이스 편집 GUI |
| **abbrevtool** | CLI Tool | 약어 데이터 가져오기 도구 |

### 주요 파일

```
hanulim/
├── InputMethod/
│   ├── main.swift                   부트스트랩 진입점
│   ├── HNInputController.swift      IMK 컨트롤러 (키 이벤트 수신, 분기)
│   ├── HNInputContext.swift         한글 오토마타
│   ├── HNEventTap.swift             전역 키 인터셉터 (CGEventTap; ESC)
│   ├── HNCandidates.swift           약어 후보 데이터 모델
│   ├── HNCandidatesController.swift 약어 후보 패널 관리
│   ├── HNAppController.swift        앱 컨트롤러
│   ├── HNUserDefaults.swift         사용자 환경설정
│   └── Info.plist                   입력 소스, 자판 등록
├── HNDataController.swift           CoreData 스택 (약어 DB)
├── HNDebug.swift                    디버그 로깅 유틸리티
└── *.png                            메뉴바 아이콘 리소스
```

---

## 2. 부트스트랩 순서

`main.swift`는 `NSApplicationMain` 없이 수동으로 실행 흐름을 제어합니다.

```
main.swift (autoreleasepool)
 │
 ├─ 1. TISRegisterInputSource(bundle.bundleURL)
 │      로그아웃 없이 새 입력 모드 아이콘·설정을 시스템에 반영합니다.
 │
 ├─ 2. HNEventTap.shared.start()
 │      ESC(조합 중, switchesToRomanOnEsc 켜짐) 이벤트를 앱보다 먼저 가로채는
 │      CGEventTap을 설치합니다.
 │      (접근성 권한 필요. 없으면 listen-only 또는 폴백 모드로 동작)
 │
 ├─ 3. IMKServer(name:bundleIdentifier:)
 │      IMK 서버를 생성합니다. 앱들이 이 서버를 통해 입력기에 연결됩니다.
 │
 ├─ 4. HNCandidatesController(server:)
 │      CoreData 스택을 초기화하고 약어 DB 파일을 로드합니다.
 │
 ├─ 5. Bundle.main.loadNibNamed("MainMenu", ...)
 │      MainMenu.nib에서 HNAppController 인스턴스를 생성합니다.
 │
 └─ 6. NSApplication.shared.run()
        이벤트 루프를 시작합니다.
```

---

## 3. InputMethodKit 아키텍처

### 이벤트 흐름

```
macOS 이벤트 큐
 │
 ├─ [HNEventTap 활성 시] ESC (조합 중, switchesToRomanOnEsc 켜짐) 소비
 │       → 조합 커밋·ASCII 레이아웃 전환·합성 ESC 전송
 │
 └─ 나머지 이벤트 → 포커스된 앱 → NSTextInputContext.handleEvent()
                                          │
                                          └─ HNInputController.handle(_:client:)
```

### HNInputController

`IMKInputController`를 상속한 핵심 클래스입니다. IMK가 각 클라이언트 앱의 포커스 변경마다 인스턴스를 생성합니다.

#### 주요 메서드

**`handle(_:client:) → Bool`**

모든 키 입력의 진입점입니다. `inputText(_:key:modifiers:client:)` 대신 이 메서드를 사용하는 이유는, `inputText`가 `false`를 반환할 때 IMK의 텍스트 처리를 거쳐 터미널 에뮬레이터에 키 이벤트가 확실하게 전달되지 않는 문제가 있기 때문입니다.

분기 로직:

```
keyDown 이벤트 수신
 │
 ├─ ESC (변경키 없음, switchesToRomanOnEsc 켜짐, 소비 탭 없음): ASCII 전환
 │   → 조합 커밋 후 TISSelectInputSource(ASCII) 호출, ESC 통과 (false 반환)
 │   → 소비 탭이 활성화된 경우에는 탭에서 먼저 처리되어 이 경로에 도달하지 않음
 │
 ├─ Option+Return: 조합 중인 문자열로 약어 후보 검색
 │
 └─ 그 외: HNInputContext.handleKey() 위임
```

**`setValue(_:forTag:client:)`**

시스템이 입력 모드를 전환할 때 호출됩니다. `kTSMDocumentInputModePropertyTag` 태그와 함께 입력 모드 ID(예: `org.cocomelo.inputmethod.Hanulim.3final`)를 받아 `inputContext.setKeyboardLayout(name:)`으로 자판 배열을 전환합니다.

**`recognizedEvents(_:) → Int`**

조합 중에는 마우스 클릭도 수신하여 즉시 커밋 처리를 합니다.

```swift
// 조합 중: 키 입력 + 마우스 클릭 수신
mask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

// 조합 없음: 키 입력만 수신
mask = [.keyDown]
```

---

## 4. 한글 조합 엔진

`HNInputContext.swift`에 구현된 핵심 엔진입니다.

### 지원 자판

| ID 접미사 | 이름 | 종류 | 범위 |
|-----------|------|------|------|
| `2standard` | 두벌식 표준 | 자모 | 현대 |
| `2archaic` | 두벌식 옛한글 | 자모 | 옛한글 |
| `3final` | 세벌식 최종 | 자소 | 현대 |
| `390` | 세벌식 390 | 자소 | 현대 |
| `3noshift` | 세벌식 무확장 | 자소 | 현대 |
| `393` | 세벌식 393 | 자소 | 옛한글 |

**자모(Jamo) 방식**: 두벌식처럼 초성·종성을 같은 키로 입력하며, 위치에 따라 자동으로 초성/종성을 결정합니다.

**자소(Jaso) 방식**: 세벌식처럼 초성·중성·종성 자리를 별도의 키로 명시적으로 입력합니다.

**세벌식 무확장**: shift 키를 사용하지 않고 현재 한글 전체를 입력할 수 있는 세벌식 자판.

### 자판 배열 데이터 구조

```swift
struct HNKeyboardLayout {
    let name: String
    let type: HNKeyboardLayoutType    // .jamo 또는 .jaso
    let scope: HNKeyboardLayoutScope  // .modern 또는 .archaic
    let value: [UInt32]               // 키 코드 0~50번 항목, 51개
}
```

각 `value` 항목은 32비트 값으로, 상위 16비트는 Shift 입력 시, 하위 16비트는 일반 입력 시의 코드입니다. 16비트 코드에서 상위 바이트는 키 종류(0=기호, 1=초성, 2=중성, 3=종성, 4=방점), 하위 바이트는 해당 자소의 인덱스입니다.

### 한글 오토마타

**상태 저장 구조체:**

```swift
struct HNCharacter {
    var type: UInt8      // 현재 상태: 0=없음, 1=초성, 2=중성, 3=종성
    var initial:  UInt8  // 초성 인덱스
    var medial:   UInt8  // 중성 인덱스
    var final_:   UInt8  // 종성 인덱스
    var diacritic: UInt8 // 방점
}
```

**`handleKey()` 처리 흐름:**

```
키 입력
 │
 ├─ Ctrl/Cmd/Option 변경키 조합: 통과
 │
 ├─ 기호 키:
 │    현재 조합 커밋 → 기호 직접 삽입
 │
 ├─ 한글 자소:
 │    keyBuffer에 추가 → compose() 실행 → 조합 미리보기 갱신
 │
 └─ 그 외 (Space, Return 등):
      현재 조합 커밋 → false 반환 (앱이 처리)
```

**`compose()` 음절 조합 알고리즘:**

두벌식(jamo)과 세벌식(jaso) 모두 이 함수를 거칩니다. 세벌식은 키가 이미 초성·중성·종성으로 명시적 태깅되어 있어 아래의 초성→종성 변환 분기가 실행되지 않습니다.

```
새 자소 입력
 │
 ├─ [중성 뒤에 초성 입력] 종성 후보로 변환 시도
 │    hnJasoInitialToFinal[] 테이블로 초성→종성 변환
 │    기존 종성과 합성 가능하면 겹받침 구성
 │
 ├─ [완성 음절 뒤에 중성 입력] 분리 처리
 │    종성을 분리해 다음 음절의 초성으로 이동
 │    겹받침이면 한 자소만 분리
 │
 ├─ [같은 종류의 자소] 합성 테이블 조회
 │    hnJasoCompositionIn/Out[] 으로 겹자음·겹모음 구성
 │    예: ㄱ + ㄱ → ㄲ,  ㅗ + ㅏ → ㅘ
 │
 └─ [조합 불가] 현재 음절 커밋, 새 음절 시작
```

**`composeCharacter()` 유니코드 변환:**

| 설정 | 출력 방식 | 예시 |
|------|-----------|------|
| NFC (기본) | 완성형 한글 음절 블록 | `ㄱ + ㅏ + ㄴ` → `간` (U+AC04) |
| NFD | 자소 분리형 (옛한글·분리 유니코드) | `ㄱ` → U+1100, `ㅏ` → U+1161 |

NFC 완성형 공식: `U+AC00 + (초성−1)×588 + (중성−1)×28 + 종성`

---

## 5. ESC 키 전환

`switchesToRomanOnEsc` 옵션이 켜진 경우, 하늘입력기 한글 모드에서 ESC를 누르면 현재 조합 중인 음절을 커밋하고 시스템의 ASCII 레이아웃(ABC 등)으로 전환합니다. vi/vim 사용자가 입력 모드를 나올 때 입력기도 함께 로마자로 전환되도록 하기 위한 기능입니다.

### 전환 방식

ASCII 레이아웃 전환은 `TISCopyCurrentASCIICapableKeyboardLayoutInputSource()`로 대상을 동적으로 찾아 `TISSelectInputSource()`를 호출합니다. 레이아웃 ID를 하드코딩하지 않으므로 ABC, US, Dvorak 등 사용자가 설정한 레이아웃에 자동으로 대응합니다.

이 경우 `TISSelectInputSource` 호출은 안전합니다. 하늘입력기 내부 모드 간 전환이 아니라 **완전히 다른 입력 소스로의 전환**이기 때문입니다. 하늘입력기의 IMK 세션은 정상적으로 종료되고, ABC는 IMK 컨트롤러 초기화가 필요 없습니다. 이후 사용자가 다시 하늘입력기를 선택하면 시스템이 새 IMK 세션을 올바르게 생성합니다. (자세한 배경은 [부록](#부록-내장-로마자-모드-시도-이력) 참조)

### 2계층 구조

```
계층 1: HNEventTap (CGEventTap, 시스템 수준)
 │  앱보다 먼저 이벤트를 가로채 처리합니다.
 │  접근성 권한이 있을 때만 소비 모드로 동작합니다.
 │    • ESC (조합 중)  → 조합 커밋·ASCII 전환·합성 ESC 전송, 이벤트 소비
 │    • ESC (조합 없음) → ASCII 전환(비동기), 이벤트 통과
 │
 └─ 권한 없을 경우 폴백 →

계층 2: HNInputController.handle() (IMK 수준)
    소비 탭이 없을 때 ESC를 처리합니다.
    터미널 에뮬레이터에서 조합 중 ESC는 두 번 입력이 필요할 수 있습니다.
```

### ESC 처리 상세

| 상태 | ESC 처리 |
|------|---------|
| 조합 없음 | 원본 ESC 통과, ASCII 전환은 비동기 부수 효과 |
| 조합 중 (preedit 있음) | 원본 ESC 소비 후 조합 커밋·ASCII 전환·합성 ESC 전송 |

**조합 없음**: ESC 이벤트는 소비하지 않고 앱에 그대로 전달됩니다. ASCII 전환은 비동기로 수행되므로 vi/vim은 ESC를 정상 수신하여 명령 모드로 전환됩니다.

**조합 중**: Ghostty, Terminal.app 등 터미널 에뮬레이터는 preedit(조합 중인 음절)이 표시된 상태에서 ESC가 입력되면, 이를 "preedit 해제" 이벤트로 분류하고 PTY(neovim 등)로 전달하지 않습니다. 이를 해결하기 위해 CGEventTap이 원본 ESC를 **소비**하고 메인 스레드에서 다음 순서로 처리합니다.

1. `HNInputController.commitForEsc()`: 조합 중인 음절을 클라이언트에 삽입
2. `HNEventTap.shared.switchToASCII()`: `TISSelectInputSource(ASCII)` 호출
3. 합성 ESC 이벤트 전송 (`.cgAnnotatedSessionEventTap`): preedit가 없는 상태에서 도착하므로 터미널이 PTY로 정상 전달 → neovim/vim이 명령 모드로 전환

### HNEventTap 탭 콜백

```swift
if keyCode == 53 && noModifiers && switchesToRomanOnEsc && isCurrentlyHanulimMode() {
    if HNInputContext.isComposing {
        DispatchQueue.main.async {
            HNInputController.active?.commitForEsc()
            HNEventTap.shared.switchToASCII()
            // 합성 ESC: preedit 없음 → 터미널이 PTY로 정상 전달
            let src = CGEventSource(stateID: .hidSystemState)
            CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)?
                .post(tap: .cgAnnotatedSessionEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)?
                .post(tap: .cgAnnotatedSessionEventTap)
        }
        return nil  // 원본 소비
    } else {
        DispatchQueue.main.async {
            if HNEventTap.shared.isCurrentlyHanulimMode() {
                HNEventTap.shared.switchToASCII()
            }
        }
    }
}
```

---

## 6. 약어 확장 시스템

한글 약어를 완성된 문자열로 자동 확장하는 기능입니다.

### 동작 흐름

```
사용자가 약어 입력 후 Option+Return 누름
 │
 ├─ HNInputContext.composedString으로 CoreData 검색
 │    fetchRequest: abbrev.abbrev == $ABBREV
 │
 ├─ 결과가 있으면 IMKCandidates 패널 표시
 │    패널 종류: kIMKSingleRowSteppingCandidatePanel (단일 행 탐색)
 │
 ├─ 사용자가 항목 선택
 │    candidateSelected() → client.insertText(expansion)
 │
 └─ 주석 표시
      candidateSelectionChanged() → IMKCandidates.showAnnotation()
```

### 데이터 구조

약어 데이터베이스는 CoreData(SQLite)를 사용합니다.

- **위치**: `~/Library/Application Support/Hanulim/Abbrevs/*.db`
- **엔티티**: `Expansion`
  - `abbrev`: 약어 (예: "salam")
  - `expansion`: 확장 문자열 (예: "안녕하세요")
  - `annotation`: 설명 텍스트

여러 `.db` 파일이 있으면 모두 로드되어 함께 검색됩니다.

### 관련 클래스

**`HNCandidates`**: 단일 약어에 대한 후보 목록과 주석 맵을 보관합니다.

**`HNCandidatesController`**: IMKCandidates 패널과 CoreData 검색 요청을 관리하는 싱글턴입니다. `IMKServer` 초기화 시 생성되며 앱 종료 시까지 유지됩니다.

**`HNDataController`**: CoreData 퍼시스턴트 스토어 코디네이터와 매니지드 오브젝트 컨텍스트를 관리하는 싱글턴입니다.

---

## 7. 입력 소스 등록

`InputMethod/Info.plist`의 `tsInputModeListKey`에서 6개의 입력 모드를 등록합니다.

### 모드 목록

| 모드 ID 접미사 | 표시 이름 | 기본 활성 | 아이콘 |
|----------------|-----------|-----------|--------|
| `2standard` | 두벌식 표준 | 예 | hanulim2.png |
| `2archaic` | 두벌식 옛한글 | 아니오 | hanulim2a.png |
| `3final` | 세벌식 최종 | 예 | hanulim3.png |
| `390` | 세벌식 390 | 아니오 | hanulim3o.png |
| `3noshift` | 세벌식 무확장 | 아니오 | hanulim3n.png |
| `393` | 세벌식 393 | 아니오 | hanulim3a.png |

각 모드는 시스템 설정 → 키보드 → 입력 소스에서 개별적으로 추가할 수 있습니다.

### 주요 plist 키

| 키 | 설명 |
|----|------|
| `TISInputSourceID` | 입력 소스 고유 ID |
| `TISIntendedLanguage` | 대상 언어 (`ko`) |
| `tsInputModeIsVisibleKey` | 메뉴 막대에 표시 여부 |
| `tsInputModeDefaultStateKey` | 설치 시 기본 활성 여부 |
| `tsInputModeMenuIconFileKey` | 메뉴 아이콘 파일 이름 |
| `tsInputModePrimaryInScriptKey` | 해당 스크립트의 주 입력기 여부 |
| `tsInputModeScriptKey` | 스크립트 종류 (`smKorean`) |

---

## 8. 사용자 환경설정

`HNUserDefaults`는 `UserDefaults.standard`를 감싸고, 변경 알림을 관찰하여 실시간으로 반영합니다.

| 설정 키 | 역할 |
|---------|------|
| `usesSmartQuotationMarks` | 스마트 따옴표 사용 ('' "" ↔ '' "") |
| `inputsBackSlashInsteadOfWon` | 원화 기호(₩) 대신 역슬래시(\\) 입력 |
| `handlesCapsLockAsShift` | CapsLock을 Shift로 처리 |
| `commitsImmediately` | 음절 완성 즉시 삽입 (조합 중 상태 없음) |
| `usesDecomposedUnicode` | NFD 자소 분리 유니코드 사용 |
| `switchesToRomanOnEsc` | ESC 키 입력 시 ASCII 레이아웃으로 자동 전환 (기본값: false) |

---

### `switchesToRomanOnEsc` — vi/vim 사용자를 위한 ESC 자동 전환

이 옵션을 활성화하면 하늘입력기 한글 모드에서 ESC 키를 누를 때 현재 조합 중인 음절을 커밋하고 시스템 ASCII 레이아웃(ABC 등)으로 전환됩니다. vi/vim에서 입력 모드를 빠져나올 때 입력기도 함께 로마자로 전환되므로, 명령 모드에서 한글이 입력되는 불편함을 없애줍니다.

기본값은 `false`입니다. 대부분의 사용자에게는 불필요한 기능이므로, vi/vim 사용자만 활성화하면 됩니다.

**동작 조건:**
- 현재 입력 소스가 하늘입력기 한글 모드일 것
- ESC 단독 입력일 것 (다른 변경키 조합 제외)
- 다른 입력기(ABC 등)가 활성화된 상태에서는 동작하지 않음

**활성화 방법:**

```bash
defaults write org.cocomelo.inputmethod.Hanulim switchesToRomanOnEsc -bool true
killall Hanulim
```

**비활성화 방법 (기본값):**

```bash
defaults write org.cocomelo.inputmethod.Hanulim switchesToRomanOnEsc -bool false
killall Hanulim
```

---

## 9. 디버그 로깅

`HNDebug.swift`는 `/tmp/hanulim.log` 파일에 비동기로 로그를 기록합니다. 로그 파일이 존재하지 않으면 새로 생성하고, 존재하면 끝에 추가합니다. `#if DEBUG` 조건부 컴파일 가드는 없으므로 **릴리스 빌드에서도 로그 파일이 존재하면 기록됩니다.**

로그를 확인하려면:

```bash
touch /tmp/hanulim.log
killall Hanulim          # IME 프로세스 재시작
tail -f /tmp/hanulim.log
```

로그를 끄려면 파일을 삭제하면 됩니다:

```bash
rm /tmp/hanulim.log
```

---

## 10. 권한 설정

CGEventTap 소비 모드(이벤트를 앱보다 먼저 차단하는 방식)는 macOS의 접근성 권한이 필요합니다. `switchesToRomanOnEsc`가 꺼진 경우(기본값)에는 이 권한이 불필요합니다.

**설정 경로**: 시스템 설정 → 개인정보 보호 및 보안 → 접근성 → Hanulim 추가

권한이 없는 경우, `switchesToRomanOnEsc`가 켜진 상태에서 다음과 같은 부작용이 있습니다.

- **ESC (조합 중)**: Ghostty, Terminal.app 등 터미널 에뮬레이터에서 한글 조합 중에 ESC를 누르면 두 번 입력이 필요합니다. VimR 등 네이티브 macOS GUI 앱은 영향 없습니다.

접근성 권한 부여 후 `killall Hanulim`으로 프로세스를 재시작하면 소비 모드 탭이 활성화됩니다. 로그에서 `tap installed (consuming=true)` 메시지로 확인할 수 있습니다.

### 개발 중 권한 재설정 (빌드할 때마다 필요)

macOS는 앱 바이너리가 변경되면(빌드할 때마다) 해당 번들의 코드 서명이 바뀌었다고 판단하여 **접근성 권한을 자동으로 취소**합니다. 스위치를 껐다 켜는 것만으로는 복원되지 않으며, 반드시 다음 절차를 따라야 합니다.

1. 시스템 설정 → 개인정보 보호 및 보안 → 접근성 열기
2. 목록에서 Hanulim을 선택하고 **−** 버튼으로 **삭제**
3. **+** 버튼으로 Hanulim을 **다시 추가** (`/Library/Input Methods/Hanulim.app`)
4. 스위치를 켬 상태로 확인
5. `killall Hanulim` 으로 IME 프로세스 재시작

```bash
killall Hanulim
```

재시작 후 로그에서 `tap installed (consuming=true)`가 보이면 정상입니다.

```bash
grep "tap installed" /tmp/hanulim.log | tail -1
```

> **참고**: 이 제약은 릴리스 빌드를 배포한 뒤에는 발생하지 않습니다. 바이너리가 바뀌지 않으므로 권한이 유지됩니다.

---

## 부록: 내장 로마자 모드 시도 이력

이 부록은 하늘입력기 내부에 로마자 입력 모드를 구현하려 했던 시도와 그 실패 원인을 기록합니다. 동일한 문제를 반복 조사하지 않도록 남겨 둡니다.

### ComponentInputModeDict 아키텍처

하늘입력기의 모든 입력 모드는 단일 컴포넌트 입력 소스(`org.cocomelo.inputmethod.Hanulim`) 안에 *입력 모드(input mode)*로 등록됩니다. 이를 ComponentInputModeDict 구조라고 합니다. 이 구조에서 시스템이 모드를 전환하는 방식은 새 컨트롤러를 생성하는 것이 아니라, 기존 `HNInputController` 인스턴스에 `setValue(_:forTag:kTSMDocumentInputModePropertyTag:client:)`를 호출하는 것입니다.

### 시도한 내용

한국어 입력기 내에 `org.cocomelo.inputmethod.Hanulim.Roman` 모드를 ComponentInputModeDict에 추가하고, Shift+Space/ESC 키로 한글 모드와 로마자 모드를 토글하는 기능을 구현하려 했습니다.

### TISSelectInputSource 호출 시 IMK 세션 파괴 문제

**`TISSelectInputSource`를 어느 프로세스에서 호출하더라도, 하늘입력기 모드 ID(`org.cocomelo.inputmethod.Hanulim.*`)를 대상으로 하면 IMK 세션이 파괴됩니다.**

TextEdit 등 Cocoa 앱은 `deactivateServer`를 호출하지만 새 `initWithServer`/`activateServer`를 호출하지 않아, 이후 모든 키 입력이 입력기를 우회합니다.

메뉴 막대에서 모드를 선택할 때는 SystemUIServer가 IMKit의 **비공개 XPC 경로**를 통해 전환하므로 세션이 유지됩니다. 그러나 이 경로는 앱 코드에서 접근할 수 없습니다.

시도한 방법과 결과:

| 방법 | 결과 |
|------|------|
| 입력기 프로세스 내에서 직접 호출 | 세션 파괴 |
| `hnswitch` 자식 프로세스에서 호출 | 동일하게 세션 파괴 |
| 150ms 지연 후 호출 | 동일하게 세션 파괴 |

### setValue 직접 호출로의 전환

세션을 유지하면서 모드를 전환하는 유일한 방법은 `TISSelectInputSource` 없이 활성 컨트롤러에 직접 `setValue(_:forTag:client:)`를 호출하는 것입니다. 이 방식으로 Shift+Space 토글이 동작하도록 구현하는 데 성공했습니다. 그러나 TIS 상태가 갱신되지 않아 **메뉴 막대 아이콘이 변경되지 않는** 한계가 있었습니다. TIS를 업데이트하지 않으면 아이콘을 갱신할 공개 API가 없습니다.

### 내장 로마자 모드 폐기 결정

메뉴 막대 아이콘 미반영 문제 외에도, 시스템 단축키(시스템 설정 → 키보드 → 단축키 → 입력 소스)로 Shift+Space를 ABC 전환에 사용할 수 있어 내장 로마자 모드 전체를 제거하고, ESC 키에 한해 `TISSelectInputSource(ABC)`를 직접 호출하는 방식으로 단순화했습니다. 하늘입력기에서 **완전히 다른 입력 소스**로 전환할 때는 IMK 세션이 정상 종료되므로 세션 파괴 문제가 발생하지 않습니다.

### hnswitch 헬퍼 도구

위 과정에서 `InputSwitcher/main.swift`(`hnswitch`)라는 CLI 헬퍼 도구를 별도 프로세스로 만들어 `TISSelectInputSource`를 호출하는 방법도 시도했습니다. 그러나 별도 프로세스에서 호출해도 세션 파괴가 동일하게 발생하여 사용을 중단했고, 최종적으로 프로젝트에서 완전히 제거했습니다.
