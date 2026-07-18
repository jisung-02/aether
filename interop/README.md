# HTTP/3 Interop

Manual interoperability check for the Aether QUIC + HTTP/3 server against a
real client.

## What the automated tests already prove

`test/aether/protocol/quic/connection_test.gleam` runs a complete handshake
and an HTTP/3 GET **in process**: a test-only QUIC + TLS 1.3 client, built
from the same primitives as the server, protects a real client Initial,
completes the TLS 1.3 handshake (X25519, `TLS_AES_128_GCM_SHA256`, ALPN
`h3`), and exchanges an HTTP/3 request/response — all decrypted and decoded
byte-for-byte. The crypto layer is additionally checked against the RFC 9001
and RFC 8448 test vectors. So the wire format, packet protection, handshake,
QPACK, and framing are validated without an external peer.

## Verified against real curl

curl 8.21.0 (ngtcp2/nghttp3) completes the handshake and gets the response:

```
$ CURL=/opt/homebrew/opt/curl/bin/curl ./interop/run.sh
Hello from Aether HTTP/3
[status 200, 3]
```

(`version 3` = HTTP/3.)

## Running against real curl / a browser

The server serves a fixed `200 text/plain` response on `GET /`.

```sh
# Needs an HTTP/3-capable curl (the macOS system curl is not).
brew install curl
CURL=/opt/homebrew/opt/curl/bin/curl ./interop/run.sh
```

`run.sh` starts `aether/examples/http3/server` (port 4433, using the
self-signed EC certificate in `test/fixtures/tls/`) and issues
`curl --http3-only -k https://localhost:4433/`.

Expected output:

```
Hello from Aether HTTP/3
[status 200, 3]
```

Browsers: enable HTTP/3/QUIC and open `https://localhost:4433/`, accepting
the self-signed certificate.

## Scope

The runtime targets the localhost happy path (one client, in-order
delivery, server authentication). Retry, Version Negotiation, 0-RTT, key
update, connection migration, and active PTO retransmission are not yet
implemented — see `docs/superpowers/specs/2026-07-18-quic-runtime-interop-design.md`.
