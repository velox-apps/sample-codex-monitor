import Foundation

// MARK: - Local Usage Snapshot

struct LocalUsageSnapshotArgs: Codable, Sendable {
  let days: Int
  let workspacePath: String?
}

/// Scans CODEX_HOME/sessions/YYYY/MM/DD/*.jsonl and aggregates token usage.
func localUsageSnapshot(days: Int, workspacePath: String?, state: AppState) throws -> LocalUsageSnapshot {
  let codexHome = resolveDefaultCodexHome() ?? "~/.codex"
  let sessionsDir = (codexHome as NSString).appendingPathComponent("sessions")
  let now = Date()
  let calendar = Calendar.current

  // Determine date range
  let endDate = now
  guard calendar.date(byAdding: .day, value: -(days - 1), to: endDate) != nil else {
    throw CodexError(message: "invalid date range")
  }

  let dateFormatter = DateFormatter()
  dateFormatter.dateFormat = "yyyy-MM-dd"

  // Collect per-day data
  var dailyData: [String: DayAccumulator] = [:]
  var modelTokens: [String: Int64] = [:]

  // Walk the sessions directory structure: sessions/YYYY/MM/DD/*.jsonl
  for dayOffset in 0..<days {
    guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: endDate) else { continue }
    let year = calendar.component(.year, from: date)
    let month = calendar.component(.month, from: date)
    let day = calendar.component(.day, from: date)

    let dayDir = String(format: "%@/%04d/%02d/%02d", sessionsDir, year, month, day)
    guard FileManager.default.fileExists(atPath: dayDir) else { continue }
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: dayDir) else { continue }

    let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
    var acc = dailyData[dayKey] ?? DayAccumulator()

    for file in files {
      guard file.hasSuffix(".jsonl") else { continue }
      let filePath = (dayDir as NSString).appendingPathComponent(file)
      try processSessionFile(
        path: filePath,
        workspacePath: workspacePath,
        accumulator: &acc,
        modelTokens: &modelTokens
      )
    }

    dailyData[dayKey] = acc
  }

  // Build sorted days list
  var daysList: [LocalUsageDay] = []
  for dayOffset in stride(from: days - 1, through: 0, by: -1) {
    guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: endDate) else { continue }
    let year = calendar.component(.year, from: date)
    let month = calendar.component(.month, from: date)
    let day = calendar.component(.day, from: date)
    let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
    let acc = dailyData[dayKey] ?? DayAccumulator()
    daysList.append(LocalUsageDay(
      day: dayKey,
      inputTokens: acc.inputTokens,
      cachedInputTokens: acc.cachedInputTokens,
      outputTokens: acc.outputTokens,
      totalTokens: acc.inputTokens + acc.cachedInputTokens + acc.outputTokens,
      agentTimeMs: acc.agentTimeMs,
      agentRuns: acc.agentRuns
    ))
  }

  // Calculate totals
  let last7 = daysList.suffix(min(7, daysList.count))
  let last30 = daysList.suffix(min(30, daysList.count))
  let last7Tokens = last7.reduce(Int64(0)) { $0 + $1.totalTokens }
  let last30Tokens = last30.reduce(Int64(0)) { $0 + $1.totalTokens }
  let activeDays = daysList.filter { $0.totalTokens > 0 }.count
  let averageDaily = activeDays > 0 ? last30Tokens / Int64(activeDays) : 0

  let totalCached = daysList.reduce(Int64(0)) { $0 + $1.cachedInputTokens }
  let totalInput = daysList.reduce(Int64(0)) { $0 + $1.inputTokens + $1.cachedInputTokens }
  let cacheHitRate = totalInput > 0 ? Double(totalCached) / Double(totalInput) * 100.0 : 0.0

  var peakDay: String?
  var peakDayTokens: Int64 = 0
  for day in daysList {
    if day.totalTokens > peakDayTokens {
      peakDayTokens = day.totalTokens
      peakDay = day.day
    }
  }

  let totals = LocalUsageTotals(
    last7DaysTokens: last7Tokens,
    last30DaysTokens: last30Tokens,
    averageDailyTokens: averageDaily,
    cacheHitRatePercent: cacheHitRate,
    peakDay: peakDay,
    peakDayTokens: peakDayTokens
  )

  // Build top models
  let totalAllTokens = modelTokens.values.reduce(Int64(0), +)
  var topModels = modelTokens.map { (model, tokens) in
    LocalUsageModel(
      model: model,
      tokens: tokens,
      sharePercent: totalAllTokens > 0 ? Double(tokens) / Double(totalAllTokens) * 100.0 : 0.0
    )
  }
  topModels.sort { $0.tokens > $1.tokens }
  if topModels.count > 10 {
    topModels = Array(topModels.prefix(10))
  }

  return LocalUsageSnapshot(
    updatedAt: Int64(now.timeIntervalSince1970 * 1000),
    days: daysList,
    totals: totals,
    topModels: topModels
  )
}

