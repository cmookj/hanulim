# 하늘입력기 (Hanulim) 한국어 입력기

macOS용 한국어 입력기입니다. InputMethodKit(IMK) 프레임워크를 기반으로 하며, 현대 및 옛한글 자판 배열을 지원합니다.

## 저작권 및 라이선스

이 소프트웨어는 [GNU General Public License v2](COPYING)에 따라 배포됩니다.

- 원작자: Copyright (C) 2007-2017 Sanghyuk Suh \<han9kin@gmail.com\>
- Swift 포팅 및 추가 개발: Copyright (C) 2026 Changmook Chun \<cmookj@duck.com\>

원본 Objective-C 소스는 Sanghyuk Suh가 작성하였으며, GitHub(`github.com/han9kin/hanulim`)에 GPL v2로 공개되어 있었습니다.
이 저장소는 해당 소스를 Swift로 번역하고 현대 macOS(Sequoia)에 맞게 수정한 파생 저작물입니다.
GPL v2의 조건에 따라 이 파생 저작물도 동일한 GPL v2 라이선스로 배포합니다.

---

## 목차

1. [프로젝트 구조](#1-프로젝트-구조)
2. [부트스트랩 순서](#2-부트스트랩-순서)
3. [InputMethodKit 아키텍처](#3-inputmethodkit-아키텍처)
4. [한글 오토마타](#4-한글-오토마타)
5. [약어 확장 시스템](#5-약어-확장-시스템)
6. [입력 소스 등록](#6-입력-소스-등록)
7. [사용자 환경설정](#7-사용자-환경설정)
8. [디버그 로깅](#8-디버그-로깅)

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
│   ├── HNCandidates.swift           약어 데이터 모델
│   ├── HNCandidatesController.swift 약어 패널 컨트롤러
│   ├── HNAppController.swift        App 컨트롤러
│   ├── HNUserDefaults.swift         사용자 환경설정
│   └── Info.plist                   입력 소스, 자판 등록
├── HNDataController.swift           CoreData 스택 (약어 DB)
├── HNDebug.swift                    디버그 로깅 유틸리티
└── *.png                            메뉴 막대 아이콘 리소스
```

---

## 2. 부트스트랩 순서

`main.swift`는 `NSApplicationMain` 없이 수동으로 실행 흐름을 제어합니다.

```
main.swift (autoreleasepool)
 │
 ├─ 1. IMKServer(name:bundleIdentifier:)
 │      IMK 서버를 생성합니다. 앱들이 이 서버를 통해 입력기에 연결됩니다.
 │
 ├─ 2. HNCandidatesController(server:)
 │      CoreData 스택을 초기화하고 약어 DB 파일을 로드합니다.
 │
 ├─ 3. Bundle.main.loadNibNamed("MainMenu", ...)
 │      MainMenu.nib에서 HNAppController 인스턴스를 생성합니다.
 │
 └─ 4. NSApplication.shared.run()
        이벤트 루프를 시작합니다.
```

---

## 3. InputMethodKit 아키텍처

### 이벤트 흐름

```
macOS 이벤트 큐
 │
 └─ 포커스된 앱 → NSTextInputContext.handleEvent()
                        │
                        └─ HNInputController.inputText(_:key:modifiers:client:)
```

### HNInputController

`IMKInputController`를 상속한 핵심 클래스입니다.
IMK가 각 클라이언트 앱의 포커스 변경마다 인스턴스를 생성합니다.

#### 주요 메서드

**`inputText(_:key:modifiers:client:) → Bool`**

모든 키 입력의 진입점입니다.

분기 로직:

```
keyDown 이벤트 수신
 │
 ├─ Option+Return: 조합 중인 문자열로 약어 후보 검색
 │
 └─ 그 외: HNInputContext.handleKey() 위임
```

**`setValue(_:forTag:client:)`**

시스템이 입력 소스를 전환할 때 호출됩니다. `kTSMDocumentInputModePropertyTag` 태그와 함께 입력 모드 ID(예: `org.cocomelo.inputmethod.Hanulim.3final`)를 받아 `inputContext.setKeyboardLayout(name:)`을 호출해 자판 배열을 전환합니다.

**`recognizedEvents(_:) → Int`**

조합 중에는 마우스 클릭도 수신하여 즉시 커밋 처리를 합니다.

```swift
// 조합 중: 키 입력 + 마우스 클릭 수신
mask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

// 조합 없음: 키 입력만 수신
mask = [.keyDown]
```

---

## 4. 한글 오토마타

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

**자소(Jaso) 방식**: 세벌식처럼 초성·중성·종성 자리를 별도의 키로 입력합니다.

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

각 `value` 항목은 32비트 값으로, 상위 16비트는 Shift 입력 시, 하위 16비트는 일반 입력 시의 코드입니다.
16비트 코드에서 상위 바이트는 키 종류(0=기호, 1=초성, 2=중성, 3=종성, 4=방점), 하위 바이트는 해당 자소의 인덱스입니다.

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
 ├─ Ctrl/Cmd/Option 수식키 조합 (couldHandle = false):
 │    keyConv = 0으로 처리 → 조합 커밋 → false 반환 (앱이 처리)
 │
 ├─ 기호 키 (keyConv != 0, type == symbol):
 │    현재 조합 커밋 → 기호 직접 삽입 → true 반환
 │
 ├─ 한글 자소 (keyConv != 0, type != symbol):
 │    keyBuffer에 추가 → compose() 실행 → 조합 미리보기 갱신 → true 반환
 │
 ├─ 조합 중 특수키 (couldHandle = true, keyBuffer 비어있지 않음):
 │    Delete: 마지막 자소 제거 후 재조합 → true 반환
 │    Tab (Terminal 한정): 조합 커밋 → false 반환
 │    화살표 (Word 한정): 조합 커밋 → true 반환
 │
 └─ 그 외 (Space, Return 등):
      현재 조합 커밋 → false 반환 (앱이 처리)
```

**`compose()` 조합 알고리즘:**

`keyBuffer`에 쌓인 자소 코드를 순회하며 `HNCharacter`를 구성합니다.
두벌식(jamo)과 세벌식(jaso)은 아래와 같이 다르게 처리됩니다.

두벌식(jamo) 전용 처리:

```
새 자소 입력
 │
 ├─ [초성 입력, 이미 중성 이후 상태] 종성 후보로 변환 시도
 │    hnJasoInitialToFinal[] 테이블로 초성→종성 변환
 │    기존 종성과 합성 가능하면 겹받침 구성
 │
 └─ [중성 입력, 이미 종성 있음] 분리 처리
      종성을 떼어 다음 음절의 초성으로 이동
      겹받침이면 마지막 자소만 분리
```

공통 처리 (두벌식·세벌식 공통):

```
새 자소 입력
 │
 ├─ [같은 종류의 자소 연속 입력] 합성 테이블 조회
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

## 5. 약어 확장 시스템

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

**`HNCandidatesController`**: IMKCandidates 패널과 CoreData 검색 요청을 관리하는 싱글턴입니다.
`IMKServer` 초기화 시 생성되며 앱 종료 시까지 유지됩니다.

**`HNDataController`**: CoreData 퍼시스턴트 스토어 코디네이터와 매니지드 오브젝트 컨텍스트를 관리하는 싱글턴입니다.

---

## 6. 입력 소스 등록

`InputMethod/Info.plist`의 `tsInputModeListKey`에서 입력 모드를 등록합니다.

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

## 7. 사용자 환경설정

`HNUserDefaults`는 `UserDefaults.standard`를 감싸고, 변경 알림을 관찰하여 실시간으로 반영합니다.

| 설정 키 | 역할 |
|---------|------|
| `usesSmartQuotationMarks` | 스마트 따옴표 사용 ('' "" ↔ '' "") |
| `inputsBackSlashInsteadOfWon` | 원화 기호(₩) 대신 역슬래시(\\) 입력 |
| `handlesCapsLockAsShift` | CapsLock을 Shift로 처리 |
| `commitsImmediately` | 음절 완성 즉시 삽입 (조합 중 상태 없음) |
| `usesDecomposedUnicode` | NFD 자소 분리 유니코드 사용 |

설정은 터미널에서 `defaults` 명령으로 변경하고 `killall Hanulim`으로 재시작하면 즉시 반영됩니다.

```bash
defaults write org.cocomelo.inputmethod.Hanulim usesSmartQuotationMarks -bool true
killall Hanulim
```

---

## 8. 디버그 로깅

`HNDebug.swift`는 `#if DEBUG` 빌드에서만 활성화됩니다.
`NSLog`를 사용해 시스템 로그에 출력하며, Console.app에서 확인할 수 있습니다.

```swift
func HNLog(_ message: @autoclosure () -> String) {
#if DEBUG
    NSLog("%@", message())
#endif
}
```

릴리스 빌드에서는 `HNLog` 호출이 완전히 제거됩니다.
