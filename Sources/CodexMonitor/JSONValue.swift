import Foundation

public enum JSONValue: Codable, Sendable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }

  public var objectValue: [String: JSONValue]? {
    if case .object(let value) = self {
      return value
    }
    return nil
  }

  public var arrayValue: [JSONValue]? {
    if case .array(let value) = self {
      return value
    }
    return nil
  }

  public var stringValue: String? {
    if case .string(let value) = self {
      return value
    }
    return nil
  }

  public var boolValue: Bool? {
    if case .bool(let value) = self {
      return value
    }
    return nil
  }

  public var doubleValue: Double? {
    if case .number(let value) = self {
      return value
    }
    return nil
  }

  public var isNull: Bool {
    if case .null = self {
      return true
    }
    return false
  }

  public subscript(key: String) -> JSONValue? {
    objectValue?[key]
  }

  public func asUInt64() -> UInt64? {
    guard let value = doubleValue, value >= 0 else {
      return nil
    }
    return UInt64(value)
  }

}
