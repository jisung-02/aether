// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// User Type Definition
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Defines the User type and JSON serialization/deserialization functions
// for CRUD operations.
//

import gleam/json
import gleam/dynamic/decode

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// User entity
///
pub type User {
  User(id: Int, name: String, email: String)
}

/// Request to create a new user
///
pub type CreateUserRequest {
  CreateUserRequest(name: String, email: String)
}

/// Request to update an existing user
///
pub type UpdateUserRequest {
  UpdateUserRequest(name: String, email: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// JSON Serialization
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a User to JSON string
///
pub fn to_json(user: User) -> String {
  json.object([
    #("id", json.int(user.id)),
    #("name", json.string(user.name)),
    #("email", json.string(user.email)),
  ])
  |> json.to_string()
}

/// Converts a list of Users to JSON array string
///
pub fn list_to_json(users: List(User)) -> String {
  json.array(users, fn(user) {
    json.object([
      #("id", json.int(user.id)),
      #("name", json.string(user.name)),
      #("email", json.string(user.email)),
    ])
  })
  |> json.to_string()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// JSON Deserialization
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses a CreateUserRequest from JSON string
/// JSON 문자열에서 CreateUserRequest 파싱
///
pub fn parse_create_request(json_str: String) -> Result(CreateUserRequest, String) {
  let decoder = {
    use name <- decode.field("name", decode.string)
    use email <- decode.field("email", decode.string)
    decode.success(CreateUserRequest(name: name, email: email))
  }

  case json.parse(json_str, decoder) {
    Ok(request) -> Ok(request)
    Error(_) -> Error("Invalid JSON: expected {\"name\": string, \"email\": string}")
  }
}

/// Parses an UpdateUserRequest from JSON string
/// JSON 문자열에서 UpdateUserRequest 파싱
///
pub fn parse_update_request(json_str: String) -> Result(UpdateUserRequest, String) {
  let decoder = {
    use name <- decode.field("name", decode.string)
    use email <- decode.field("email", decode.string)
    decode.success(UpdateUserRequest(name: name, email: email))
  }

  case json.parse(json_str, decoder) {
    Ok(request) -> Ok(request)
    Error(_) -> Error("Invalid JSON: expected {\"name\": string, \"email\": string}")
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an error JSON response
///
pub fn error_json(message: String) -> String {
  json.object([
    #("error", json.string(message)),
  ])
  |> json.to_string()
}

/// Creates a success message JSON response
///
pub fn message_json(message: String) -> String {
  json.object([
    #("message", json.string(message)),
  ])
  |> json.to_string()
}
