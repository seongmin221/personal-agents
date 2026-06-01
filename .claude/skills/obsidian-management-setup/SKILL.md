---
name: obsidian-management-setup
description: Install or update the Claude-Obsidian work-organizer infrastructure. Analyzes each target vault's actual structure and daily-note format, then drafts a fitting OBSIDIAN.md and lets the user choose to migrate to the canonical daily template or keep their existing format (with optional `## LOGs` + logging). Handles fresh install, adding a new vault, and refreshing global artifacts. Invoke with "set up obsidian management", "add vault X", or "sync obsidian management".
model: sonnet
---

# obsidian-management-setup

Claude-Obsidian 작업 조직 인프라를 이 머신에 설치하거나 업데이트하는 skill.

## Canonical artifacts (source of truth)

이 skill 디렉토리 내부의 파일들이 source-of-truth 다. 설치/갱신 시 `~/.claude/` 와 각 vault 로 복사된다.

- `CLAUDE.md.sample` — 글로벌 `~/.claude/CLAUDE.md` 템플릿
- `OBSIDIAN.md.sample` — per-vault `OBSIDIAN.md` 템플릿 (vault 분석 결과로 customize)
- `settings.snippet.json` — `~/.claude/settings.json` 의 `hooks` 에 유저가 paste 할 JSON 블록
- `hook-spawn-settings.json` — hook 이 띄우는 headless claude 가 사용할 scoped 권한 설정
- `agents/obsidian-vault-manager.md` — 글로벌 agent
- `scripts/today-cal-events.js` — 글로벌 스크립트 (obsidian-vault-manager 의 EventKit 캘린더 조회용; 반복 일정을 정확히 전개)
- `skills/log-conversation/SKILL.md` — 글로벌 skill
- `skills/extract-session-notes/SKILL.md` — 글로벌 skill (`## NOTEs` 추출용)
- `hooks/log-conversation-stop.sh`, `hooks/log-conversation-session-end.sh` — hook 스크립트

이 artifact 들을 업데이트하려면: skill 디렉토리 내의 파일을 직접 편집한 뒤 skill 을 "refresh" 모드로 재실행하여 `~/.claude/*` 에 반영.

## 모드 자동 감지 + 확인

다음 중 하나로 판단:
- **Install** — `~/.claude/CLAUDE.md` 가 없거나 글로벌 agent/skill/hook 중 하나 이상이 누락.
- **Add-vault** — 글로벌 완비. 유저가 "add a vault" 등을 요청하거나 새 vault 경로를 제시.
- **Refresh** — 글로벌 완비. 유저가 "sync" / "update" / "refresh" 등을 요청.

감지한 모드를 유저에게 밝히고, 확인받은 뒤에만 진행.

## Install / Add-vault 모드 — 각 vault 처리 플로우

### 1. Vault 분석 (read-only)

유저가 지정한 각 vault 에 대해:

- 최상위 폴더 트리 (1~2 depth) 를 `ls` / `Glob` 으로 확인.
- 이모지 prefix 가 붙은 폴더 (예: `🧑‍💻 work notes`, `📝 meetings`) → 이모지-카테고리 매핑 후보 행 도출.
- 일일 노트 위치 탐색: `daily notes/`, `Daily Notes/`, 또는 `YYYY-MM-DD.md` 파일이 존재하는 폴더.
- 최근 daily 파일을 Read 로 열어 포맷 파악:
  - 섹션 헤더들 (예: `## Today's Todos`, `## Notes`, `## 겪은 불편함`).
  - 월별 서브폴더 (`YYYY-MM/`) 존재 여부.
- 기타 signal: `Archive Notes/` 같은 수동 관리 폴더, `📝 meetings` 류의 월별 서브폴더 컨벤션 등.

분석 결과를 간단히 보고:
- 폴더 트리
- 추정된 이모지-카테고리 매핑 (행 단위)
- 일일 노트 위치 + 현재 헤더 + 서브폴더 여부

유저가 보정할 수 있게 기다림.

