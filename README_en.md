# ✨ Aether

[한국어 문서로 이동 🇰🇷](./README.md)

---

## A Gleam-based Server Framework

**Aether** is a comprehensive server framework built with the Gleam programming language, designed for building type-safe, scalable, and maintainable backend systems.

The framework provides a complete networking stack from low-level TCP/UDP to high-level HTTP/2, all with Gleam's strong type system guarantees.

This project was created as a course assignment for the Full-Stack Service Networking class in the Department of Computer Science and Engineering at Kyung Hee University.

---

## 🌟 Key Features

### 🔒 Type-Safe Foundation
- Leverages Gleam's strong type system to catch errors at compile time
- All APIs designed with explicit error handling using `Result` types
- No runtime exceptions - predictable behavior

### 🏗️ Layered Architecture
- **Network Layer**: Raw TCP/UDP socket operations with connection management
- **Protocol Layer**: Protocol-agnostic abstractions (HTTP/1.x, HTTP/2)
- **Pipeline Layer**: Composable request/response processing stages
- **Router Layer**: Type-safe URL routing with pattern matching

### 🚀 HTTP/2 Support
- Full HTTP/2 binary framing (RFC 9113)
- HPACK header compression (RFC 7541)
- Stream multiplexing
- Flow control
- Connection preface handling

### ⚡ Powered by BEAM
- Built on Erlang VM's battle-tested concurrency model
- Fault-tolerant with supervisor trees
- Scalable connection handling via OTP patterns

---

## 📊 Project Statistics

| Metric | Value |
|--------|-------|
| Source Files | 60+ |
| Lines of Code | ~236,000 |
| Test Cases | 1,300 |
| Test Coverage | All passing ✅ |

---

## 🏛️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Application Layer                       │
├─────────────────────────────────────────────────────────────┤
│  Router        │  Middleware     │  Serialization            │
│  - Pattern     │  - Composable   │  - JSON                   │
│  - Groups      │  - Type-safe    │  - Binary                 │
│  - Params      │                 │                           │
├─────────────────────────────────────────────────────────────┤
│                      Pipeline Layer                          │
│  - Stage       │  - Executor     │  - Compose                │
│  - Error       │  - Pipeline     │                           │
├─────────────────────────────────────────────────────────────┤
│                      Protocol Layer                          │
│  ┌─────────────────────┐  ┌─────────────────────┐           │
│  │       HTTP/1.x      │  │       HTTP/2        │           │
│  │  - Request/Response │  │  - Frame Layer      │           │
│  │  - Headers          │  │  - HPACK            │           │
│  │  - Body             │  │  - Stream Manager   │           │
│  │                     │  │  - Flow Control     │           │
│  │                     │  │  - Connection       │           │
│  └─────────────────────┘  └─────────────────────┘           │
├─────────────────────────────────────────────────────────────┤
│                      Network Layer                           │
│  - TCP          │  - UDP          │  - Socket                │
│  - Connection   │  - Transport    │  - Manager               │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Module Structure

### Core (`aether/core`)
- `data.gleam` - Core data types
- `message.gleam` - Message definitions

### Network (`aether/network`)
- `tcp.gleam` - TCP socket operations
- `udp.gleam` - UDP socket operations
- `socket.gleam` - Socket abstractions
- `transport.gleam` - Transport layer
- `connection.gleam` - Connection state machine
- `connection_manager.gleam` - Connection pool management
- `connection_supervisor.gleam` - OTP supervisor integration

### Protocol (`aether/protocol`)

#### HTTP (`aether/protocol/http`)
- `request.gleam` - HTTP request handling
- `response.gleam` - HTTP response building
- `headers.gleam` - Header manipulation
- `body.gleam` - Body processing
- `unified.gleam` - Protocol-agnostic request/response

#### HTTP/2 (`aether/protocol/http2`)
- `frame.gleam` - Frame type definitions
- `frame_parser.gleam` - Binary frame parsing
- `frame_builder.gleam` - Frame serialization
- `stream.gleam` - Stream state machine
- `stream_manager.gleam` - Multi-stream management
- `flow_control.gleam` - Window-based flow control
- `connection.gleam` - HTTP/2 connection handler
- `preface.gleam` - Connection preface
- `stage.gleam` - Aether pipeline integration
- `error.gleam` - Error types

#### HPACK (`aether/protocol/http2/hpack`)
- `table.gleam` - Static/dynamic header tables
- `encoder.gleam` - Header compression
- `decoder.gleam` - Header decompression
- `huffman.gleam` - Huffman coding
- `integer.gleam` - Variable-length integers
- `string.gleam` - String encoding