// MARK: - Private Types

private struct DayAccumulator {
  var inputTokens: Int64 = 0
  var cachedInputTokens: Int64 = 0
  var outputTokens: Int64 = 0
  var agentTimeMs: Int64 = 0
  var agentRuns: Int64 = 0
}

private struct UsageTotals {
  var input: Int64 = 0
  var cached: Int64 = 0
  var output: Int64 = 0
}

private let maxActivityGapMs: Int64 = 2 * 60 * 1000 // 2 minutes

// MARK: - Timestamp Parsing

/// Parses the "timestamp" field which may be an ISO 8601 string or a numeric value.
/// Returns milliseconds since epoch, or nil.
private func readTimestampMs(from json: [String: Any]) -> Int64? {
  guard let raw = json["timestamp"] else { return nil }
  if let text = raw as? String {
    // ISO 8601: "2026-02-07T15:14:20.796Z"
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) {
      return Int64(date.timeIntervalSince1970 * 1000)
    }
    // Try without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: text) {
      return Int64(date.timeIntervalSince1970 * 1000)
    }
    return nil
  }
  // Numeric timestamp
  let numeric: Int64
  if let i = raw as? Int64 {
    numeric = i
  } else if let i = raw as? Int {
    numeric = Int64(i)
  } else if let d = raw as? Double {
    numeric = Int64(d)
  } else {
    return nil
  }
  // Heuristic: if < 1 trillion, it's seconds — convert to ms
  if numeric > 0 && numeric < 1_000_000_000_000 {
    return numeric * 1000
  }
  return numeric
}

/// Derives a day key (YYYY-MM-DD in local timezone) from a timestamp in ms.
private func dayKeyForTimestampMs(_ ms: Int64) -> String? {
  let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
  let calendar = Calendar.current
  let y = calendar.component(.year, from: date)
  let m = calendar.component(.month, from: date)
  let d = calendar.component(.day, from: date)
  return String(format: "%04d-%02d-%02d", y, m, d)
}

// MARK: - Field Extraction Helpers

/// Reads cwd from payload for session_meta and turn_context events.
private func extractCwd(from json: [String: Any]) -> String? {
  (json["payload"] as? [String: Any])?["cwd"] as? String
}

/// Reads model from turn_context payload.
private func extractModelFromTurnContext(_ json: [String: Any]) -> String? {
  guard let payload = json["payload"] as? [String: Any] else { return nil }
  if let model = payload["model"] as? String { return model }
  if let info = payload["info"] as? [String: Any],
     let model = info["model"] as? String { return model }
  return nil
}

/// Reads model from token_count event payload.
private func extractModelFromTokenCount(_ json: [String: Any]) -> String? {
  guard let payload = json["payload"] as? [String: Any] else { return nil }
  if let info = payload["info"] as? [String: Any] {
    if let m = info["model"] as? String { return m }
    if let m = info["model_name"] as? String { return m }
  }
  if let m = payload["model"] as? String { return m }
  if let m = json["model"] as? String { return m }
  return nil
}

/// Finds a usage map (total_token_usage or last_token_usage) inside info.
private func findUsageMap(
  _ info: [String: Any],
  keys: [String]
) -> [String: Any]? {
  for key in keys {
    if let map = info[key] as? [String: Any] { return map }
  }
  return nil
}

