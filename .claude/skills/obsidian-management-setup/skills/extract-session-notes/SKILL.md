---
name: extract-session-notes
description: Extract durable insights from the current Claude session and append them as a `### {emoji} TITLE` h3 with descriptive bullets under today's daily note `## NOTEs` section. Picks the target vault by matching the current working directory against `~/.claude/CLAUDE.md` mappings; reads emoji-category mapping and daily-note path pattern from the vault's `OBSIDIAN.md`. Vault-agnostic. Invoke when the user runs `/extract-session-notes [optional scope]`.
model: sonnet
---

# extract-session-notes

현재 Claude 세션(또는 인자로 지정한 부분 집합) 에서 의미 있는 인사이트를 뽑아 오늘의 일일 노트 `## NOTEs` 섹션에 `### {이모지} TITLE` h3 한 블록 + 서술형 bullet 들로 기록한다.

`log-conversation` 이 활동 흐름을 `## LOGs` 에 짧게 남기는 반면, 이 skill 은 **나중에 다시 봤을 때 그때의 결정과 맥락을 떠올릴 수 있는 노트** 를 만드는 데 목적이 있다.

이 스킬은 **vault-agnostic**. 어느 vault 에 어떻게 기록할지는 전부 `~/.claude/CLAUDE.md` 와 해당 vault 의 `OBSIDIAN.md` 에서 읽어온다. 스킬 내부에 vault 경로·이모지·카테고리를 하드코딩하지 말 것.

## 동작

### 0. 호출 방식
- 직접 호출만 지원. hook 트리거 없음.
- 인자 없음 → 현재 세션 전체가 대상
- 인자 있음 (예: `/extract-session-notes redream 데이터 모델 부분`) → 그 주제에 해당하는 부분만 대상
- cwd 는 `pwd` 로 결정. 세션 컨텍스트는 자체 컨텍스트에서 직접 사용 (transcript 파일 읽기 불필요).

### 1. 대상 vault 결정
`log-conversation` §1 과 동일:
- `~/.claude/CLAUDE.md` 의 두 매핑 테이블 파싱:
  - `작업 - vault 매핑`: 작업 → vault directory
  - `작업 - claude session 위치 매핑`: 작업 → claude session directory
- cwd 기준:
  - **(a) vault-root 매치**: cwd 가 `작업 - vault 매핑` 의 어떤 vault 안이면 (prefix-match) 그 vault.
  - **(b) session-dir 매치**: 아니면 `작업 - claude session 위치 매핑` 에서 가장 길게 prefix-match 되는 엔트리 → 작업 → vault.
  - 경로 비교는 `~` 를 `$HOME` 으로 expand.
- 매칭 없으면 → 유저에게 `AskUserQuestion` 으로 vault 선택. 임의 기본값 금지.

### 2. 대상 vault 의 `OBSIDIAN.md` 읽기
vault 루트의 `OBSIDIAN.md` 에서 다음을 얻는다:
- 일일 노트 경로 패턴 (예: `📆 Daily Archive/Notes/YYYY-MM/YYYY-MM-DD.md`)
- 일일 노트 템플릿 (`## NOTEs` 섹션 형식 재확인 — `### {category emoji} TITLE`)
- **이모지-카테고리 매핑 표** (이 스킬의 핵심 입력)

이 정보는 절대 스킬에 가정하지 말고 매번 OBSIDIAN.md 에서 읽을 것.

### 3. 오늘의 일일 노트 경로 계산
- 위 패턴에 오늘 날짜(`YYYY-MM-DD`, `YYYY-MM`) 대입해 절대경로 산출.
- 파일이 존재하지 않으면 → **중단**. 다음 메시지를 명확히 출력:
  `오늘 일일 노트 ({path}) 가 아직 없습니다. obsidian-vault-manager 를 먼저 실행해 주세요.`
- 파일을 생성하지 말 것.

### 4. 추출 대상 컨텐츠 식별
- 인자 없음: 세션 전체.
- 인자 있음: 인자를 필터로 사용해 해당 주제와 관련된 대화 부분만 대상화.
- 단순 활동(파일 편집, 명령 실행 등) 은 후보가 아님. **결정·인사이트·아이디어·논거·회고** 같은 "지속 가치 있는 내용" 만 후보.

