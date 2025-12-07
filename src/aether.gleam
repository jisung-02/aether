// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// // Aether HTTP/1.1 Server Example
// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// //
// // This demonstrates a simple HTTP/1.1 server using the Aether framework
// // with routing, JSON responses, and dynamic path parameters.
// //
// // Run with: gleam run
// //

// import aether/core/message.{type Message}
// import aether/pipeline/pipeline
// import aether/protocol/http/request as aether_request
// import aether/protocol/http/response as aether_response
// import aether/protocol/http/stage as http_stage
// import aether/router/params.{type Params}
// import aether/router/router.{type RouteError}
// import gleam/bit_array
// import gleam/bytes_tree
// import gleam/erlang/process
// import gleam/http.{Delete, Get, Head, Options, Patch, Post, Put}
// import gleam/http/request as http_request
// import gleam/http/response as http_response
// import gleam/int
// import gleam/io
// import gleam/json
// import gleam/list
// import gleam/option
// import gleam/string
// import mist.{type Connection, type ResponseData}

// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// // Route Handlers
// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// /// Home page handler - returns a welcome message
// fn home_handler(
//   _req: aether_request.ParsedRequest,
//   _params: Params,
//   _data: Message,
// ) -> Result(aether_response.HttpResponse, RouteError) {
//   let body =
//     json.object([
//       #("message", json.string("Welcome to Aether HTTP Server!")),
//       #("version", json.string("1.0.0")),
//     ])

//   Ok(aether_response.json_response(200, body))
// }

// /// Health check handler
// fn health_handler(
//   _req: aether_request.ParsedRequest,
//   _params: Params,
//   _data: Message,
// ) -> Result(aether_response.HttpResponse, RouteError) {
//   let body = json.object([#("status", json.string("healthy"))])

//   Ok(aether_response.json_response(200, body))
// }

// /// Get user by ID handler - demonstrates dynamic path parameters
// fn get_user_handler(
//   _req: aether_request.ParsedRequest,
//   p: Params,
//   _data: Message,
// ) -> Result(aether_response.HttpResponse, RouteError) {
//   case params.get_int(p, "id") {
//     option.Some(user_id) -> {
//       let body =
//         json.object([
//           #("id", json.int(user_id)),
//           #("name", json.string("User " <> int.to_string(user_id))),
//           #(
//             "email",
//             json.string("user" <> int.to_string(user_id) <> "@example.com"),
//           ),
//         ])

//       Ok(aether_response.json_response(200, body))
//     }
//     option.None -> {
//       let body = json.object([#("error", json.string("Invalid user ID"))])

//       Ok(aether_response.json_response(400, body))
//     }
//   }
// }

// /// List all users handler
// fn list_users_handler(
//   _req: aether_request.ParsedRequest,
//   _params: Params,
//   _data: Message,
// ) -> Result(aether_response.HttpResponse, RouteError) {
//   let users =
//     json.array(
//       [
//         json.object([#("id", json.int(1)), #("name", json.string("Alice"))]),
//         json.object([#("id", json.int(2)), #("name", json.string("Bob"))]),
//         json.object([#("id", json.int(3)), #("name", json.string("Charlie"))]),
//       ],
//       fn(x) { x },
//     )

//   let body = json.object([#("users", users)])

//   Ok(aether_response.json_response(200, body))
// }

// /// Create user handler - demonstrates POST request handling
// fn create_user_handler(
//   req: aether_request.ParsedRequest,
//   _params: Params,
//   _data: Message,
// ) -> Result(aether_response.HttpResponse, RouteError) {
//   let body_str = case bit_array.to_string(req.body) {
//     Ok(s) -> s
//     Error(_) -> ""
//   }

//   let response_body =
//     json.object([
//       #("message", json.string("User created successfully")),
//       #("received_body", json.string(body_str)),
//     ])

//   Ok(aether_response.json_response(201, response_body))
// }

// /// Echo handler - echoes back request information
// fn echo_handler(
//   req: aether_request.ParsedRequest,
//   _p: Params,
//   _data: Message,
// ) -> Result(aether_response.HttpResponse, RouteError) {
//   let body_str = case bit_array.to_string(req.body) {
//     Ok(s) -> s
//     Error(_) -> "<binary data>"
//   }

//   let response_body =
//     json.object([
//       #("method", json.string(aether_request.method_to_string(req.method))),
//       #("uri", json.string(req.uri)),
//       #("version", json.string(aether_request.version_to_string(req.version))),
//       #("body", json.string(body_str)),
//     ])

//   Ok(aether_response.json_response(200, response_body))
// }

// /// Custom 404 handler
// fn not_found_handler(
//   req: aether_request.ParsedRequest,
//   _params: Params,
//   _data: Message,
// ) -> Result(aether_response.HttpResponse, RouteError) {
//   let body =
//     json.object([
//       #("error", json.string("Not Found")),
//       #("path", json.string(req.uri)),
//       #("message", json.string("The requested resource does not exist")),
//     ])

//   Ok(aether_response.json_response(404, body))
// }

// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// // Router & Pipeline Setup
// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// /// Creates and configures the application router
// fn create_router() -> router.Router {
//   router.new()
//   |> router.get("/", home_handler)
//   |> router.get("/health", health_handler)
//   |> router.get("/users", list_users_handler)
//   |> router.get("/users/:id", get_user_handler)
//   |> router.post("/users", create_user_handler)
//   |> router.any("/echo", echo_handler)
//   |> router.not_found(not_found_handler)
// }

