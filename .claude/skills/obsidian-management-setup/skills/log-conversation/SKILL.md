---
name: log-conversation
description: Append a concise log of the current Claude conversation to today's daily note `## LOGs` section. Picks the target vault by matching the current working directory against `~/.claude/CLAUDE.md` session-dir mappings. Vault-agnostic — all vault-specific details (daily-note path shape, conventions) come from the target vault's OBSIDIAN.md at runtime. Invoke when the user runs `/log-conversation` or when a hook fires it.
model: haiku
---

# log-conversation

현재 Claude 대화 내용을 한 줄 로그로 요약해 오늘의 일일 노트 `## LOGs` 섹션에 추가한다.

이 스킬은 **vault-agnostic**. 어느 vault 에 어떻게 기록할지는 전부 `~/.claude/CLAUDE.md` 와 해당 vault 의 `OBSIDIAN.md` 에서 읽어온다. 스킬 내부에 vault 경로나 경로 패턴을 하드코딩하지 말 것.

## 동작

### 0. 호출 경로 판별
이 스킬은 두 가지 방식으로 호출된다:
- **직접 호출** (유저가 `/log-conversation` 입력): 현재 Claude 세션의 대화 컨텍스트를 직접 읽는다. cwd 는 `pwd` 로.
- **hook 트리거** (Stop/SessionEnd hook 이 headless claude 를 띄워 실행): 호출 프롬프트에 다음 두 줄이 포함된다.
  ```
  - cwd: <path>
  - transcript file: <path>
  ```
  이 경우:
  - cwd 는 프롬프트의 cwd 값 사용.
  - 대화 내용은 `transcript file` 경로의 JSONL 을 Read 로 읽어 파악. 최근 턴부터 역순으로 훑되, since-marker (step 4) 이후 분만 보면 충분.

### 1. 대상 vault 결정
- `~/.claude/CLAUDE.md` 를 읽고 두 매핑 테이블 파싱:
  - `작업 - vault 매핑`: 작업 → vault directory
  - `작업 - claude session 위치 매핑`: 작업 → claude session directory
- step 0 에서 얻은 cwd 기준으로:
  - **(a) vault-root 매치**: cwd 가 `작업 - vault 매핑` 의 어떤 vault 안에 있으면 (prefix-match) 그 vault 사용.
  - **(b) session-dir 매치**: 아니면 `작업 - claude session 위치 매핑` 에서 가장 길게 prefix-match 되는 엔트리 → 작업 라벨 → vault.
  - 경로 비교는 `~` 를 `$HOME` 으로 expand.
- 매칭 없으면 → 유저에게 어느 vault 에 기록할지 물어본다. 기본값을 임의로 선택하지 말 것. (단, hook 트리거라 interactive 가 불가능하면 → 조용히 skip 하고 종료.)

### 2. 대상 vault 의 `OBSIDIAN.md` 읽기
- vault 디렉토리 루트의 `OBSIDIAN.md` 파일을 읽는다.
- 여기서 얻어야 할 것:
  - 일일 노트 경로 패턴 (예: `업무/📆 Daily Archive/Notes/YYYY-MM/YYYY-MM-DD.md`)
  - 일일 노트 템플릿 (어느 섹션이 `## LOGs` 인지 재확인)
- 경로 패턴이나 템플릿을 스킬 내부에 가정하지 말 것. 반드시 이 문서에서 읽을 것.

### 3. 오늘의 일일 노트 경로 계산
- OBSIDIAN.md 에서 읽은 패턴에 오늘 날짜(`YYYY-MM-DD`, `YYYY-MM`) 를 대입해 절대경로 계산.
- 파일이 존재하지 않으면 → **중단**. 다음 메시지를 유저에게 명확히 출력:
  `오늘 일일 노트 ({path}) 가 아직 없습니다. obsidian-vault-manager 를 먼저 실행해 주세요.`
- 파일을 생성하지 말 것. 일일 노트 생성은 이 스킬의 책임이 아님.

