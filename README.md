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
5. [로마자 모드 전환](#5-로마자-모드-전환)
6. [약어 확장 시스템](#6-약어-확장-시스템)
7. [입력 소스 등록](#7-입력-소스-등록)
8. [사용자 환경설정](#8-사용자-환경설정)
   - [usesShiftSpaceForRomanMode](#usesshiftspaceforromanmode--shiftspace-로마자-모드-전환)
   - [switchesToRomanOnEsc](#switchestoromanonesc--vivim-사용자를-위한-esc-자동-전환)
9. [디버그 로깅](#9-디버그-로깅)
10. [권한 설정](#10-권한-설정)

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
│   ├── main.swift                  부트스트랩 진입점
│   ├── HNInputController.swift     IMK 컨트롤러 (키 이벤트 수신·분기)
│   ├── HNInputContext.swift        한글 오토마타
│   ├── HNEventTap.swift            Shift+Space 전역 인터셉터 (CGEventTap)
│   ├── HNCandidates.swift          약어 후보 데이터 모델
│   ├── HNCandidatesController.swift 약어 후보 패널 관리
│   ├── HNAppController.swift       메뉴 공급자
│   ├── HNUserDefaults.swift        사용자 환경설정 래퍼
│   └── Info.plist                  입력 소스·자판 등록
├── HNDataController.swift          CoreData 스택 (약어 DB)
├── HNDebug.swift                   디버그 로깅 유틸리티
└── *.png                           메뉴 막대 아이콘 자산
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
 │      Shift+Space를 앱보다 먼저 가로채는 CGEventTap을 설치합니다.
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
 ├─ [HNEventTap 활성 시] Shift+Space 이벤트 소비 (앱 도달 전)
 │
 └─ 나머지 이벤트 → 포커스된 앱 → NSTextInputContext.handleEvent()
                                          │
                                          └─ HNInputController.handle(_:client:)
```

### HNInputController

`IMKInputController`를 상속한 핵심 클래스입니다. IMK가 각 클라이언트 앱의 포커스 변경마다 인스턴스를 생성합니다.

#### 주요 메서드

**`handle(_:client:) → Bool`**

모든 키 입력의 진입점입니다. `inputText(_:key:modifiers:client:)` 대신 이 메서드를 사용하는 이유는, `inputText`가 `false`를 반환할 때 IMK의 텍스트 처리 기계를 거쳐 터미널 에뮬레이터에 키 이벤트가 확실하게 전달되지 않는 문제가 있기 때문입니다.

분기 로직:

```
keyDown 이벤트 수신
 │
 ├─ Shift+Space (keyCode 49, Shift만 단독): toggleRomanMode()
 │   → HNEventTap이 소비 모드면 여기에 도달하지 않음 (폴백 경로)
 │
 ├─ ESC (수식키 없음, switchesToRomanOnEsc 켜짐, 한글 모드): 로마자 모드로 전환
 │   → 조합 커밋 후 통과 (false 반환)
 │   → HNEventTap이 소비 모드면 여기에 도달하지 않음 (폴백 경로)
 │   → 터미널 에뮬레이터에서는 조합 중일 때 CGEventTap 계층이 처리
 │
 ├─ Option+Return: 조합 중인 문자열로 약어 후보 검색
 │
 └─ 그 외: HNInputContext.handleKey() 위임
```

**`setValue(_:forTag:client:)`**

시스템이 입력 소스를 전환할 때 호출됩니다. `kTSMDocumentInputModePropertyTag` 태그와 함께 입력 모드 ID(예: `org.cocomelo.inputmethod.Hanulim.3final`)를 받아 두 가지 작업을 수행합니다.

- `inputContext.setKeyboardLayout(name:)` → 자판 배열 전환 및 `isRomanMode` 갱신
- `HNEventTap.shared.lastKoreanModeID` 갱신 (로마자 모드에서 돌아올 목적지 기억)

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
 ├─ 로마자 모드: 그대로 통과 (조합 없음)
 ├─ Ctrl/Cmd/Option 수식키 조합: 통과
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

**`compose()` 자모 조합 알고리즘 (두벌식):**

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

## 5. 로마자 모드 전환

Shift+Space로 한글 조합을 일시 중단하고 로마자(영문)를 직접 입력하는 모드입니다. 로마자 모드는 별도의 입력 소스(`org.cocomelo.inputmethod.Hanulim.Roman`)로 등록되어 있어 메뉴 막대 아이콘도 함께 전환됩니다.

### 2계층 구조

```
계층 1: HNEventTap (CGEventTap, 시스템 수준)
 │  앱보다 먼저 Shift+Space를 가로채 이벤트를 소비합니다.
 │  접근성 권한이 있을 때만 동작합니다.
 │
 └─ 권한 없을 경우 폴백 →

계층 2: HNInputController.handle() (IMK 수준)
    앱이 이미 처리한 후에 입력기에 전달된 이벤트를 받아 모드를 전환합니다.
    Ghostty 등 이벤트를 미리 처리하는 앱에서 공백이 삽입되는 부작용이 있습니다.
```

### HNEventTap 상세

**`start()` 초기화 순서:**

```
1. CGEvent.tapCreate(.cgSessionEventTap, .headInsertEventTap, .defaultTap) 시도
   ├─ 성공: isConsuming = true, 탭 설치 완료
   └─ 실패 (접근성 권한 없음):
        ├─ AXIsProcessTrustedWithOptions() → 시스템 설정 접근성 화면 열기
        ├─ CGPreflightListenEventAccess() 확인
        ├─ 필요시 CGRequestListenEventAccess() → 입력 모니터링 화면 열기
        └─ CGEvent.tapCreate(..., .listenOnly) 시도 (진단 전용)
```

**탭 콜백 (C 호환 함수):**

```swift
{ _, type, event, _ -> Unmanaged<CGEvent>? in
    // ── Shift+Space ──────────────────────────────────────────
    if isShiftSpace && usesShiftSpaceForRomanMode {
        if HNEventTap.shared.isConsuming {
            DispatchQueue.main.async { HNEventTap.shared.toggleRomanMode() }
            return nil  // 이벤트 소비 → 앱에 전달되지 않음
        } else {
            return Unmanaged.passRetained(event)  // 통과 (폴백에서 처리)
        }
    }

    // ── ESC (수식키 없음, switchesToRomanOnEsc 켜짐, 한글 모드) ──
    if isEsc && switchesToRomanOnEsc && isKoreanMode {
        if HNInputContext.isComposing {
            // 조합 중: 원본 ESC 소비 후 조합 커밋·모드 전환·합성 ESC 전송
            // 터미널 에뮬레이터는 조합 중 ESC를 preedit 해제로 처리하여
            // PTY로 전달하지 않으므로, CGEventTap 계층에서 직접 처리해야 함
            DispatchQueue.main.async {
                HNInputController.active?.commitForEsc()
                HNEventTap.shared.selectInputSource(id: romanModeID)
                // 합성 ESC: preedit 없음 → 터미널이 PTY로 정상 전달
                CGEvent(virtualKey: 53, keyDown: true)?.post(tap: .cgAnnotatedSessionEventTap)
                CGEvent(virtualKey: 53, keyDown: false)?.post(tap: .cgAnnotatedSessionEventTap)
            }
            return nil  // 원본 소비
        } else {
            // 조합 없음: 모드 전환 후 원본 통과 → 앱이 ESC를 그대로 수신
            DispatchQueue.main.async { HNEventTap.shared.selectInputSource(id: romanModeID) }
        }
    }

    return Unmanaged.passRetained(event)
}
```

**`toggleRomanMode()` 전환 로직:**

```swift
func toggleRomanMode() {
    // TIS에서 현재 모드를 직접 읽어 판단 (인스턴스 상태에 의존하지 않음)
    let targetID = isCurrentlyRomanMode()
        ? lastKoreanModeID              // 로마자 → 마지막 한글 자판으로 복귀
        : "...Hanulim.Roman"            // 한글 → 로마자 모드로 전환
    TISSelectInputSource(source(for: targetID))
}
```

TIS 선택 후 macOS가 `setValue(_:forTag:client:)`를 호출하여 `HNInputContext.isRomanMode`와 `lastKoreanModeID`를 자동으로 갱신합니다.

### 상태 동기화

```
TISSelectInputSource()
 │
 └─ setValue(_:forTag:client:) 호출됨 (macOS → HNInputController)
      ├─ inputContext.setKeyboardLayout(name:)
      │    isRomanMode  ← (name == Roman) ? true : false
      │    lastKoreanModeID ← name  (로마자 모드가 아닌 경우만 갱신)
      │
      └─ HNEventTap.shared.lastKoreanModeID ← name  (로마자 모드가 아닌 경우만)
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

`InputMethod/Info.plist`의 `tsInputModeListKey`에서 7개의 입력 모드를 등록합니다.

### 모드 목록

| 모드 ID 접미사 | 표시 이름 | 기본 활성 | 아이콘 |
|----------------|-----------|-----------|--------|
| `2standard` | 두벌식 표준 | 예 | hanulim2.png |
| `2archaic` | 두벌식 옛한글 | 아니오 | hanulim2a.png |
| `3final` | 세벌식 최종 | 예 | hanulim3.png |
| `390` | 세벌식 390 | 아니오 | hanulim3o.png |
| `3noshift` | 세벌식 무확장 | 아니오 | hanulim3n.png |
| `393` | 세벌식 393 | 아니오 | hanulim3a.png |
| `Roman` | 로마자 | 아니오 | hanulimlat.png |

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
| `usesShiftSpaceForRomanMode` | Shift+Space로 하늘입력기 내장 로마자 모드 전환 |
| `switchesToRomanOnEsc` | ESC 키 입력 시 로마자 모드로 자동 전환 |

### `usesShiftSpaceForRomanMode` — Shift+Space 로마자 모드 전환

이 옵션을 활성화하면 Shift+Space가 하늘입력기 내장 로마자 모드(`org.cocomelo.inputmethod.Hanulim.Roman`)와 한글 모드 사이를 토글합니다. 비활성화(기본값)하면 Shift+Space를 하늘입력기가 가로채지 않으므로, 시스템 단축키(시스템 설정 → 키보드 → 단축키 → 입력 소스)에 Shift+Space를 할당하여 ABC 등 다른 입력기와 전환하는 데 사용할 수 있습니다.

> macOS의 기본 입력기 전환 단축키는 수식키(Ctrl, Cmd 등) 조합만 지원하므로, Shift+Space를 시스템 단축키로 쓰려면 이 옵션을 꺼야 합니다.

**활성화 방법:**

```bash
defaults write org.cocomelo.inputmethod.Hanulim usesShiftSpaceForRomanMode -bool true
killall Hanulim
```

**비활성화 방법 (기본값):**

```bash
defaults write org.cocomelo.inputmethod.Hanulim usesShiftSpaceForRomanMode -bool false
killall Hanulim
```

---

### `switchesToRomanOnEsc` — vi/vim 사용자를 위한 ESC 자동 전환

이 옵션을 활성화하면 하늘입력기 한글 모드(두벌식, 세벌식 등)에서 ESC 키를 누를 때 자동으로 로마자 모드로 전환됩니다. vi/vim에서 입력 모드를 빠져나올 때 동시에 입력기도 로마자로 전환되므로, 명령 모드에서 한글이 입력되는 불편함을 없애줍니다.

**동작 조건:**
- 현재 입력 소스가 하늘입력기 한글 모드(로마자 모드 제외)일 것
- ESC 단독 입력일 것 (다른 수식키 조합 제외)
- 로마자 모드에서 ESC를 누를 경우: 모드 전환 없이 ESC만 전달됨
- 다른 입력기(ABC 등)가 활성화된 상태에서는 동작하지 않음

**처리 방식:**

한글 조합 중 여부에 따라 두 가지 경로로 처리됩니다.

| 상태 | ESC 처리 |
|------|---------|
| 조합 없음 | 원본 ESC 통과, 모드 전환은 비동기 부수 효과 |
| 조합 중 (preedit 있음) | 원본 ESC 소비 후 조합 커밋·모드 전환·합성 ESC 전송 |

**조합 없음**: ESC 이벤트는 소비하지 않고 앱에 그대로 전달됩니다. 모드 전환은 비동기로 수행되므로 vi/vim은 ESC를 정상 수신하여 명령 모드로 전환됩니다.

**조합 중**: Ghostty, Terminal.app 등 터미널 에뮬레이터는 preedit(조합 중인 음절)이 표시된 상태에서 ESC가 입력되면, 이를 "preedit 해제" 이벤트로 분류하고 PTY(neovim 등)로 전달하지 않습니다. 이를 해결하기 위해 CGEventTap이 원본 ESC를 **소비**하고 메인 스레드에서 다음 순서로 처리합니다.

1. `HNInputController.commitForEsc()`: 조합 중인 음절을 클라이언트에 삽입
2. `selectInputSource(romanModeID)`: 로마자 모드로 전환
3. 합성 ESC 이벤트 전송 (`.cgAnnotatedSessionEventTap`): preedit가 없는 상태에서 도착하므로 터미널이 PTY로 정상 전달 → neovim/vim이 명령 모드로 전환

이 기능은 2계층으로 구현됩니다.

- **접근성 권한 있음**: `HNEventTap` CGEventTap 콜백에서 처리 → 터미널 에뮬레이터(Ghostty, Terminal.app), GUI 앱(VimR) 모두 단일 ESC로 정상 동작
- **접근성 권한 없음**: `HNInputController.handle()` 폴백에서 처리 → VimR 등 네이티브 GUI 앱은 정상 동작하지만, 터미널 에뮬레이터에서 조합 중일 때는 ESC를 두 번 입력해야 할 수 있음

**활성화 방법:**

```bash
defaults write org.cocomelo.inputmethod.Hanulim switchesToRomanOnEsc -bool true
killall Hanulim
```

**비활성화 방법:**

```bash
defaults write org.cocomelo.inputmethod.Hanulim switchesToRomanOnEsc -bool false
killall Hanulim
```

---

## 9. 디버그 로깅

`HNDebug.swift`는 `/tmp/hanulim.log` 파일에 비동기로 로그를 기록합니다. `#if DEBUG` 조건부 컴파일로 릴리스 빌드에서는 완전히 비활성화됩니다.

디버그 빌드에서 로그를 확인하려면:

```bash
touch /tmp/hanulim.log
killall Hanulim          # IME 프로세스 재시작
tail -f /tmp/hanulim.log
```

---

## 10. 권한 설정

CGEventTap 소비 모드(이벤트를 앱보다 먼저 차단하는 방식)는 macOS의 접근성 권한이 필요합니다.

**설정 경로**: 시스템 설정 → 개인정보 보호 및 보안 → 접근성 → Hanulim 추가

권한이 없는 경우 입력 모드 전환 자체는 정상 동작하지만, Ghostty 등 IME 호출 전에 키 이벤트를 직접 처리하는 앱에서 Shift+Space 입력 시 공백 문자가 추가로 삽입될 수 있습니다.

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