// /// Creates the request processing pipeline
// fn create_pipeline(
//   app_router: router.Router,
// ) -> pipeline.Pipeline(Message, Message) {
//   pipeline.new()
//   |> pipeline.pipe(http_stage.decode())
//   |> pipeline.pipe(router.to_stage(app_router))
//   |> pipeline.pipe(http_stage.encode_response())
// }

// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// // Mist Integration
// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// /// Handles incoming HTTP requests through the pipeline
// fn handle_request(
//   req: http_request.Request(Connection),
//   processing_pipeline: pipeline.Pipeline(Message, Message),
// ) -> http_response.Response(ResponseData) {
//   let body_result = mist.read_body(req, 1024 * 1024)

//   case body_result {
//     Ok(mist_req) -> {
//       let raw_request = build_raw_request(mist_req)
//       let input_message = message.new(raw_request)

//       case pipeline.execute(processing_pipeline, input_message) {
//         Ok(result_message) -> {
//           let response_bytes = message.bytes(result_message)
//           parse_response_bytes(response_bytes)
//         }
//         Error(err) -> {
//           io.println("Pipeline error: " <> string.inspect(err))
//           internal_server_error()
//         }
//       }
//     }
//     Error(_) -> bad_request_response()
//   }
// }

// /// Builds raw HTTP request bytes from mist request
// fn build_raw_request(req: http_request.Request(BitArray)) -> BitArray {
//   let method = case req.method {
//     Get -> "GET"
//     Post -> "POST"
//     Put -> "PUT"
//     Delete -> "DELETE"
//     Patch -> "PATCH"
//     Head -> "HEAD"
//     Options -> "OPTIONS"
//     _ -> "GET"
//   }

//   let path = req.path

//   let headers_str =
//     req.headers
//     |> list.map(fn(h: #(String, String)) { h.0 <> ": " <> h.1 })
//     |> string.join("\r\n")

//   let body = req.body

//   let request_line = method <> " " <> path <> " HTTP/1.1\r\n"
//   let full_request = request_line <> headers_str <> "\r\n\r\n"

//   <<full_request:utf8, body:bits>>
// }

// /// Parses response bytes back to mist response
// fn parse_response_bytes(bytes: BitArray) -> http_response.Response(ResponseData) {
//   case bit_array.to_string(bytes) {
//     Ok(response_str) -> {
//       case string.split_once(response_str, "\r\n\r\n") {
//         Ok(#(headers_part, body_str)) -> {
//           let status = extract_status(headers_part)
//           let headers = extract_headers(headers_part)

//           http_response.Response(
//             status: status,
//             headers: headers,
//             body: mist.Bytes(bytes_tree.from_string(body_str)),
//           )
//         }
//         Error(_) -> internal_server_error()
//       }
//     }
//     Error(_) -> internal_server_error()
//   }
// }

// /// Extracts status code from response headers
// fn extract_status(headers_part: String) -> Int {
//   case string.split_once(headers_part, "\r\n") {
//     Ok(#(status_line, _)) -> {
//       let parts = string.split(status_line, " ")
//       case parts {
//         [_, status_str, ..] -> {
//           case int.parse(status_str) {
//             Ok(status) -> status
//             Error(_) -> 500
//           }
//         }
//         _ -> 500
//       }
//     }
//     Error(_) -> 500
//   }
// }

// /// Extracts headers from response
// fn extract_headers(headers_part: String) -> List(#(String, String)) {
//   case string.split_once(headers_part, "\r\n") {
//     Ok(#(_, rest)) -> {
//       rest
//       |> string.split("\r\n")
//       |> list.filter_map(fn(line) {
//         case string.split_once(line, ": ") {
//           Ok(#(name, value)) -> Ok(#(string.lowercase(name), value))
//           Error(_) -> Error(Nil)
//         }
//       })
//     }
//     Error(_) -> []
//   }
// }

// fn internal_server_error() -> http_response.Response(ResponseData) {
//   let body =
//     json.to_string(json.object([
//       #("error", json.string("Internal Server Error")),
//     ]))

//   http_response.Response(
//     status: 500,
//     headers: [#("content-type", "application/json")],
//     body: mist.Bytes(bytes_tree.from_string(body)),
//   )
// }

// fn bad_request_response() -> http_response.Response(ResponseData) {
//   let body =
//     json.to_string(json.object([#("error", json.string("Bad Request"))]))

//   http_response.Response(
//     status: 400,
//     headers: [#("content-type", "application/json")],
//     body: mist.Bytes(bytes_tree.from_string(body)),
//   )
// }

// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// // Main Entry Point
// // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// pub fn main() {
//   io.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
//   io.println("  Aether HTTP/1.1 Server")
//   io.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
//   io.println("")
//   io.println("  Available routes:")
//   io.println("    GET  /           - Home page")
//   io.println("    GET  /health     - Health check")
//   io.println("    GET  /users      - List all users")
//   io.println("    GET  /users/:id  - Get user by ID")
//   io.println("    POST /users      - Create new user")
//   io.println("    ANY  /echo       - Echo request details")
//   io.println("")
//   io.println("  Starting server on http://localhost:3000")
//   io.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

//   let app_router = create_router()
//   let processing_pipeline = create_pipeline(app_router)

//   let assert Ok(_) =
//     fn(req) { handle_request(req, processing_pipeline) }
//     |> mist.new
//     |> mist.port(3000)
//     |> mist.start

//   process.sleep_forever()
// }
