# ✨ Aether

[English Documentation 🇺🇸](./README_en.md)

---

## Gleam 기반 서버 프레임워크

**Aether**는 Gleam으로 작성된 서버 프레임워크이자 학습용 네트워킹 스택입니다. 저수준 TCP/UDP 소켓 래퍼부터 HTTP/1.x 파서/빌더, HTTP/2 프레이밍과 HPACK, 파이프라인 조합, 라우터, JSON 직렬화와 content negotiation까지 한 저장소 안에서 다룹니다.

현재 코드베이스는 다음 두 축으로 구성됩니다.

- 프레임워크 모듈: `src/aether/**`
- 실행 예제와 통합 진입점: `src/aether/examples/**`, `src/aether.gleam`

이 프로젝트는 경희대학교 컴퓨터공학과 풀스택 서비스 네트워킹 수업 과제로 제작되었습니다.

---

## 🌟 핵심 기능

- 타입 안전한 요청/응답 처리와 `Result` 기반 오류 모델
- TCP/UDP 소켓 추상화, 옵션 구성, 에러 매핑, 연결 관리
- HTTP/1.x 요청 파싱, 응답 생성, URL 인코딩/디코딩, 파이프라인 스테이지
- HTTP/2 프레임 파싱/생성, HPACK, 스트림 관리, 흐름 제어
- 프로토콜 레지스트리, 검증기, 파이프라인 빌더
- 패턴 매칭 라우터, 라우트 그룹, path/query 파라미터 처리
- JSON 직렬화와 `Accept` 헤더 기반 content negotiation
- 하나의 포트에서 `HTTP/1.1 + h2c` 또는 `TLS + ALPN(h2, http/1.1)` 예제 서버

---

## 📊 현재 코드베이스 스냅샷

| 항목 | 값 |
|------|-----|
| `src/aether` Gleam 모듈 | 70개 |
| `src` 전체 파일 | 74개 |
| `test` 파일 | 53개 |
| `src` 코드 라인 | 29,555 |
| `test` 코드 라인 | 18,813 |
| 로컬 검증 결과 | `gleam test` 1308 passing |

위 수치는 현재 저장소 트리를 기준으로 계산했습니다.

---

## 🏛️ 아키텍처 개요

### Network
- `tcp`, `udp`, `socket`, `transport`
- `connection`, `connection_manager`, `connection_supervisor`
- `connection_config`, `socket_options`, `socket_error`

### Protocol
- HTTP/1.x: request/response model, parser, builder, stage, URL utilities
- HTTP/2: frame layer, connection state, stream management, flow control
- HPACK: encoder, decoder, table, huffman, integer, string
- TCP 학습용 프로토콜 계층: header, parser, builder, checksum, state, stage, mode
- 프로토콜 조합: `protocol`, `registry`, `validator`, `pipeline_builder`

### Application
- `pipeline/*`로 조합 가능한 처리 단계 구성
- `router/*`로 path pattern, route group, params 기반 라우팅
- `serialization/json`, `serialization/negotiation`으로 응답 직렬화와 협상 처리

### Examples
- `src/aether.gleam`: HTTP/1.x / HTTP/2 데모 실행
- `src/aether/examples/server_main.gleam`: 멀티프로토콜 CRUD 서버
- `src/aether/examples/http1/*`: HTTP/1.x CRUD 라우터와 핸들러
- `src/aether/examples/http2/*`: HTTP/2 프레임 레벨 CRUD 예제
- `src/aether/examples/multiprotocol/*`: h2c / TLS ALPN 런타임 구성과 서버 바인딩

---

## 📦 모듈 구조

### Entry Points
- `src/aether.gleam`
- `src/aether/examples/server_main.gleam`

### Core
- `src/aether/core/data.gleam`
- `src/aether/core/message.gleam`

### Examples
- `src/aether/examples/common/store.gleam`
- `src/aether/examples/common/user.gleam`
- `src/aether/examples/http1/handlers.gleam`
- `src/aether/examples/http1/http2_handlers.gleam`
- `src/aether/examples/http1/server.gleam`
- `src/aether/examples/http2/handlers.gleam`
- `src/aether/examples/http2/server.gleam`
- `src/aether/examples/multiprotocol/runtime.gleam`
- `src/aether/examples/multiprotocol/server.gleam`

### Network
- `src/aether/network/connection.gleam`
- `src/aether/network/connection_config.gleam`
- `src/aether/network/connection_manager.gleam`
- `src/aether/network/connection_supervisor.gleam`
- `src/aether/network/socket.gleam`
- `src/aether/network/socket_error.gleam`
- `src/aether/network/socket_options.gleam`
- `src/aether/network/tcp.gleam`
- `src/aether/network/transport.gleam`
- `src/aether/network/udp.gleam`

### Pipeline
- `src/aether/pipeline/compose.gleam`
- `src/aether/pipeline/error.gleam`
- `src/aether/pipeline/executor.gleam`
- `src/aether/pipeline/pipeline.gleam`
- `src/aether/pipeline/stage.gleam`

