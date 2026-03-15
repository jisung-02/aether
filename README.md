# ✨ Aether

[English Documentation 🇺🇸](./README_en.md)

---

## Gleam 기반 서버 프레임워크

**Aether**는 Gleam 프로그래밍 언어로 구축된 종합 서버 프레임워크입니다. 타입 안전하고, 확장 가능하며, 유지보수가 용이한 백엔드 시스템 구축을 목표로 합니다.

저수준 TCP/UDP부터 고수준 HTTP/2까지 완전한 네트워킹 스택을 제공하며, 모든 기능에 Gleam의 강력한 타입 시스템을 적용합니다.

이 프로젝트는 경희대학교 컴퓨터공학과 풀스택 서비스 네트워킹 수업 과제로 제작되었습니다.

---

## 🌟 주요 특징

### 🔒 타입 안전한 기반
- Gleam의 강력한 타입 시스템으로 컴파일 타임에 오류 감지
- `Result` 타입을 이용한 명시적 에러 처리
- 런타임 예외 없음 - 예측 가능한 동작

### 🏗️ 계층화된 아키텍처
- **Network 계층**: TCP/UDP 소켓 연산 및 연결 관리
- **Protocol 계층**: 프로토콜 독립적 추상화 (HTTP/1.x, HTTP/2)
- **Pipeline 계층**: 조합 가능한 요청/응답 처리 스테이지
- **Router 계층**: 패턴 매칭 기반 타입 안전 URL 라우팅

### 🚀 HTTP/2 지원
- 완전한 HTTP/2 바이너리 프레이밍 (RFC 9113)
- HPACK 헤더 압축 (RFC 7541)
- 스트림 다중화
- 흐름 제어
- 연결 프리페이스 처리

### ⚡ BEAM 기반
- Erlang VM의 검증된 동시성 모델 기반
- 슈퍼바이저 트리를 통한 내결함성
- OTP 패턴을 활용한 확장 가능한 연결 처리

---

## 📊 프로젝트 통계

| 항목 | 값 |
|------|-----|
| 소스 파일 | 60개+ |
| 코드 라인 | ~236,000 |
| 테스트 케이스 | 1,300개 |
| 테스트 상태 | 전체 통과 ✅ |

---

## 🏛️ 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────┐
│                      애플리케이션 계층                        │
├─────────────────────────────────────────────────────────────┤
│  Router        │  Middleware     │  Serialization            │
│  - 패턴 매칭   │  - 조합 가능    │  - JSON                   │
│  - 그룹화      │  - 타입 안전    │  - 바이너리               │
│  - 파라미터    │                 │                           │
├─────────────────────────────────────────────────────────────┤
│                      파이프라인 계층                          │
│  - Stage       │  - Executor     │  - Compose                │
│  - Error       │  - Pipeline     │                           │
├─────────────────────────────────────────────────────────────┤
│                      프로토콜 계층                            │
│  ┌─────────────────────┐  ┌─────────────────────┐           │
│  │       HTTP/1.x      │  │       HTTP/2        │           │
│  │  - 요청/응답        │  │  - 프레임 계층      │           │
│  │  - 헤더             │  │  - HPACK            │           │
│  │  - 본문             │  │  - 스트림 관리자    │           │
│  │                     │  │  - 흐름 제어        │           │
│  │                     │  │  - 연결 핸들러      │           │
│  └─────────────────────┘  └─────────────────────┘           │
├─────────────────────────────────────────────────────────────┤
│                      네트워크 계층                            │
│  - TCP          │  - UDP          │  - Socket                │
│  - Connection   │  - Transport    │  - Manager               │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 모듈 구조

### Core (`aether/core`)
- `data.gleam` - 핵심 데이터 타입
- `message.gleam` - 메시지 정의

### Network (`aether/network`)
- `tcp.gleam` - TCP 소켓 연산
- `udp.gleam` - UDP 소켓 연산
- `socket.gleam` - 소켓 추상화
- `transport.gleam` - 전송 계층
- `connection.gleam` - 연결 상태 머신
- `connection_manager.gleam` - 연결 풀 관리
- `connection_supervisor.gleam` - OTP 슈퍼바이저 통합

### Protocol (`aether/protocol`)

#### HTTP (`aether/protocol/http`)
- `request.gleam` - HTTP 요청 처리
- `response.gleam` - HTTP 응답 빌더
- `headers.gleam` - 헤더 조작
- `body.gleam` - 본문 처리
- `unified.gleam` - 프로토콜 독립적 요청/응답

