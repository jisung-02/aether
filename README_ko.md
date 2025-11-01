### 2. `README_ko.md` (한국어 버전)

```markdown
# ✨ Aether

[Go to English document 🇺🇸](./README.md)

---

### 글림(Gleam) 기반 서버 프레임워크

**Aether**는 Gleam 언어를 기반으로 개발된 서버 프레임워크입니다.

이 프레임워크는 **명시성(Explicitness)**과 **레이어 간 독립성(Layer Independence/Decoupling)**을 핵심 가치로 삼아, 타입 안전하고 유지보수가 쉬운 백엔드 시스템 구축을 목표로 합니다.

#### 🌟 특징

* **타입 안전 기반:** Gleam의 강력한 타입 시스템을 활용하여 컴파일 시점에 오류를 포착합니다.
* **분리된 아키텍처:** 요청 처리, 라우팅, 비즈니스 로직 등의 레이어를 명확하게 분리하여 코드의 독립성과 테스트 용이성을 극대화합니다.
* **BEAM 기반 구동:** Erlang VM(`Mist` 사용)의 동시성(Concurrency) 및 내결함성(Fault Tolerance)을 기반으로 하여 확장 가능하고 안정적인 서버를 제공합니다.

#### 🛠️ 주요 기술 스택

| 컴포넌트 | 패키지 | 역할 |
| :--- | :--- | :--- |
| **HTTP 서버** | `mist` | 견고하고 빠른 HTTP 서버 구현체 |
| **HTTP 타입** | `gleam_http` | 요청 및 응답의 핵심 HTTP 타입 정의 |
| **JSON 처리** | `gleam_json` | 타입 안전한 JSON 인코딩/디코딩 지원 |

#### 🚀 시작하기

프로젝트를 클론하고 의존성을 설치합니다.

```bash
gleam build
gleam run