### 4.5. 메타 작업 필터 (skip 판정)
대상이 **일일 노트/skill 인프라 자체의 관리 작업** 만으로 구성되면 노트를 만들지 않고 조용히 종료. 메타 작업 예시:
- daily note 파일의 직접 편집 (todo 정리, 체크박스 토글 등)
- daily note 마이그레이션 (`obsidian-vault-manager` 호출)
- daily note 인프라 변경 — `log-conversation` / `extract-session-notes` 자체 편집, hook 스크립트, `OBSIDIAN.md`, `~/.claude/CLAUDE.md` 매핑 등
- `## LOGs` / `## NOTEs` 추출 워크플로우

메타 + 실작업 혼합이면 실작업 부분만 노트화. 50% 이상 메타이면 전체 skip.

### 5. 카테고리(이모지) 결정
1. 추출 대상 컨텐츠를 한 줄로 압축한 주제(TITLE 후보) 와 핵심 키워드 도출.
2. `OBSIDIAN.md` 이모지-카테고리 표를 훑어 의미적으로 가장 가까운 후보 선정.
3. 신뢰도 판정:
   - **명백히 매칭** → 그 이모지 사용.
   - **애매하거나 매칭 없음** → `AskUserQuestion` 으로 유저에게 선택지 제시:
     - 매핑 표의 각 이모지+카테고리 라벨
     - "새 카테고리 만들기" 옵션
   - "새 카테고리" 선택 시 → 후속 질문(`AskUserQuestion`) 으로 새 이모지 + 카테고리 폴더명 입력 받기 → `OBSIDIAN.md` 매핑 표에 행 추가 (Edit). 카테고리 폴더는 자동 생성하지 않고, 유저에게 안내만.

### 6. 본문 작성
- bullet 개수: 약 3~4 개 기준. 상한 없음 — 필요하면 5+ 도 OK.
- 톤: **descriptive**. 나중에 유저가 다시 봤을 때 그때의 결정/맥락/논거를 되살릴 수 있어야 함.
  - "X 를 논의함" 같은 활동 요약 금지.
  - "왜 그 결정을 했는지", "어떤 옵션을 버렸고 왜인지", "핵심 인사이트가 무엇인지" 를 한 bullet 한 호흡으로 풀어 쓴다.
  - `log-conversation` 의 전보체와는 다른 결. 그렇다고 transcript 옮겨적기도 아님 — 결정·근거 중심으로 정리.
- 한국어 대화면 한국어, 영어 대화면 영어.
- TITLE: 추출 주제를 한 줄로 압축 (h3 제목, 이모지 뒤).

### 7. 일일 노트에 반영
- `## NOTEs` 섹션 끝에 새 h3 블록 append. 형식:
  ```
  ### {이모지} TITLE
  - bullet 1
  - bullet 2
  - bullet 3
  ```
- 한 번 호출당 단일 h3. 같은 주제로 다시 호출되어도 기존 h3 에 합치지 말고 항상 새 h3 추가 (반복 호출은 자연스럽게 별도 블록으로 누적되도록).
- `## TODOs`, `## LOGs` 섹션은 절대 건드리지 말 것.
- 주변 공백/줄바꿈 스타일을 깨지 않을 것.
- §5 에서 매핑 추가가 일어났다면 vault 의 `OBSIDIAN.md` 도 같은 호출에서 Edit 으로 갱신.

## 하지 않는 것
- 일일 노트를 **생성하지 않는다** (obsidian-vault-manager 책임).
- `## NOTEs` 외 섹션을 수정하지 않는다.
- 노트를 카테고리 폴더로 추출하지 않는다 (obsidian-vault-manager 책임).
- hook 트리거를 지원하지 않는다.
- 카테고리 폴더 자동 생성하지 않는다 — 매핑만 갱신하고 유저에게 안내.

## 확장
새 vault 를 추가하려면:
1. `~/.claude/CLAUDE.md` 의 두 매핑 테이블에 엔트리 추가.
2. 해당 vault 루트에 `OBSIDIAN.md` 작성 (이모지-카테고리 표 포함).
스킬 파일 자체는 수정할 필요 없음.