### 4. "지난 로그 이후" 의 대화 식별
- 일일 노트의 `## LOGs` 섹션 내용을 읽는다.
- 가장 마지막 bullet (없다면 가장 마지막 h3 제목) 을 "since-marker" 로 삼는다.
- since-marker 이후에 현재 대화에서 다루어진 내용이 **delta** — 이번에 기록할 대상.
- `## LOGs` 섹션이 비어있으면 현재 대화 전체가 delta.

### 4.5. 메타 작업 필터 (skip 판정)
- delta 가 **일일 노트 자체의 관리/편집** 작업 만으로 구성되면 **로그를 남기지 않고 조용히 종료**. 메타 작업이 `## LOGs` 에 쌓이면 다음 호출의 since-marker 가 메타 항목이 되어 노이즈가 누적됨.
- 메타 작업의 예 (대화의 주된 주제가 다음 중 하나면 skip):
  - daily note 파일 (`📆 Daily Archive/Notes/YYYY-MM/YYYY-MM-DD.md`) 의 직접 편집 — todo 정리, 체크박스 토글, 헤더 정정, 섹션 재배치 등
  - daily note 마이그레이션 (오늘/어제 daily 작업, `obsidian-vault-manager` 호출)
  - daily note 인프라 자체에 대한 변경 — `log-conversation` skill, `obsidian-vault-manager` agent, hook 스크립트, `OBSIDIAN.md`, `~/.claude/CLAUDE.md` 의 vault/세션 매핑, `claude-setup-sync` / `obsidian-management-setup` skill 등
  - `## LOGs` 추출 또는 `## NOTEs` 추출 등 일일 노트 정리 워크플로우
- delta 가 메타 작업 + 실제 작업의 혼합이면, **실제 작업 부분만 로그**. 메타 작업 bullet 은 만들지 않는다.
- 판정이 애매하면 보수적으로: 대화의 50% 이상이 메타이면 전체 skip.

### 5. delta 요약
- delta 를 짧은 bullet 들로 요약. 여러 주제라면 여러 bullet.
- 톤: 간결, 전보체. 마케팅 문구나 추임새 금지.
- 긴 대화여도 bullet 개수는 소수(대개 1~4) 로 억제. 로그이지 transcript 가 아님.
- 한국어 대화라면 한국어로, 영어 대화라면 영어로 작성.

### 6. h3 그룹핑 결정
- 가장 최근 h3 제목과 delta 의 주제가 **명백히 같은 흐름** 이면 해당 h3 하위에 bullet append.
- **명백히 다른 주제** 이면 새 h3 생성 후 하위에 bullet 추가.
- 애매한 경우: 재사용 쪽으로 살짝 기울이되 (실제 겹침이 있을 때만), 확신이 없으면 새 h3 생성.
- 새 h3 제목: delta 의 주제를 넓게 아우르는 한 줄. 이후 대화가 이어지며 포함 범위가 넓어질 수 있음을 감안.

### 7. 파일에 반영
- Edit 으로 일일 노트를 수정. 기존 h3 확장이면 bullet 삽입, 새 h3 면 h3 + bullet 을 `## LOGs` 하위 마지막에 추가.
- `## TODOs`, `## NOTEs` 섹션은 절대 건드리지 말 것.
- 주변 공백/줄바꿈 스타일을 깨지 않을 것.

## 하지 않는 것
- 일일 노트를 **생성하지 않는다** (obsidian-vault-manager 의 책임).
- `## LOGs` 바깥 섹션을 수정하지 않는다.
- 로그를 카테고리 폴더로 추출하지 않는다 (obsidian-vault-manager 의 책임).

## 확장
새 vault 를 추가하려면:
1. `~/.claude/CLAUDE.md` 의 두 매핑 테이블에 엔트리 추가.
2. 해당 vault 루트에 `OBSIDIAN.md` 작성 (경로 패턴 등 포함).
스킬 파일 자체는 수정할 필요 없음.