#### HTTP/2 (`aether/protocol/http2`)
- `frame.gleam` - 프레임 타입 정의
- `frame_parser.gleam` - 바이너리 프레임 파싱
- `frame_builder.gleam` - 프레임 직렬화
- `stream.gleam` - 스트림 상태 머신
- `stream_manager.gleam` - 다중 스트림 관리
- `flow_control.gleam` - 윈도우 기반 흐름 제어
- `connection.gleam` - HTTP/2 연결 핸들러
- `preface.gleam` - 연결 프리페이스
- `stage.gleam` - Aether 파이프라인 통합
- `error.gleam` - 에러 타입

#### HPACK (`aether/protocol/http2/hpack`)
- `table.gleam` - 정적/동적 헤더 테이블
- `encoder.gleam` - 헤더 압축
- `decoder.gleam` - 헤더 압축 해제
- `huffman.gleam` - 허프만 코딩
- `integer.gleam` - 가변 길이 정수
- `string.gleam` - 문자열 인코딩

#### TCP 프로토콜 (`aether/protocol/tcp`)
- `connection.gleam` - TCP 연결 처리
- `reliable_delivery.gleam` - 신뢰성 계층
- `segment.gleam` - TCP 세그먼트

### Pipeline (`aether/pipeline`)
- `pipeline.gleam` - 파이프라인 빌더
- `stage.gleam` - 처리 스테이지
- `compose.gleam` - 스테이지 합성
- `executor.gleam` - 파이프라인 실행
- `error.gleam` - 에러 처리

### Router (`aether/router`)
- `router.gleam` - 메인 라우터
- `pattern.gleam` - URL 패턴 매칭
- `group.gleam` - 라우트 그룹화
- `params.gleam` - 파라미터 추출

### Serialization (`aether/serialization`)
- JSON 인코딩/디코딩 지원
- 바이너리 직렬화

### Utilities (`aether/util`)
- `benchmark.gleam` - 성능 유틸리티
- 헬퍼 함수

---

## 🛠️ 기술 스택

| 컴포넌트 | 패키지 | 버전 | 역할 |
|----------|--------|------|------|
| **HTTP 서버** | `mist` | 5.x | HTTP 서버 구현 |
| **HTTP 타입** | `gleam_http` | 4.x | HTTP 타입 정의 |
| **JSON** | `gleam_json` | 2.x | JSON 처리 |
| **OTP** | `gleam_otp` | 1.x | 동시성 패턴 |
| **소켓** | `glisten` | 8.x | 저수준 네트워킹 |
| **표준 라이브러리** | `gleam_stdlib` | 0.44+ | 핵심 유틸리티 |

---

## 🚀 시작하기

### 사전 요구사항
- Gleam >= 1.11.0
- Erlang/OTP >= 26

### 설치

```bash
git clone https://github.com/jisung-02/gleam_aether.git
cd gleam_aether/aether
gleam build
```

### 테스트 실행

```bash
gleam test
```

### 예제: 기본 HTTP 서버

```gleam
import aether/router.{router, get, post}
import aether/protocol/http/response

pub fn main() {
  let app = router()
    |> get("/", fn(_req) { response.ok("안녕하세요, Aether!") })
    |> get("/health", fn(_req) { response.json(#("status", "ok")) })
    |> post("/api/users", create_user)
  
  // Mist로 서버 시작
  start_server(app, port: 8080)
}
```

### 예제: HTTP/2 프레임 처리

```gleam
import aether/protocol/http2/connection
import aether/protocol/http2/frame_builder

pub fn handle_request() {
  let conn = connection.new_server()
  
  // 수신 프레임 처리
  case connection.handle_frame(conn, incoming_frame) {
    connection.RequestComplete(conn, stream_id, headers, body) -> {
      // 응답 빌드
      let #(conn, response_frames) = connection.build_response(
        conn, stream_id, 200,
        [#("content-type", "application/json")],
        body
      )
      // response_frames 전송
    }
    connection.SendFrames(conn, frames) -> {
      // 제어 프레임 전송 (SETTINGS ACK 등)
    }
    _ -> // 기타 케이스 처리
  }
}
```

---

## 📋 구현 상태

| 기능 | 상태 |
|------|------|
| TCP/UDP 네트워킹 | ✅ 완료 |
| 연결 관리 | ✅ 완료 |
| HTTP/1.x 지원 | ✅ 완료 |
| HTTP/2 프레이밍 | ✅ 완료 |
| HPACK 압축 | ✅ 완료 |
| 스트림 다중화 | ✅ 완료 |
| 흐름 제어 | ✅ 완료 |
| 파이프라인 아키텍처 | ✅ 완료 |
| 라우터 | ✅ 완료 |
| 서버 푸시 | ⏳ 계획됨 |
| TLS/ALPN | ⏳ 계획됨 |
| WebSocket | ⏳ 계획됨 |

---

## 📄 라이선스

MIT License

---

## 🤝 기여하기

기여를 환영합니다! Pull Request를 자유롭게 제출해주세요.

---

*Gleam으로 ❤️를 담아 제작*