### 2. OBSIDIAN.md 초안 작성

`OBSIDIAN.md.sample` 을 기반으로 vault 별 초안 생성. 변환 원칙은 "canonical 형태를 강요하지 말 것" — 실제 vault 그대로 반영.

채워 넣어야 할 부분:
- **폴더 트리**: vault 의 실제 모습.
- **이모지-카테고리 매핑**: 분석 결과의 행을 채운 뒤 각 행을 유저에게 확인.
- **카테고리별 분류 전략**: 가능한 부분은 자동 추론 (예: `📝 meetings` 의 월별 서브폴더 컨벤션). 불확실하면 질문.
- **일일 노트 경로 패턴**: 분석 결과대로.
- **일일 노트 템플릿**: **step 3 의 결정에 따라 채움** (이 시점엔 placeholder 유지).
- **캘린더 통합**: 이 vault 에 macOS Calendar 의 업무 일정을 daily 로 가져올지 유저에게 질문. yes 면 어떤 캘린더 이름 / 계정을 "업무" 로 볼지 받아 `포함 캘린더` / `포함 계정` 리스트를 채움. no 또는 응답 없음 → 섹션을 비워두거나 생략 (`obsidian-vault-manager` 가 자동으로 skip).

완성 초안을 유저에게 보여주고, 편집/승인 받은 뒤 vault 루트의 `OBSIDIAN.md` 에 쓰기.

해당 vault 에 이미 `OBSIDIAN.md` 가 있으면 → 초안 작성 건너뛰고 refresh 여부 질문 (기본: skip).

### 3. 일일 노트 포맷 결정 (유저 선택)

두 옵션을 유저에게 제시:

#### (a) canonical 템플릿으로 마이그레이션
- `## <legacy>` 헤더를 `## TODOs` / `## NOTEs` / `## LOGs` 로 rename.
- 필요시 특정 섹션 drop (예: `## 겪은 불편함`).
- `## LOGs` 가 없으면 섹션 append.
- 일일 노트 폴더 이름을 canonical 로 정규화 (예: `daily notes` → `📆 Daily Archive/Notes`). 유저 확인 필수.
- 월별 서브폴더가 없으면 추가 (`YYYY-MM/` 로 기존 파일 이동). 유저 확인 필수.
- 파괴적 작업 전 반드시 재확인.
- 이 경로를 택하면 agent + skill + hook 전체 인프라가 이 vault 에서 작동.

#### (b) 기존 포맷 유지
- daily 헤더, 파일 위치, 폴더 이름 모두 건드리지 않음.
- 후속 질문: **`## LOGs` + 로깅 기능을 추가할까요? (yes/no)**
  - **yes** → OBSIDIAN.md 의 daily 템플릿에 `## LOGs` 섹션 추가. 유저 확인을 받아 최근 N 개의 기존 daily 에도 `## LOGs` append (N 은 유저가 지정).
  - **no** → OBSIDIAN.md 상단에 `logging: disabled` 표기 추가. `log-conversation` 은 이 vault 에 대해 no-op 하게 됨. agent 도 로그 extraction 을 skip.

### 4. OBSIDIAN.md 쓰기 + 선택된 migration 실행

- 완성된 OBSIDIAN.md 를 `<vault>/OBSIDIAN.md` 로 쓰기.
- **migrate** 를 택했으면: 폴더 rename + 헤더 rewrite + 월별 서브폴더 이동 + `## LOGs` append (Step 1 에서 hand-run 했던 동일한 로직).
- **keep + LOGs** 를 택했으면: 유저가 동의한 경우, 최근 N 개 daily 에 `## LOGs` 섹션 append.

## Install 모드 — Global step (모든 vault 처리 후 1회)