### Protocol Common
- `src/aether/protocol/pipeline_builder.gleam`
- `src/aether/protocol/protocol.gleam`
- `src/aether/protocol/registry.gleam`
- `src/aether/protocol/validator.gleam`

### Protocol HTTP
- `src/aether/protocol/http/builder.gleam`
- `src/aether/protocol/http/parser.gleam`
- `src/aether/protocol/http/request.gleam`
- `src/aether/protocol/http/response.gleam`
- `src/aether/protocol/http/stage.gleam`
- `src/aether/protocol/http/unified.gleam`
- `src/aether/protocol/http/url.gleam`

### Protocol HTTP/2
- `src/aether/protocol/http2/connection.gleam`
- `src/aether/protocol/http2/error.gleam`
- `src/aether/protocol/http2/flow_control.gleam`
- `src/aether/protocol/http2/frame.gleam`
- `src/aether/protocol/http2/frame_builder.gleam`
- `src/aether/protocol/http2/frame_parser.gleam`
- `src/aether/protocol/http2/preface.gleam`
- `src/aether/protocol/http2/stage.gleam`
- `src/aether/protocol/http2/stream.gleam`
- `src/aether/protocol/http2/stream_manager.gleam`

### Protocol HPACK
- `src/aether/protocol/http2/hpack/decoder.gleam`
- `src/aether/protocol/http2/hpack/encoder.gleam`
- `src/aether/protocol/http2/hpack/huffman.gleam`
- `src/aether/protocol/http2/hpack/integer.gleam`
- `src/aether/protocol/http2/hpack/string.gleam`
- `src/aether/protocol/http2/hpack/table.gleam`

### Protocol TCP
- `src/aether/protocol/tcp/builder.gleam`
- `src/aether/protocol/tcp/checksum.gleam`
- `src/aether/protocol/tcp/connection.gleam`
- `src/aether/protocol/tcp/header.gleam`
- `src/aether/protocol/tcp/mode.gleam`
- `src/aether/protocol/tcp/parser.gleam`
- `src/aether/protocol/tcp/stage.gleam`
- `src/aether/protocol/tcp/state.gleam`

### Router
- `src/aether/router/group.gleam`
- `src/aether/router/params.gleam`
- `src/aether/router/pattern.gleam`
- `src/aether/router/router.gleam`

### Serialization
- `src/aether/serialization/json.gleam`
- `src/aether/serialization/negotiation.gleam`

### Utilities
- `src/aether/util/benchmark.gleam`
- `src/aether/util/time.gleam`

### Erlang FFI
- `src/aether_examples_runtime_ffi.erl`
- `src/aether_tcp_ffi.erl`
- `src/aether_udp_ffi.erl`

---

## 🛠️ 기술 스택

| 컴포넌트 | 패키지 | 버전 범위 | 역할 |
|----------|--------|-----------|------|
| 표준 라이브러리 | `gleam_stdlib` | `>= 0.44.0 and < 2.0.0` | 기본 자료구조와 유틸리티 |
| Erlang 연동 | `gleam_erlang` | `>= 1.0.0 and < 2.0.0` | BEAM/OTP 연동 |
| HTTP 타입 | `gleam_http` | `>= 4.0.0 and < 5.0.0` | HTTP 메서드/타입 |
| JSON | `gleam_json` | `>= 2.0.0 and < 4.0.0` | JSON 처리 |
| OTP | `gleam_otp` | `>= 1.0.0 and < 2.0.0` | 액터/슈퍼바이저 패턴 |
| 저수준 네트워킹 | `glisten` | `>= 8.0.1 and < 9.0.0` | 소켓과 리스너 |
| HTTP 서버 | `mist` | `>= 5.0.0 and < 6.0.0` | HTTP 서버 통합 |
| 테스트 | `gleeunit` | `>= 1.8.0 and < 2.0.0` | 테스트 러너 |

---

## 🚀 시작하기

### 사전 요구사항
- Gleam `>= 1.11.0`
- Erlang/OTP `>= 26`
- Git

### 설치

```bash
git clone https://github.com/jisung-02/aether.git
cd aether
gleam build
```

### 자주 쓰는 명령

```bash
# 전체 빌드
gleam build

# 데모 실행 (src/aether.gleam)
gleam run

# 멀티프로토콜 CRUD 서버 실행
gleam run -m aether/examples/server_main

# 테스트
gleam test

# 포맷 검사
gleam format --check src test
```

---

## 🌐 멀티프로토콜 서버 실행

`src/aether/examples/server_main.gleam`은 하나의 리스너에서 아래 두 모드를 지원합니다.

- 기본 모드: `HTTP/1.1 + h2c`
- TLS 모드: `HTTP/1.1 + HTTP/2` with `ALPN`

### 환경 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `AETHER_PORT` | 서버 포트 | `3000`(기본), TLS 사용 시 `3443` |
| `AETHER_TLS_CERT` | TLS 인증서 경로 | 미설정 |
| `AETHER_TLS_KEY` | TLS 개인키 경로 | 미설정 |