#### TCP Protocol (`aether/protocol/tcp`)
- `connection.gleam` - TCP connection handling
- `reliable_delivery.gleam` - Reliability layer
- `segment.gleam` - TCP segments

### Pipeline (`aether/pipeline`)
- `pipeline.gleam` - Pipeline builder
- `stage.gleam` - Processing stages
- `compose.gleam` - Stage composition
- `executor.gleam` - Pipeline execution
- `error.gleam` - Error handling

### Router (`aether/router`)
- `router.gleam` - Main router
- `pattern.gleam` - URL pattern matching
- `group.gleam` - Route grouping
- `params.gleam` - Parameter extraction

### Serialization (`aether/serialization`)
- JSON encoding/decoding support
- Binary serialization

### Utilities (`aether/util`)
- `benchmark.gleam` - Performance utilities
- Helper functions

---

## 🛠️ Technology Stack

| Component | Package | Version | Role |
|-----------|---------|---------|------|
| **HTTP Server** | `mist` | 5.x | HTTP server implementation |
| **HTTP Types** | `gleam_http` | 4.x | HTTP type definitions |
| **JSON** | `gleam_json` | 2.x | JSON processing |
| **OTP** | `gleam_otp` | 1.x | Concurrency patterns |
| **Sockets** | `glisten` | 8.x | Low-level networking |
| **Standard Library** | `gleam_stdlib` | 0.44+ | Core utilities |

---

## 🚀 Getting Started

### Prerequisites
- Gleam >= 1.11.0
- Erlang/OTP >= 26

### Installation

```bash
git clone https://github.com/jisung-02/gleam_aether.git
cd gleam_aether/aether
gleam build
```

### Running Tests

```bash
gleam test
```

### Example: Serve HTTP/1.1 + HTTP/2 On One Port

The example server in `src/aether/examples/server_main.gleam` now accepts both `HTTP/1.1` and `HTTP/2` on the same listener.

- Default: `http://localhost:3000` with `HTTP/1.1` + `h2c`
- With TLS: set `AETHER_TLS_CERT` and `AETHER_TLS_KEY` to enable `https://localhost:3443` with `ALPN (h2, http/1.1)`

```bash
# Cleartext HTTP/1.1 + h2c
gleam run -m aether/examples/server_main

# HTTP/1.1
curl http://localhost:3000/api/users

# HTTP/2 prior knowledge
curl --http2-prior-knowledge http://localhost:3000/api/users

# TLS + ALPN
AETHER_TLS_CERT=./cert.pem AETHER_TLS_KEY=./key.pem gleam run -m aether/examples/server_main

# TLS HTTP/2
curl -k --http2 https://localhost:3443/api/users
```

### Example: Basic HTTP Server

```gleam
import aether/router.{router, get, post}
import aether/protocol/http/response

pub fn main() {
  let app = router()
    |> get("/", fn(_req) { response.ok("Hello, Aether!") })
    |> get("/health", fn(_req) { response.json(#("status", "ok")) })
    |> post("/api/users", create_user)
  
  // Start server with Mist
  start_server(app, port: 8080)
}
```

### Example: HTTP/2 Frame Handling

```gleam
import aether/protocol/http2/connection
import aether/protocol/http2/frame_builder

pub fn handle_request() {
  let conn = connection.new_server()
  
  // Handle incoming frame
  case connection.handle_frame(conn, incoming_frame) {
    connection.RequestComplete(conn, stream_id, headers, body) -> {
      // Build response
      let #(conn, response_frames) = connection.build_response(
        conn, stream_id, 200,
        [#("content-type", "application/json")],
        body
      )
      // Send response_frames
    }
    connection.SendFrames(conn, frames) -> {
      // Send control frames (SETTINGS ACK, etc.)
    }
    _ -> // Handle other cases
  }
}
```

---

## 📋 Implementation Status

| Feature | Status |
|---------|--------|
| TCP/UDP Networking | ✅ Complete |
| Connection Management | ✅ Complete |
| HTTP/1.x Support | ✅ Complete |
| HTTP/2 Framing | ✅ Complete |
| HPACK Compression | ✅ Complete |
| Stream Multiplexing | ✅ Complete |
| Flow Control | ✅ Complete |
| Pipeline Architecture | ✅ Complete |
| Router | ✅ Complete |
| Server Push | ⏳ Planned |
| TLS/ALPN | ⏳ Planned |
| WebSocket | ⏳ Planned |

---

## 📄 License

MIT License

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

*Built with ❤️ using Gleam*
