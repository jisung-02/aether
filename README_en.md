# ✨ Aether

[한국어 문서로 이동 🇰🇷](./README.md)

---

## A Gleam-based Server Framework

**Aether** is a Gleam server framework and networking learning stack. It covers low-level TCP/UDP socket wrappers, HTTP/1.x parsing and building, HTTP/2 framing and HPACK, composable pipelines, routing, JSON serialization, and content negotiation in a single repository.

The current codebase has two main surfaces.

- Framework modules: `src/aether/**`
- Runnable examples and integration entrypoints: `src/aether/examples/**`, `src/aether.gleam`

This project was created as a course assignment for the Full-Stack Service Networking class in the Department of Computer Science and Engineering at Kyung Hee University.

---

## 🌟 Key Capabilities

- Type-safe request/response handling with explicit `Result`-based errors
- TCP/UDP socket abstractions, option builders, error mapping, and connection management
- HTTP/1.x request parsing, response building, URL encoding/decoding, and pipeline stages
- HTTP/2 frame parsing/building, HPACK, stream management, and flow control
- Protocol registry, validator, and pipeline builder
- Pattern-matching router with route groups and path/query parameters
- JSON serialization and `Accept`-driven content negotiation
- A single-port example server for `HTTP/1.1 + h2c` or `TLS + ALPN(h2, http/1.1)`

---

## 📊 Current Repository Snapshot

| Metric | Value |
|--------|-------|
| Gleam modules under `src/aether` | 70 |
| Total files under `src` | 74 |
| Test files | 53 |
| Lines in `src` | 29,555 |
| Lines in `test` | 18,813 |
| Local verification | `gleam test` with 1308 passing tests |

These numbers are based on the current repository tree.

---

## 🏛️ Architecture Overview

### Network
- `tcp`, `udp`, `socket`, `transport`
- `connection`, `connection_manager`, `connection_supervisor`
- `connection_config`, `socket_options`, `socket_error`

### Protocol
- HTTP/1.x: request/response model, parser, builder, stage, and URL utilities
- HTTP/2: frame layer, connection state, stream management, and flow control
- HPACK: encoder, decoder, table, huffman, integer, and string utilities
- Learning-focused TCP protocol layer: header, parser, builder, checksum, state, stage, mode
- Protocol composition: `protocol`, `registry`, `validator`, `pipeline_builder`

### Application
- `pipeline/*` for composable processing stages
- `router/*` for path patterns, route groups, and parameter extraction
- `serialization/json` and `serialization/negotiation` for response formatting and negotiation

### Examples
- `src/aether.gleam`: runs HTTP/1.x and HTTP/2 demos
- `src/aether/examples/server_main.gleam`: multi-protocol CRUD server
- `src/aether/examples/http1/*`: HTTP/1.x CRUD router and handlers
- `src/aether/examples/http2/*`: frame-level HTTP/2 CRUD example
- `src/aether/examples/multiprotocol/*`: h2c / TLS ALPN runtime and server binding

---

## 📦 Module Layout

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

## 🛠️ Technology Stack

| Component | Package | Version Range | Role |
|-----------|---------|---------------|------|
| Standard library | `gleam_stdlib` | `>= 0.44.0 and < 2.0.0` | Core data structures and utilities |
| Erlang interop | `gleam_erlang` | `>= 1.0.0 and < 2.0.0` | BEAM/OTP interop |
| HTTP types | `gleam_http` | `>= 4.0.0 and < 5.0.0` | HTTP methods and shared types |
| JSON | `gleam_json` | `>= 2.0.0 and < 4.0.0` | JSON handling |
| OTP | `gleam_otp` | `>= 1.0.0 and < 2.0.0` | Actor and supervisor patterns |
| Low-level networking | `glisten` | `>= 8.0.1 and < 9.0.0` | Sockets and listeners |
| HTTP server | `mist` | `>= 5.0.0 and < 6.0.0` | HTTP server integration |
| Testing | `gleeunit` | `>= 1.8.0 and < 2.0.0` | Test runner |

---

## 🚀 Getting Started

### Prerequisites
- Gleam `>= 1.11.0`
- Erlang/OTP `>= 26`
- Git

### Installation

```bash
git clone https://github.com/jisung-02/aether.git
cd aether
gleam build
```

### Common Commands

```bash
# Build everything
gleam build

# Run demos (src/aether.gleam)
gleam run

# Run the multi-protocol CRUD server
gleam run -m aether/examples/server_main

# Run tests
gleam test

# Check formatting
gleam format --check src test
```

---

## 🌐 Running The Multi-Protocol Server

`src/aether/examples/server_main.gleam` supports both of the following modes on one listener.

- Default mode: `HTTP/1.1 + h2c`
- TLS mode: `HTTP/1.1 + HTTP/2` with `ALPN`

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AETHER_PORT` | Server port override | `3000`, or `3443` when TLS is enabled |
| `AETHER_TLS_CERT` | TLS certificate path | unset |
| `AETHER_TLS_KEY` | TLS private key path | unset |

`AETHER_TLS_CERT` and `AETHER_TLS_KEY` must both be set to enable TLS mode.

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

### Example Endpoints

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

## 🧩 Router Example

This is a minimal example that matches the current router API.

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

Path and query values are read through `aether/router/params`.

```gleam
case params.get_int(route_params, "id") {
  Some(id) -> // use id
  None -> // invalid or missing
}
```

For full Mist integration, see `src/aether/examples/server_main.gleam`.

---

## 🚀 HTTP/2 Frame Handling Example

The current HTTP/2 connection API is used as follows.

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

## 📋 Current Implementation Status

| Area | Status | Notes |
|------|--------|-------|
| TCP/UDP socket layer | ✅ Implemented | Includes unit and integration tests |
| Connection management | ✅ Implemented | Includes manager and supervisor modules |
| HTTP/1.x parsing/building | ✅ Implemented | Parser, builder, and pipeline stages |
| HTTP/2 framing | ✅ Implemented | `frame`, `frame_parser`, `frame_builder` |
| HPACK | ✅ Implemented | Encoder, decoder, table, huffman, integer |
| Stream management / flow control | ✅ Implemented | `stream_manager`, `flow_control` |
| h2c + TLS/ALPN example server | ✅ Implemented | `examples/multiprotocol/*` |
| Router | ✅ Implemented | Route groups, params, mount support |
| JSON serialization | ✅ Implemented | `serialization/json` |
| Content negotiation | ✅ Implemented | `serialization/negotiation` |
| Graceful shutdown timeout | ⚠️ Partial | Placeholder logic remains in `connection_manager` |
| Benchmark timing accuracy | ⚠️ Partial | `util/benchmark` still has TODO timing logic |
| WebSocket | ❌ Not implemented | No dedicated README surface yet |
| HTTP/2 Server Push | ❌ Not implemented | No dedicated README surface yet |

---

## 🧪 Development And Verification

GitHub Actions currently validates the project with the following commands.

```bash
gleam test
gleam format --check src test
```

The current workflow pins Gleam `1.12.0` and Erlang/OTP `27.1.2`.

Because socket integration tests are included, some environments may require network permissions for the full test suite.

---

## 🤝 Contributing

Recommended before opening a PR:

```bash
gleam format
gleam test
```

The repository uses `.github/pull_request_template.md` for pull requests.

---

## 📄 License

MIT License