`AETHER_TLS_CERT`와 `AETHER_TLS_KEY`는 둘 다 있어야 TLS 모드가 활성화됩니다.

### Cleartext HTTP/1.1 + h2c

```bash
gleam run -m aether/examples/server_main

curl http://localhost:3000/api/users
curl --http2-prior-knowledge http://localhost:3000/api/users
```

### TLS + ALPN

```bash
AETHER_TLS_CERT=./cert.pem \
AETHER_TLS_KEY=./key.pem \
gleam run -m aether/examples/server_main

curl -k --http1.1 https://localhost:3443/api/users
curl -k --http2 https://localhost:3443/api/users
```

### 예제 엔드포인트

- `GET /api/users`
- `GET /api/users/:id`
- `POST /api/users`
- `PUT /api/users/:id`
- `DELETE /api/users/:id`
- `GET /api/http2/users`
- `GET /api/http2/users/:id`
- `POST /api/http2/users`
- `PUT /api/http2/users/:id`
- `DELETE /api/http2/users/:id`

---

## 🧩 라우터 예제

아래 예제는 현재 라우터 API에 맞는 최소 구성입니다.

```gleam
import aether/core/data.{type Data}
import aether/protocol/http/request
import aether/protocol/http/response
import aether/router/params
import aether/router/router

fn health(
  _req: request.ParsedRequest,
  _params: params.Params,
  _data: Data,
) -> Result(response.HttpResponse, router.RouteError) {
  Ok(response.text_response(200, "ok"))
}

pub fn app() -> router.Router {
  router.new()
  |> router.get("/health", health)
}
```

Path/query 파라미터는 `aether/router/params`에서 읽습니다.

```gleam
case params.get_int(route_params, "id") {
  Some(id) -> // use id
  None -> // invalid or missing
}
```

실제 서버와 Mist 통합 예시는 `src/aether/examples/server_main.gleam`을 참고하면 됩니다.

---

## 🚀 HTTP/2 프레임 처리 예제

현재 HTTP/2 연결 API는 아래 흐름으로 사용합니다.

```gleam
import aether/protocol/http2/connection

pub fn handle_request(incoming_frame) {
  let conn = connection.new_server()

  case connection.handle_frame(conn, incoming_frame) {
    connection.RequestComplete(conn, stream_id, headers, body) -> {
      let #(conn, response_frames) = connection.build_response(
        conn,
        stream_id,
        200,
        [#("content-type", "application/json")],
        body,
      )

      // send response_frames
    }
    connection.SendFrames(conn, frames) -> {
      // send control frames
    }
    connection.HandleOk(conn) -> {
      // state updated, nothing to send
    }
    connection.HandleError(conn, error) -> {
      // connection-level error handling
    }
  }
}
```

---

## 📋 현재 구현 상태

| 항목 | 상태 | 비고 |
|------|------|------|
| TCP/UDP 소켓 계층 | ✅ 구현 | 단위/통합 테스트 포함 |
| 연결 관리 | ✅ 구현 | manager/supervisor 포함 |
| HTTP/1.x 파싱/빌딩 | ✅ 구현 | parser, builder, stage 제공 |
| HTTP/2 프레이밍 | ✅ 구현 | frame/frame_parser/frame_builder |
| HPACK | ✅ 구현 | encoder/decoder/table/huffman 포함 |
| 스트림 관리/흐름 제어 | ✅ 구현 | `stream_manager`, `flow_control` |
| h2c + TLS/ALPN 예제 서버 | ✅ 구현 | `examples/multiprotocol/*` |
| 라우터 | ✅ 구현 | route group, params, mount 지원 |
| JSON 직렬화 | ✅ 구현 | `serialization/json` |
| Content negotiation | ✅ 구현 | `serialization/negotiation` |
| graceful shutdown timeout | ⚠️ 부분 구현 | `connection_manager`에 placeholder 존재 |
| benchmark 측정 정확도 | ⚠️ 부분 구현 | `util/benchmark`에 TODO 존재 |
| WebSocket | ❌ 미구현 | README 차원에서 별도 제공 없음 |
| HTTP/2 Server Push | ❌ 미구현 | README 차원에서 별도 제공 없음 |

---

## 🧪 개발 및 검증

GitHub Actions는 아래 명령을 기준으로 검증합니다.

```bash
gleam test
gleam format --check src test
```

현재 워크플로우 기준 CI 버전은 Gleam `1.12.0`, Erlang/OTP `27.1.2`입니다.

소켓 통합 테스트가 포함되어 있으므로, 실행 환경에 따라 네트워크 권한이 필요할 수 있습니다.

---

## 🤝 기여하기

기여 전 권장 절차:

```bash
gleam format
gleam test
```

PR 템플릿은 `.github/pull_request_template.md`를 사용합니다.

---

## 📄 라이선스

MIT License