- 모인 `(label, vault path)` 와 `(label, session dir)` 로 `~/.claude/CLAUDE.md` 를 `CLAUDE.md.sample` 기반으로 렌더링.
- Canonical global artifact 를 `~/.claude/` 로 복사:
  - `agents/obsidian-vault-manager.md` → `~/.claude/agents/obsidian-vault-manager.md`
  - `scripts/today-cal-events.js` → `~/.claude/scripts/today-cal-events.js`
  - `skills/log-conversation/SKILL.md` → `~/.claude/skills/log-conversation/SKILL.md`
  - `skills/extract-session-notes/SKILL.md` → `~/.claude/skills/extract-session-notes/SKILL.md`
  - `hooks/log-conversation-stop.sh` → `~/.claude/hooks/log-conversation-stop.sh` (+ chmod +x)
  - `hooks/log-conversation-session-end.sh` → `~/.claude/hooks/log-conversation-session-end.sh` (+ chmod +x)
  - `hook-spawn-settings.json` → `~/.claude/hook-spawn-settings.json`
- `settings.snippet.json` 내용을 출력하면서 유저에게 안내:
  > 아래 JSON 블록을 `~/.claude/settings.json` 의 `hooks` 객체에 병합하세요. 기존 `hooks` 엔트리(예: `SubagentStop`) 는 유지한 채 `Stop` 과 `SessionEnd` 키만 추가하면 됩니다. (Claude Code 정책 상 이 skill 은 `settings.json` 을 직접 편집할 수 없습니다.)

## Add-vault 모드

위의 per-vault 플로우 (1~4) 를 실행 + 기존 `~/.claude/CLAUDE.md` 의 두 매핑 테이블에 새 행 추가. Globals 는 건드리지 않음. 변경 사항 요약 보고.

## Refresh 모드

- Skill dir 의 canonical artifact 각각을 `~/.claude/*` 의 현재 파일과 비교 (Read + diff).
- 차이 나는 파일들을 유저에게 간략히 표시.
- 유저 확인 후 canonical → global 로 복사. **`~/.claude/CLAUDE.md` 와 per-vault `OBSIDIAN.md` 는 refresh 대상이 아니다.** (유저 커스터마이징 보존)
- `settings.snippet.json` 이 이전 버전과 다르면 유저에게 `~/.claude/settings.json` 재-paste 를 상기시킴.

## 절대 하지 않는 것
- `~/.claude/settings.json` 을 자동 편집하지 않는다. 정책 상 block 되며, harness 설정은 유저의 주권 영역.
- 과거 daily 노트를 migrate 모드 외에는 수정하지 않는다.
- Vault 에 이미 있는 `OBSIDIAN.md` 를 명시적 opt-in 없이 덮어쓰지 않는다.
- Vault 의 기존 폴더/파일을 "keep existing format" 모드에서는 건드리지 않는다.

## 제약 및 tradeoff (유저에게 명시)

- **agent (`obsidian-vault-manager`) 는 canonical `## TODOs / ## NOTEs` 를 전제**. "기존 포맷 유지" 를 택한 vault 에서는 agent 의 todo/note migration 이 작동하지 않음. 로그 관련 기능만 작동.
- **`log-conversation` skill 은 `## LOGs` 를 전제**. `logging: disabled` 로 표시된 vault 에서는 skill 이 no-op.
- **`extract-session-notes` skill 은 canonical `## NOTEs` + OBSIDIAN.md 의 이모지-카테고리 매핑을 전제**. "기존 포맷 유지" 를 택해 `## NOTEs` 가 없는 vault 에서는 skill 이 작동하지 않음.

이 제약은 "keep existing format" 단계에서 유저에게 명시적으로 알릴 것.

## 확장 / 갱신 시나리오

- **새 vault 추가**: skill 을 재실행하고 "add vault" 요청. CLAUDE.md 에 행 추가 + 새 vault 에 OBSIDIAN.md 드롭.
- **canonical artifact 갱신**: skill dir 내 artifact 를 직접 편집 → skill 을 "refresh" 로 재실행 → `~/.claude/*` 반영.
- **settings.json 변경 필요**: `settings.snippet.json` 을 업데이트한 뒤 유저에게 재-paste 안내.
