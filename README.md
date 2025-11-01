# ✨ Aether

[한국어 문서로 이동 🇰🇷](./README_ko.md)

---

### A Gleam-based Server Framework

**Aether** is a server framework developed based on the Gleam language.

The framework aims to build type-safe, easy-to-maintain backend systems by focusing on core values: **Explicitness** and **Independence between Layers (Decoupling)**.

#### 🌟 Key Features

* **Type-Safe Foundation:** Leverages Gleam's strong type system to catch errors at compile time.
* **Decoupled Architecture:** Clearly separates layers such as request handling, routing, and business logic to maximize code independence and testability.
* **Powered by BEAM:** Provides a scalable and reliable server based on the concurrency and fault tolerance of the Erlang VM (using `Mist`).

#### 🛠️ Core Technology Stack

| Component | Package | Role |
| :--- | :--- | :--- |
| **HTTP Server** | `mist` | Robust and fast HTTP server implementation. |
| **HTTP Types** | `gleam_http` | Core HTTP type definitions for requests and responses. |
| **JSON Handling** | `gleam_json` | Type-safe JSON encoding and decoding support. |

#### 🚀 Getting Started

Clone the project and install dependencies:

```bash
gleam build
gleam run