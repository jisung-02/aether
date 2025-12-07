// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// In-Memory Store
// 메모리 내 데이터 저장소
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// A simple in-memory store for User entities using Dict.
// Dict를 사용한 간단한 User 엔티티 메모리 저장소
//
// This is a pure functional implementation - each operation returns
// a new Store instance.
// 순수 함수형 구현 - 각 연산은 새로운 Store 인스턴스를 반환
//

import aether/examples/common/user.{type User, User}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// In-memory store for users
///
pub type Store {
  Store(users: Dict(Int, User), next_id: Int)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Store Creation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new empty store
///
pub fn new() -> Store {
  Store(users: dict.new(), next_id: 1)
}

/// Creates a store with sample data
///
pub fn with_sample_data() -> Store {
  new()
  |> create("Alice", "alice@example.com")
  |> fn(result) { result.0 }
  |> create("Bob", "bob@example.com")
  |> fn(result) { result.0 }
  |> create("Charlie", "charlie@example.com")
  |> fn(result) { result.0 }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Read Operations
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets all users as a list
///
pub fn get_all(store: Store) -> List(User) {
  store.users
  |> dict.values()
  |> list.sort(fn(a, b) { compare_int(a.id, b.id) })
}

/// Gets a user by ID
///
pub fn get_one(store: Store, id: Int) -> Option(User) {
  case dict.get(store.users, id) {
    Ok(user) -> Some(user)
    Error(_) -> None
  }
}

/// Checks if a user exists
///
pub fn exists(store: Store, id: Int) -> Bool {
  dict.has_key(store.users, id)
}

/// Gets the count of users
///
pub fn count(store: Store) -> Int {
  dict.size(store.users)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Write Operations
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new user
///
/// Returns the updated store and the created user.
///
pub fn create(store: Store, name: String, email: String) -> #(Store, User) {
  let id = store.next_id
  let user = User(id: id, name: name, email: email)
  let new_users = dict.insert(store.users, id, user)
  let new_store = Store(users: new_users, next_id: id + 1)
  #(new_store, user)
}

/// Updates an existing user
///
/// Returns the updated store and the updated user (if found).
///
pub fn update(
  store: Store,
  id: Int,
  name: String,
  email: String,
) -> #(Store, Option(User)) {
  case dict.get(store.users, id) {
    Ok(_existing) -> {
      let updated_user = User(id: id, name: name, email: email)
      let new_users = dict.insert(store.users, id, updated_user)
      let new_store = Store(..store, users: new_users)
      #(new_store, Some(updated_user))
    }
    Error(_) -> #(store, None)
  }
}

/// Deletes a user by ID
///
/// Returns the updated store and whether the deletion was successful.
///
pub fn delete(store: Store, id: Int) -> #(Store, Bool) {
  case dict.get(store.users, id) {
    Ok(_) -> {
      let new_users = dict.delete(store.users, id)
      let new_store = Store(..store, users: new_users)
      #(new_store, True)
    }
    Error(_) -> #(store, False)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Compares two integers for sorting
/// 정렬을 위한 정수 비교 함수
///
fn compare_int(a: Int, b: Int) -> order.Order {
  case a < b {
    True -> order.Lt
    False ->
      case a > b {
        True -> order.Gt
        False -> order.Eq
      }
  }
}
