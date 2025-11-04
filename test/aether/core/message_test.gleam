import gleam/dict
import gleam/dynamic
import gleam/option
import gleam/list

import gleeunit

import test_helper
import aether/core/message

pub fn main() -> Nil {
  gleeunit.main()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Message Operations Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn message_new_test() {
  let test_bytes = <<1, 2, 3>>
  let msg = message.new(test_bytes)

  test_helper.assert_equal(msg.bytes, test_bytes)
  test_helper.assert_equal(msg.metadata, dict.new())

  // Request ID should not be empty
  assert msg.context.request_id != ""

  // Started at should be positive
  assert msg.context.started_at > 0

  test_helper.assert_equal(msg.context.custom, dict.new())
}

pub fn message_empty_test() {
  let msg = message.empty()

  test_helper.assert_equal(msg.bytes, <<>>)
  test_helper.assert_equal(msg.metadata, dict.new())
}

pub fn message_from_string_test() {
  let test_string = "Hello, World!"
  let msg = message.from_string(test_string)

  test_helper.assert_equal(msg.bytes, <<test_string:utf8>>)
  test_helper.assert_equal(msg.metadata, dict.new())
}

pub fn message_bytes_test() {
  let test_bytes = <<1, 2, 3, 4>>
  let msg = message.new(test_bytes)

  test_helper.assert_equal(message.bytes(msg), test_bytes)
}

pub fn message_set_bytes_test() {
  let original_bytes = <<1, 2, 3>>
  let new_bytes = <<4, 5, 6>>
  let msg = message.new(original_bytes)
  let updated_msg = message.set_bytes(msg, new_bytes)

  // Original should be unchanged
  test_helper.assert_equal(message.bytes(msg), original_bytes)

  // Updated should have new bytes
  test_helper.assert_equal(message.bytes(updated_msg), new_bytes)
}

pub fn message_append_bytes_test() {
  let original_bytes = <<1, 2>>
  let additional_bytes = <<3, 4>>
  let msg = message.new(original_bytes)
  let updated_msg = message.append_bytes(msg, additional_bytes)

  // Original should be unchanged
  test_helper.assert_equal(message.bytes(msg), original_bytes)

  // Updated should have concatenated bytes
  test_helper.assert_equal(message.bytes(updated_msg), <<1, 2, 3, 4>>)
}

pub fn message_byte_size_test() {
  let test_bytes = <<1, 2, 3, 4, 5>>
  let msg = message.new(test_bytes)

  test_helper.assert_equal(message.byte_size(msg), 5)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Metadata Operations Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn metadata_set_get_test() {
  let msg = message.empty()
  let key = "content-type"
  let value = dynamic.string("application/json")

  let updated_msg = message.set_metadata(msg, key, value)

  test_helper.assert_equal(message.get_metadata(updated_msg, key), option.Some(value))

  // Original message should be unchanged
  test_helper.assert_equal(message.get_metadata(msg, key), option.None)
}

pub fn metadata_get_nonexistent_test() {
  let msg = message.empty()

  test_helper.assert_equal(message.get_metadata(msg, "nonexistent"), option.None)
}

pub fn metadata_delete_test() {
  let msg = message.empty()
  let key = "test-key"
  let value = dynamic.string("test-value")
  let with_metadata = message.set_metadata(msg, key, value)
  let without_metadata = message.delete_metadata(with_metadata, key)

  // Should be deleted in the new message
  test_helper.assert_equal(message.get_metadata(without_metadata, key), option.None)

  // Original message with metadata should be unchanged
  test_helper.assert_equal(message.get_metadata(with_metadata, key), option.Some(value))
}

pub fn metadata_has_key_test() {
  let msg = message.empty()
  let key = "test-key"
  let with_metadata = message.set_metadata(msg, key, dynamic.string("test-value"))

  test_helper.assert_equal(message.has_metadata(with_metadata, key), True)
  test_helper.assert_equal(message.has_metadata(msg, key), False)
}

pub fn metadata_keys_test() {
  let msg = message.empty()
  let updated_msg = msg
    |> message.set_metadata("key1", dynamic.string("value1"))
    |> message.set_metadata("key2", dynamic.string("value2"))
    |> message.set_metadata("key3", dynamic.string("value3"))

  let keys = message.metadata_keys(updated_msg)

  test_helper.assert_equal(list.contains(keys, "key1"), True)
  test_helper.assert_equal(list.contains(keys, "key2"), True)
  test_helper.assert_equal(list.contains(keys, "key3"), True)
  test_helper.assert_equal(list.length(keys), 3)
}

pub fn metadata_merge_test() {
  let msg = message.empty()
  let base_msg = msg
    |> message.set_metadata("existing", dynamic.string("old"))
    |> message.set_metadata("keep", dynamic.string("unchanged"))

  let new_metadata = dict.from_list([
    #("existing", dynamic.string("new")),
    #("added", dynamic.string("value")),
  ])

  let merged_msg = message.merge_metadata(base_msg, new_metadata)

  // Existing key should be overridden
  test_helper.assert_equal(message.get_metadata(merged_msg, "existing"), option.Some(dynamic.string("new")))

  // Added key should be present
  test_helper.assert_equal(message.get_metadata(merged_msg, "added"), option.Some(dynamic.string("value")))

  // Unchanged key should remain
  test_helper.assert_equal(message.get_metadata(merged_msg, "keep"), option.Some(dynamic.string("unchanged")))
}

pub fn metadata_clear_test() {
  let msg = message.empty()
  let with_metadata = msg
    |> message.set_metadata("key1", dynamic.string("value1"))
    |> message.set_metadata("key2", dynamic.string("value2"))

  let cleared_msg = message.clear_metadata(with_metadata)

  test_helper.assert_equal(list.length(message.metadata_keys(cleared_msg)), 0)

  // Original message should be unchanged
  test_helper.assert_equal(list.length(message.metadata_keys(with_metadata)), 2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Context Operations Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn context_new_test() {
  let ctx = message.new_context()

  // Request ID should not be empty
  assert ctx.request_id != ""

  // Started at should be positive
  assert ctx.started_at > 0

  test_helper.assert_equal(ctx.custom, dict.new())
}

pub fn context_new_with_id_test() {
  let test_id = "test-request-123"
  let ctx = message.new_context_with_id(test_id)

  test_helper.assert_equal(ctx.request_id, test_id)

  // Started at should be positive
  assert ctx.started_at > 0

  test_helper.assert_equal(ctx.custom, dict.new())
}

pub fn context_request_id_test() {
  let test_id = "test-request-456"
  let ctx = message.new_context_with_id(test_id)
  let msg = message.Message(
    bytes: <<>>,
    metadata: dict.new(),
    context: ctx,
  )

  test_helper.assert_equal(message.request_id(msg), test_id)
}

pub fn context_started_at_test() {
  let msg1 = message.empty()
  let started_at1 = message.started_at(msg1)

  // Create another message a moment later
  let msg2 = message.empty()
  let started_at2 = message.started_at(msg2)

  // Second message should have later or equal start time
  assert started_at2 >= started_at1

  // Both should be reasonable timestamps (greater than 0)
  assert started_at1 > 0
  assert started_at2 > 0
}

pub fn context_elapsed_test() {
  let msg = message.empty()

  // Should start with small elapsed time
  let initial_elapsed = message.elapsed_microseconds(msg)
  assert initial_elapsed >= 0

  let initial_ms = message.elapsed_milliseconds(msg)
  assert initial_ms >= 0

  // Milliseconds should be approximately equal to microseconds divided by 1000
  // Allow for small timing differences between the two calls
  let expected_ms = initial_elapsed / 1000
  let diff = case initial_ms > expected_ms {
    True -> initial_ms - expected_ms
    False -> expected_ms - initial_ms
  }

  // Allow difference of up to 10ms due to timing and execution delays
  assert diff <= 10
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Custom Context Data Operations Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn context_data_set_get_test() {
  let msg = message.empty()
  let key = "user_id"
  let value = dynamic.string("alice")

  let updated_msg = message.set_context_data(msg, key, value)

  test_helper.assert_equal(message.get_context_data(updated_msg, key), option.Some(value))

  // Original message should be unchanged
  test_helper.assert_equal(message.get_context_data(msg, key), option.None)
}

pub fn context_data_get_nonexistent_test() {
  let msg = message.empty()

  test_helper.assert_equal(message.get_context_data(msg, "nonexistent"), option.None)
}

pub fn context_data_delete_test() {
  let msg = message.empty()
  let key = "session"
  let value = dynamic.string("abc123")
  let with_data = message.set_context_data(msg, key, value)
  let without_data = message.delete_context_data(with_data, key)

  // Should be deleted in the new message
  test_helper.assert_equal(message.get_context_data(without_data, key), option.None)

  // Original message should be unchanged
  test_helper.assert_equal(message.get_context_data(with_data, key), option.Some(value))
}

pub fn context_data_has_key_test() {
  let msg = message.empty()
  let key = "auth_token"
  let with_data = message.set_context_data(msg, key, dynamic.string("token123"))

  test_helper.assert_equal(message.has_context_data(with_data, key), True)
  test_helper.assert_equal(message.has_context_data(msg, key), False)
}

pub fn context_data_keys_test() {
  let msg = message.empty()
  let updated_msg = msg
    |> message.set_context_data("user", dynamic.string("alice"))
    |> message.set_context_data("role", dynamic.string("admin"))
    |> message.set_context_data("session", dynamic.string("xyz789"))

  let keys = message.context_data_keys(updated_msg)

  test_helper.assert_equal(list.contains(keys, "user"), True)
  test_helper.assert_equal(list.contains(keys, "role"), True)
  test_helper.assert_equal(list.contains(keys, "session"), True)
  test_helper.assert_equal(list.length(keys), 3)
}

pub fn context_data_merge_test() {
  let msg = message.empty()
  let base_msg = msg
    |> message.set_context_data("existing", dynamic.string("old"))
    |> message.set_context_data("keep", dynamic.string("unchanged"))

  let new_custom = dict.from_list([
    #("existing", dynamic.string("new")),
    #("added", dynamic.string("value")),
  ])

  let merged_msg = message.merge_context_data(base_msg, new_custom)

  // Existing key should be overridden
  test_helper.assert_equal(message.get_context_data(merged_msg, "existing"), option.Some(dynamic.string("new")))

  // Added key should be present
  test_helper.assert_equal(message.get_context_data(merged_msg, "added"), option.Some(dynamic.string("value")))

  // Unchanged key should remain
  test_helper.assert_equal(message.get_context_data(merged_msg, "keep"), option.Some(dynamic.string("unchanged")))
}

pub fn context_data_clear_test() {
  let msg = message.empty()
  let with_data = msg
    |> message.set_context_data("key1", dynamic.string("value1"))
    |> message.set_context_data("key2", dynamic.string("value2"))

  let cleared_msg = message.clear_context_data(with_data)

  test_helper.assert_equal(list.length(message.context_data_keys(cleared_msg)), 0)

  // Original message should be unchanged
  test_helper.assert_equal(list.length(message.context_data_keys(with_data)), 2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn message_comprehensive_operations_test() {
  let base_msg = message.from_string("test data")

  let final_msg = base_msg
    |> message.set_metadata("content-type", dynamic.string("text/plain"))
    |> message.set_metadata("content-length", dynamic.string("9"))
    |> message.set_context_data("user_id", dynamic.string("alice"))
    |> message.set_context_data("role", dynamic.string("admin"))
    |> message.append_bytes(<<0, 1, 2>>)

  // Verify all operations worked
  test_helper.assert_equal(message.bytes(final_msg), <<"test data":utf8, 0, 1, 2>>)

  test_helper.assert_equal(message.get_metadata(final_msg, "content-type"), option.Some(dynamic.string("text/plain")))
  test_helper.assert_equal(message.get_metadata(final_msg, "content-length"), option.Some(dynamic.string("9")))
  test_helper.assert_equal(message.get_context_data(final_msg, "user_id"), option.Some(dynamic.string("alice")))
  test_helper.assert_equal(message.get_context_data(final_msg, "role"), option.Some(dynamic.string("admin")))

  test_helper.assert_equal(message.byte_size(final_msg), 12) // "test data" (9) + <<0, 1, 2>> (3)
}

pub fn message_immutability_test() {
  let original_msg = message.empty()

  let with_metadata = message.set_metadata(original_msg, "key", dynamic.string("value"))
  let with_context = message.set_context_data(original_msg, "ctx", dynamic.string("data"))
  let _with_bytes = message.set_bytes(original_msg, <<1, 2, 3>>)

  // Original message should remain unchanged
  test_helper.assert_equal(list.length(message.metadata_keys(original_msg)), 0)
  test_helper.assert_equal(list.length(message.context_data_keys(original_msg)), 0)
  test_helper.assert_equal(message.bytes(original_msg), <<>>)

  // Each modified message should have only its changes
  test_helper.assert_equal(list.length(message.metadata_keys(with_metadata)), 1)
  test_helper.assert_equal(list.length(message.context_data_keys(with_metadata)), 0)
  test_helper.assert_equal(message.bytes(with_metadata), <<>>)

  test_helper.assert_equal(list.length(message.context_data_keys(with_context)), 1)
  test_helper.assert_equal(list.length(message.metadata_keys(with_context)), 0)
  test_helper.assert_equal(message.bytes(with_context), <<>>)
}