/// Reads an Int64 from a map, trying multiple keys.
private func readI64(_ map: [String: Any], keys: [String]) -> Int64 {
  for key in keys {
    if let val = map[key] {
      if let i = val as? Int64 { return i }
      if let i = val as? Int { return Int64(i) }
      if let d = val as? Double { return Int64(d) }
    }
  }
  return 0
}

// MARK: - Activity Tracking

private func trackActivity(
  daily: inout [String: DayAccumulator],
  lastActivityMs: inout Int64?,
  timestampMs: Int64
) {
  if let prevMs = lastActivityMs {
    let delta = timestampMs - prevMs
    if delta > 0 && delta <= maxActivityGapMs {
      if let dayKey = dayKeyForTimestampMs(timestampMs) {
        daily[dayKey, default: DayAccumulator()].agentTimeMs += delta
      }
    }
  }
  lastActivityMs = timestampMs
}

// MARK: - JSONL Processing

private func processSessionFile(
  path: String,
  workspacePath: String?,
  accumulator: inout DayAccumulator,
  modelTokens: inout [String: Int64]
) throws {
  guard let data = FileManager.default.contents(atPath: path) else { return }
  guard let content = String(data: data, encoding: .utf8) else { return }

  // Per-file state matching Rust's scan_file
  var previousTotals: UsageTotals?
  var currentModel: String?
  var lastActivityMs: Int64?
  var seenRuns = Set<Int64>()
  var matchKnown = (workspacePath == nil)
  var matchesWorkspace = (workspacePath == nil)

  // We accumulate into a local DayAccumulator keyed by day, then merge into `accumulator` at the end.
  // But the caller already passes a per-day accumulator. For multi-day files, we need daily tracking.
  // Use a dict for activity tracking across days.
  var daily: [String: DayAccumulator] = [:]

  for line in content.split(separator: "\n") {
    guard !line.isEmpty else { continue }
    // Skip very large lines
    if line.count > 512_000 { continue }
    guard let lineData = line.data(using: .utf8) else { continue }
    guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

    let entryType = json["type"] as? String ?? ""

    // Extract cwd from session_meta and turn_context
    if entryType == "session_meta" || entryType == "turn_context" {
      if let cwd = extractCwd(from: json) {
        if let filter = workspacePath {
          let cwdPath = cwd as NSString
          matchesWorkspace = cwd == filter || cwdPath.hasPrefix(filter)
          matchKnown = true
          if !matchesWorkspace { break }
        }
      }
    }

    if entryType == "turn_context" {
      if let model = extractModelFromTurnContext(json) {
        currentModel = model
      }
      continue
    }

    if entryType == "session_meta" {
      continue
    }

    if !matchesWorkspace {
      if matchKnown { break }
      continue
    }
    if !matchKnown { continue }

    // Handle event_msg
    if entryType == "event_msg" || entryType.isEmpty {
      guard let payload = json["payload"] as? [String: Any] else { continue }
      let payloadType = payload["type"] as? String

      // agent_message → count as agent run
      if payloadType == "agent_message" {
        if let timestampMs = readTimestampMs(from: json) {
          if seenRuns.insert(timestampMs).inserted {
            if let dayKey = dayKeyForTimestampMs(timestampMs) {
              daily[dayKey, default: DayAccumulator()].agentRuns += 1
            }
          }
          trackActivity(daily: &daily, lastActivityMs: &lastActivityMs, timestampMs: timestampMs)
        }
        continue
      }

      // agent_reasoning → track activity only
      if payloadType == "agent_reasoning" {
        if let timestampMs = readTimestampMs(from: json) {
          trackActivity(daily: &daily, lastActivityMs: &lastActivityMs, timestampMs: timestampMs)
        }
        continue
      }

      // token_count → extract usage data
      guard payloadType == "token_count" else { continue }

      guard let info = payload["info"] as? [String: Any] else { continue }

      let input: Int64
      let cached: Int64
      let output: Int64
      let usedTotal: Bool

      if let total = findUsageMap(info, keys: ["total_token_usage", "totalTokenUsage"]) {
        input = readI64(total, keys: ["input_tokens", "inputTokens"])
        cached = readI64(total, keys: [
          "cached_input_tokens", "cache_read_input_tokens",
          "cachedInputTokens", "cacheReadInputTokens"
        ])
        output = readI64(total, keys: ["output_tokens", "outputTokens"])
        usedTotal = true
      } else if let last = findUsageMap(info, keys: ["last_token_usage", "lastTokenUsage"]) {
        input = readI64(last, keys: ["input_tokens", "inputTokens"])
        cached = readI64(last, keys: [
          "cached_input_tokens", "cache_read_input_tokens",
          "cachedInputTokens", "cacheReadInputTokens"
        ])
        output = readI64(last, keys: ["output_tokens", "outputTokens"])
        usedTotal = false
      } else {
        continue
      }

      // Compute delta, handling total_token_usage vs last_token_usage
      var deltaInput: Int64
      var deltaCached: Int64
      var deltaOutput: Int64

      if usedTotal {
        let prev = previousTotals ?? UsageTotals()
        deltaInput = max(input - prev.input, 0)
        deltaCached = max(cached - prev.cached, 0)
        deltaOutput = max(output - prev.output, 0)
        previousTotals = UsageTotals(input: input, cached: cached, output: output)
      } else {
        deltaInput = input
        deltaCached = cached
        deltaOutput = output
        // Track cumulative for when next total_token_usage arrives
        var next = previousTotals ?? UsageTotals()
        next.input += deltaInput
        next.cached += deltaCached
        next.output += deltaOutput
        previousTotals = next
      }

      if deltaInput == 0 && deltaCached == 0 && deltaOutput == 0 { continue }

      if let timestampMs = readTimestampMs(from: json),
         let dayKey = dayKeyForTimestampMs(timestampMs) {
        // Cap cached to not exceed input
        let cappedCached = min(deltaCached, deltaInput)
        daily[dayKey, default: DayAccumulator()].inputTokens += deltaInput
        daily[dayKey, default: DayAccumulator()].cachedInputTokens += cappedCached
        daily[dayKey, default: DayAccumulator()].outputTokens += deltaOutput

        let model = currentModel
          ?? extractModelFromTokenCount(json)
          ?? "unknown"
        if model != "unknown" {
          modelTokens[model, default: 0] += deltaInput + deltaOutput
        }

        trackActivity(daily: &daily, lastActivityMs: &lastActivityMs, timestampMs: timestampMs)
      }
      continue
    }

    // Handle response_item
    if entryType == "response_item" {
      guard let payload = json["payload"] as? [String: Any] else { continue }
      let role = payload["role"] as? String ?? ""
      let payloadType = payload["type"] as? String

      if role == "assistant" {
        if let timestampMs = readTimestampMs(from: json) {
          if seenRuns.insert(timestampMs).inserted {
            if let dayKey = dayKeyForTimestampMs(timestampMs) {
              daily[dayKey, default: DayAccumulator()].agentRuns += 1
            }
          }
          trackActivity(daily: &daily, lastActivityMs: &lastActivityMs, timestampMs: timestampMs)
        }
      } else if payloadType != "message" {
        if let timestampMs = readTimestampMs(from: json) {
          trackActivity(daily: &daily, lastActivityMs: &lastActivityMs, timestampMs: timestampMs)
        }
      }
    }
  }

  // Merge daily data back into the caller's accumulator.
  // The caller passes a single accumulator for one day key, but we may have parsed events
  // spanning multiple days. Merge everything — the outer function filters by day key anyway.
  for (_, dayAcc) in daily {
    accumulator.inputTokens += dayAcc.inputTokens
    accumulator.cachedInputTokens += dayAcc.cachedInputTokens
    accumulator.outputTokens += dayAcc.outputTokens
    accumulator.agentTimeMs += dayAcc.agentTimeMs
    accumulator.agentRuns += dayAcc.agentRuns
  }
}
