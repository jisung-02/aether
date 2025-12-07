import aether/core/data.{type Data}
import aether/core/message
import aether/pipeline/pipeline
import aether/pipeline/stage
import aether/protocol/pipeline_builder
import aether/protocol/protocol
import aether/protocol/registry
import gleam/result
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn create_test_registry() -> registry.Registry {
  let tcp_decode: stage.Stage(Data, Data) =
    stage.new("tcp_decode", fn(data) { Ok(data) })
  let tcp_encode: stage.Stage(Data, Data) =
    stage.new("tcp_encode", fn(data) { Ok(data) })

  let tcp =
    protocol.new("tcp")
    |> protocol.with_tag("transport")
    |> protocol.with_decoder(tcp_decode)
    |> protocol.with_encoder(tcp_encode)

  let tls_decode: stage.Stage(Data, Data) =
    stage.new("tls_decode", fn(data) { Ok(data) })
  let tls_encode: stage.Stage(Data, Data) =
    stage.new("tls_encode", fn(data) { Ok(data) })

  let tls =
    protocol.new("tls")
    |> protocol.with_tag("session")
    |> protocol.requires("tcp")
    |> protocol.must_come_after("tcp")
    |> protocol.with_decoder(tls_decode)
    |> protocol.with_encoder(tls_encode)

  let http_decode: stage.Stage(Data, Data) =
    stage.new("http_decode", fn(data) { Ok(data) })
  let http_encode: stage.Stage(Data, Data) =
    stage.new("http_encode", fn(data) { Ok(data) })

  let http =
    protocol.new("http")
    |> protocol.with_tag("application")
    |> protocol.with_decoder(http_decode)
    |> protocol.with_encoder(http_encode)

  registry.new()
  |> registry.register(tcp)
  |> registry.register(tls)
  |> registry.register(http)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decoder Pipeline Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_decoder_pipeline_simple_test() {
  let reg = create_test_registry()

  pipeline_builder.build_decoder_pipeline(reg, ["tcp", "http"])
  |> result.is_ok()
  |> should.be_true()
}

pub fn build_decoder_pipeline_with_ordering_test() {
  let reg = create_test_registry()

  // Valid order: TCP -> TLS -> HTTP
  pipeline_builder.build_decoder_pipeline(reg, ["tcp", "tls", "http"])
  |> result.is_ok()
  |> should.be_true()
}

pub fn build_decoder_pipeline_single_protocol_test() {
  let reg = create_test_registry()

  pipeline_builder.build_decoder_pipeline(reg, ["tcp"])
  |> result.is_ok()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encoder Pipeline Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_encoder_pipeline_simple_test() {
  let reg = create_test_registry()

  pipeline_builder.build_encoder_pipeline(reg, ["tcp", "http"])
  |> result.is_ok()
  |> should.be_true()
}

pub fn build_encoder_pipeline_with_ordering_test() {
  let reg = create_test_registry()

  // Valid order for encoder: HTTP -> TLS -> TCP (reverse of decoder)
  pipeline_builder.build_encoder_pipeline(reg, ["tcp", "tls", "http"])
  |> result.is_ok()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Pipeline with Direction Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_pipeline_decode_direction_test() {
  let reg = create_test_registry()

  pipeline_builder.build_pipeline(reg, ["tcp", "http"], pipeline_builder.Decode)
  |> result.is_ok()
  |> should.be_true()
}

pub fn build_pipeline_encode_direction_test() {
  let reg = create_test_registry()

  pipeline_builder.build_pipeline(reg, ["tcp", "http"], pipeline_builder.Encode)
  |> result.is_ok()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Roundtrip Pipeline Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_roundtrip_pipeline_test() {
  let reg = create_test_registry()

  pipeline_builder.build_roundtrip_pipeline(reg, ["tcp", "http"])
  |> result.is_ok()
  |> should.be_true()
}

pub fn build_roundtrip_pipeline_complex_test() {
  let reg = create_test_registry()

  pipeline_builder.build_roundtrip_pipeline(reg, ["tcp", "tls", "http"])
  |> result.is_ok()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Validation Error Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_decoder_pipeline_validation_error_test() {
  let reg = create_test_registry()

  // TLS before TCP is invalid
  let result = pipeline_builder.build_decoder_pipeline(reg, ["tls", "tcp"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(pipeline_builder.ValidationFailed(_)) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn build_decoder_pipeline_missing_dependency_test() {
  let reg = create_test_registry()

  // TLS requires TCP, but TCP is not in the list
  let result = pipeline_builder.build_decoder_pipeline(reg, ["tls", "http"])

  result.is_error(result)
  |> should.be_true()
}

pub fn build_decoder_pipeline_unknown_protocol_test() {
  let reg = create_test_registry()

  let result = pipeline_builder.build_decoder_pipeline(reg, ["tcp", "unknown"])

  result.is_error(result)
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Empty Protocol List Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_decoder_pipeline_empty_list_test() {
  let reg = create_test_registry()

  let result = pipeline_builder.build_decoder_pipeline(reg, [])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(pipeline_builder.EmptyProtocolList) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn build_encoder_pipeline_empty_list_test() {
  let reg = create_test_registry()

  let result = pipeline_builder.build_encoder_pipeline(reg, [])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(pipeline_builder.EmptyProtocolList) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn build_roundtrip_pipeline_empty_list_test() {
  let reg = create_test_registry()

  let result = pipeline_builder.build_roundtrip_pipeline(reg, [])

  result.is_error(result)
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Missing Decoder/Encoder Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_decoder_pipeline_missing_decoder_test() {
  // Create a protocol without decoder
  let no_decoder_proto = protocol.new("no_decoder")

  let reg =
    registry.new()
    |> registry.register(no_decoder_proto)

  let result = pipeline_builder.build_decoder_pipeline(reg, ["no_decoder"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(pipeline_builder.MissingDecoder("no_decoder")) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn build_encoder_pipeline_missing_encoder_test() {
  // Create a protocol without encoder
  let no_encoder_proto = protocol.new("no_encoder")

  let reg =
    registry.new()
    |> registry.register(no_encoder_proto)

  let result = pipeline_builder.build_encoder_pipeline(reg, ["no_encoder"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(pipeline_builder.MissingEncoder("no_encoder")) -> should.be_true(True)
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Get Stages Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_stages_decode_test() {
  let reg = create_test_registry()

  pipeline_builder.get_stages(reg, ["tcp", "http"], pipeline_builder.Decode)
  |> result.is_ok()
  |> should.be_true()
}

pub fn get_stages_encode_test() {
  let reg = create_test_registry()

  pipeline_builder.get_stages(reg, ["tcp", "http"], pipeline_builder.Encode)
  |> result.is_ok()
  |> should.be_true()
}

pub fn get_stages_empty_list_test() {
  let reg = create_test_registry()

  let result = pipeline_builder.get_stages(reg, [], pipeline_builder.Decode)

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(pipeline_builder.EmptyProtocolList) -> should.be_true(True)
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Can Build Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn can_build_valid_pipeline_test() {
  let reg = create_test_registry()

  pipeline_builder.can_build(reg, ["tcp", "http"], pipeline_builder.Decode)
  |> should.be_true()
}

pub fn can_build_invalid_pipeline_test() {
  let reg = create_test_registry()

  // Invalid order
  pipeline_builder.can_build(reg, ["tls", "tcp"], pipeline_builder.Decode)
  |> should.be_false()
}

pub fn can_build_empty_list_test() {
  let reg = create_test_registry()

  pipeline_builder.can_build(reg, [], pipeline_builder.Decode)
  |> should.be_false()
}

pub fn can_build_missing_decoder_test() {
  let no_decoder_proto = protocol.new("no_decoder")

  let reg =
    registry.new()
    |> registry.register(no_decoder_proto)

  pipeline_builder.can_build(reg, ["no_decoder"], pipeline_builder.Decode)
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_to_string_validation_failed_test() {
  let error = pipeline_builder.ValidationFailed([])
  let str = pipeline_builder.error_to_string(error)

  str
  |> fn(s) { s != "" }
  |> should.be_true()
}

pub fn error_to_string_missing_decoder_test() {
  let error = pipeline_builder.MissingDecoder("tcp")
  let str = pipeline_builder.error_to_string(error)

  str
  |> fn(s) { s != "" }
  |> should.be_true()
}

pub fn error_to_string_missing_encoder_test() {
  let error = pipeline_builder.MissingEncoder("tcp")
  let str = pipeline_builder.error_to_string(error)

  str
  |> fn(s) { s != "" }
  |> should.be_true()
}

pub fn error_to_string_empty_protocol_list_test() {
  let error = pipeline_builder.EmptyProtocolList
  let str = pipeline_builder.error_to_string(error)

  str
  |> fn(s) { s != "" }
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Execution Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn decoder_pipeline_executes_test() {
  let reg = create_test_registry()

  case pipeline_builder.build_decoder_pipeline(reg, ["tcp", "http"]) {
    Ok(pipe) -> {
      // Create test data
      let test_data = message.empty()

      // Execute the pipeline
      case pipeline.execute(pipe, test_data) {
        Ok(_) -> should.be_true(True)
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn encoder_pipeline_executes_test() {
  let reg = create_test_registry()

  case pipeline_builder.build_encoder_pipeline(reg, ["tcp", "http"]) {
    Ok(pipe) -> {
      let test_data = message.empty()

      case pipeline.execute(pipe, test_data) {
        Ok(_) -> should.be_true(True)
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn roundtrip_pipeline_executes_test() {
  let reg = create_test_registry()

  case pipeline_builder.build_roundtrip_pipeline(reg, ["tcp", "http"]) {
    Ok(pipe) -> {
      let test_data = message.empty()

      case pipeline.execute(pipe, test_data) {
        Ok(_) -> should.be_true(True)
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}
