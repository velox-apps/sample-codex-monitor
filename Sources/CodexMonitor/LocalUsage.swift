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
    updatedAt: Int64(now.timeIntervalSince1970),
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
  var lastActivityTime: Int64?
  var sessionActive = false
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

  var sessionCwd: String?
  var currentModel: String?
  let activityGapMs: Int64 = 2 * 60 * 1000 // 2 minutes

  for line in content.split(separator: "\n") {
    guard !line.isEmpty else { continue }
    guard let lineData = line.data(using: .utf8) else { continue }
    guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

    let type = json["type"] as? String ?? ""
    let timestampMs = (json["timestamp_ms"] as? Int64) ?? (json["timestamp"] as? Int64).map { $0 * 1000 } ?? 0

    switch type {
    case "session_meta":
      sessionCwd = json["cwd"] as? String

    case "turn_context":
      if let model = json["model"] as? String {
        currentModel = model
      }
      // Track agent run start
      if let workspace = workspacePath, let cwd = sessionCwd, !cwd.hasPrefix(workspace) {
        continue
      }
      if !accumulator.sessionActive {
        accumulator.sessionActive = true
        accumulator.agentRuns += 1
      }
      accumulator.lastActivityTime = timestampMs

    case "event_msg":
      guard let payload = json["payload"] as? [String: Any] else { continue }
      if let tokenCount = payload["token_count"] as? [String: Any] {
        if let workspace = workspacePath, let cwd = sessionCwd, !cwd.hasPrefix(workspace) {
          continue
        }
        let input = (tokenCount["input_tokens"] as? Int64) ?? 0
        let cached = (tokenCount["cache_read_input_tokens"] as? Int64)
          ?? (tokenCount["cached_input_tokens"] as? Int64)
          ?? 0
        let output = (tokenCount["output_tokens"] as? Int64) ?? 0

        accumulator.inputTokens += input
        accumulator.cachedInputTokens += cached
        accumulator.outputTokens += output

        if let model = currentModel {
          modelTokens[model, default: 0] += input + cached + output
        }

        // Track activity time
        if let lastTime = accumulator.lastActivityTime {
          let gap = timestampMs - lastTime
          if gap > 0 && gap < activityGapMs {
            accumulator.agentTimeMs += gap
          }
        }
        accumulator.lastActivityTime = timestampMs
      }

    default:
      break
    }
  }
}
