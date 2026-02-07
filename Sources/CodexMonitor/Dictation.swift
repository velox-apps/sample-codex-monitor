import Foundation
import AVFoundation
import VeloxRuntime
import VeloxRuntimeWry
import VoxtralC

// MARK: - Dictation Manager

final class DictationManager: @unchecked Sendable {
  // Model state
  var modelStatus: String = "missing"  // "missing" | "downloading" | "ready" | "error"
  var modelError: String?
  var modelPath: String?
  var downloadTask: Task<Void, Never>?
  var downloadCancelled: Bool = false
  var downloadedBytes: UInt64 = 0
  var totalBytes: UInt64? = nil

  // Session state
  var sessionState: String = "idle"  // "idle" | "listening" | "processing"
  var audioEngine: AVAudioEngine?
  var capturedSamples: [Float] = []
  var processingTask: Task<Void, Never>?
  var processingCancelled: Bool = false

  // Cached VoxtralFoundation context (reused across sessions)
  var cachedContext: UnsafeMutablePointer<vox_ctx_t>?

  // Audio level monitoring
  var levelTimer: DispatchSourceTimer?
  var currentLevel: Float = 0

  // Base directory for model storage: <AppSupport>/<identifier>/models/voxtral/
  let modelDir: URL

  init(baseDir: URL) {
    self.modelDir = baseDir.appendingPathComponent("models").appendingPathComponent("voxtral")
  }

  deinit {
    levelTimer?.cancel()
    levelTimer = nil
    if let ctx = cachedContext {
      vox_free(ctx)
    }
  }
}

// MARK: - Event Payloads

struct DictationDownloadEvent: Codable, Sendable {
  let state: String
  let modelId: String
  let progress: DictationDownloadProgress?
  let error: String?
  let path: String?
}

struct DictationDownloadProgress: Codable, Sendable {
  let downloadedBytes: UInt64
  let totalBytes: UInt64?
}

struct DictationSessionEvent: Codable, Sendable {
  let type: String     // "state" | "level" | "transcript" | "canceled"
  let state: String?
  let level: Float?
  let text: String?
}

// MARK: - Model File Constants

private let kModelFiles = ["consolidated.safetensors", "tekken.json"]
private let kBaseURL = "https://huggingface.co/mistralai/Voxtral-Mini-3B-2507/resolve/main/"
private let kEstimatedTotalBytes: UInt64 = 8_915_000_000  // ~8.9GB combined
private let kMaxRecordingSeconds: Double = 120
private let kSampleRate: Double = 16000
private let kMaxSamples = Int(kMaxRecordingSeconds * kSampleRate)

// MARK: - Model Status

func dictationModelStatus(modelId: String?, state: AppState) -> DictationModelStatusResponse {
  let resolvedId = "voxtral"
  let dm = state.getDictation()

  // Check filesystem for model files
  let dir = dm.modelDir.path
  let allExist = kModelFiles.allSatisfy { file in
    FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(file))
  }

  if allExist {
    state.withDictation { $0.modelStatus = "ready"; $0.modelPath = dir; $0.modelError = nil }
    return DictationModelStatusResponse(
      state: "ready", modelId: resolvedId, progress: nil, error: nil, path: dir
    )
  }

  let status = dm.modelStatus
  let error = dm.modelError
  let progress: JSONValue? = (status == "downloading") ? .object([
    "downloadedBytes": .number(Double(dm.downloadedBytes)),
    "totalBytes": .number(Double(dm.totalBytes ?? kEstimatedTotalBytes))
  ]) : nil

  return DictationModelStatusResponse(
    state: status, modelId: resolvedId, progress: progress, error: error, path: dm.modelPath
  )
}

// MARK: - Download Model

func dictationDownloadModel(
  modelId: String?,
  state: AppState,
  eventManager: VeloxEventManager
) -> DictationModelStatusResponse {
  let resolvedId = "voxtral"
  let dm = state.getDictation()

  // Already downloading or ready?
  if dm.modelStatus == "downloading" || dm.modelStatus == "ready" {
    return dictationModelStatus(modelId: modelId, state: state)
  }

  state.withDictation {
    $0.modelStatus = "downloading"
    $0.modelError = nil
    $0.downloadedBytes = 0
    $0.totalBytes = kEstimatedTotalBytes
    $0.downloadCancelled = false
  }

  let task = Task {
    await performDownload(state: state, eventManager: eventManager)
  }
  state.withDictation { $0.downloadTask = task }

  return DictationModelStatusResponse(
    state: "downloading", modelId: resolvedId,
    progress: .object([
      "downloadedBytes": .number(0),
      "totalBytes": .number(Double(kEstimatedTotalBytes))
    ]),
    error: nil, path: nil
  )
}

// MARK: - Cancel Download

func dictationCancelDownload(
  modelId: String?,
  state: AppState,
  eventManager: VeloxEventManager
) -> DictationModelStatusResponse {
  let resolvedId = "voxtral"

  state.withDictation {
    $0.downloadCancelled = true
    $0.downloadTask?.cancel()
    $0.downloadTask = nil
    $0.modelStatus = "missing"
    $0.modelError = nil
    $0.downloadedBytes = 0
    $0.totalBytes = nil
  }

  // Clean up partial files
  let dm = state.getDictation()
  let dir = dm.modelDir.path
  for file in kModelFiles {
    let partial = (dir as NSString).appendingPathComponent(file + ".partial")
    try? FileManager.default.removeItem(atPath: partial)
  }

  emitDownloadEvent(state: "missing", modelId: resolvedId, eventManager: eventManager)

  return DictationModelStatusResponse(
    state: "missing", modelId: resolvedId, progress: nil, error: nil, path: nil
  )
}

// MARK: - Remove Model

func dictationRemoveModel(
  modelId: String?,
  state: AppState,
  eventManager: VeloxEventManager
) -> DictationModelStatusResponse {
  let resolvedId = "voxtral"

  state.withDictation { dm in
    // Free cached context
    if let ctx = dm.cachedContext {
      vox_free(ctx)
      dm.cachedContext = nil
    }
    dm.modelStatus = "missing"
    dm.modelError = nil
    dm.modelPath = nil
  }

  // Delete model directory
  let dm = state.getDictation()
  try? FileManager.default.removeItem(at: dm.modelDir)

  emitDownloadEvent(state: "missing", modelId: resolvedId, eventManager: eventManager)

  return DictationModelStatusResponse(
    state: "missing", modelId: resolvedId, progress: nil, error: nil, path: nil
  )
}

// MARK: - Start Dictation

func dictationStart(
  preferredLanguage: String?,
  state: AppState,
  eventManager: VeloxEventManager
) throws {
  let dm = state.getDictation()

  guard dm.modelStatus == "ready" else {
    throw CodexError(message: "Model not ready (status: \(dm.modelStatus))")
  }
  guard dm.sessionState == "idle" else {
    throw CodexError(message: "Dictation already active (state: \(dm.sessionState))")
  }

  state.withDictation {
    $0.sessionState = "listening"
    $0.capturedSamples = []
    $0.currentLevel = 0
  }

  // Set up AVAudioEngine
  let engine = AVAudioEngine()
  let inputNode = engine.inputNode
  let nativeFormat = inputNode.outputFormat(forBus: 0)

  // Target format: 16kHz mono float32
  guard let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: kSampleRate,
    channels: 1,
    interleaved: false
  ) else {
    state.withDictation { $0.sessionState = "idle" }
    throw CodexError(message: "Failed to create target audio format")
  }

  let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
  guard let converter else {
    state.withDictation { $0.sessionState = "idle" }
    throw CodexError(message: "Failed to create audio converter")
  }

  // Install tap on input node
  let bufferSize: AVAudioFrameCount = 4096
  inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { [weak converter] buffer, _ in
    guard let converter else { return }

    // Estimate output frame count after sample rate conversion
    let ratio = kSampleRate / nativeFormat.sampleRate
    let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else {
      return
    }

    var error: NSError?
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }
    converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

    if error != nil { return }

    guard let channelData = convertedBuffer.floatChannelData else { return }
    let frameCount = Int(convertedBuffer.frameLength)
    if frameCount == 0 { return }

    // Compute RMS level
    let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)
    var sumSq: Float = 0
    for s in samples { sumSq += s * s }
    let rms = sqrtf(sumSq / Float(frameCount))

    // Accumulate samples & update level (no lock on RT thread — atomic-like write)
    state.withDictation { dm in
      let remaining = kMaxSamples - dm.capturedSamples.count
      if remaining > 0 {
        let toAppend = min(frameCount, remaining)
        dm.capturedSamples.append(contentsOf: samples.prefix(toAppend))
      }
      dm.currentLevel = rms
    }
  }

  do {
    try engine.start()
  } catch {
    inputNode.removeTap(onBus: 0)
    state.withDictation { $0.sessionState = "idle" }
    throw CodexError(message: "Failed to start audio engine: \(error.localizedDescription)")
  }

  state.withDictation { $0.audioEngine = engine }

  // Emit initial state event
  emitSessionEvent(type: "state", state: "listening", eventManager: eventManager)

  // Start level timer (33ms ≈ 30fps)
  let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
  timer.schedule(deadline: .now(), repeating: .milliseconds(33))
  timer.setEventHandler { [weak timer] in
    let dm = state.getDictation()
    let level = dm.currentLevel
    let sessionState = dm.sessionState

    guard sessionState == "listening" else {
      timer?.cancel()
      return
    }

    emitSessionEvent(type: "level", level: level, eventManager: eventManager)

    // Auto-stop at max duration
    if dm.capturedSamples.count >= kMaxSamples {
      timer?.cancel()
      dictationStop(state: state, eventManager: eventManager)
    }
  }
  timer.resume()
  state.withDictation { $0.levelTimer = timer }
}

// MARK: - Stop Dictation

func dictationStop(state: AppState, eventManager: VeloxEventManager) {
  let dm = state.getDictation()
  guard dm.sessionState == "listening" else { return }

  stopAudioCapture(state: state)
  state.withDictation {
    $0.sessionState = "processing"
    $0.processingCancelled = false
  }

  emitSessionEvent(type: "state", state: "processing", eventManager: eventManager)

  let task = Task {
    await performTranscription(state: state, eventManager: eventManager)
  }
  state.withDictation { $0.processingTask = task }
}

// MARK: - Cancel Dictation

func dictationCancel(state: AppState, eventManager: VeloxEventManager) {
  let dm = state.getDictation()

  switch dm.sessionState {
  case "listening":
    stopAudioCapture(state: state)
    state.withDictation {
      $0.sessionState = "idle"
      $0.capturedSamples = []
    }
    emitSessionEvent(type: "canceled", eventManager: eventManager)
    emitSessionEvent(type: "state", state: "idle", eventManager: eventManager)

  case "processing":
    state.withDictation {
      $0.processingCancelled = true
      $0.processingTask?.cancel()
      $0.processingTask = nil
      $0.sessionState = "idle"
      $0.capturedSamples = []
    }
    emitSessionEvent(type: "canceled", eventManager: eventManager)
    emitSessionEvent(type: "state", state: "idle", eventManager: eventManager)

  default:
    break
  }
}

// MARK: - Request Permission

func dictationRequestPermission() async -> Bool {
  await withCheckedContinuation { continuation in
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      continuation.resume(returning: granted)
    }
  }
}

// MARK: - Download Implementation

private func performDownload(state: AppState, eventManager: VeloxEventManager) async {
  let resolvedId = "voxtral"
  let dm = state.getDictation()
  let dir = dm.modelDir

  // Create model directory
  do {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  } catch {
    state.withDictation { $0.modelStatus = "error"; $0.modelError = error.localizedDescription }
    emitDownloadEvent(
      state: "error", modelId: resolvedId, error: error.localizedDescription,
      eventManager: eventManager
    )
    return
  }

  var cumulativeBytes: UInt64 = 0
  var lastEmitTime = Date.distantPast

  for filename in kModelFiles {
    let cancelled = state.getDictation().downloadCancelled
    if cancelled || Task.isCancelled { return }

    let urlString = kBaseURL + filename
    guard let url = URL(string: urlString) else {
      state.withDictation { $0.modelStatus = "error"; $0.modelError = "Invalid URL: \(urlString)" }
      emitDownloadEvent(
        state: "error", modelId: resolvedId, error: "Invalid URL: \(urlString)",
        eventManager: eventManager
      )
      return
    }

    let partialPath = dir.appendingPathComponent(filename + ".partial")
    let finalPath = dir.appendingPathComponent(filename)

    // Skip if already downloaded
    if FileManager.default.fileExists(atPath: finalPath.path) {
      if let attrs = try? FileManager.default.attributesOfItem(atPath: finalPath.path),
         let size = attrs[.size] as? UInt64 {
        cumulativeBytes += size
        state.withDictation { $0.downloadedBytes = cumulativeBytes }
      }
      continue
    }

    do {
      let (bytes, response) = try await URLSession.shared.bytes(from: url)

      // Update total bytes from content-length if available
      if let httpResp = response as? HTTPURLResponse,
         let contentLength = httpResp.value(forHTTPHeaderField: "Content-Length"),
         let cl = UInt64(contentLength) {
        // Adjust estimated total for this file
        _ = cl  // We keep using the estimated total for combined progress
      }

      guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw CodexError(message: "HTTP \(code) downloading \(filename)")
      }

      // Stream to partial file
      FileManager.default.createFile(atPath: partialPath.path, contents: nil)
      guard let fileHandle = try? FileHandle(forWritingTo: partialPath) else {
        throw CodexError(message: "Cannot open \(partialPath.path) for writing")
      }
      defer { try? fileHandle.close() }

      var chunkBuffer = Data()
      let flushThreshold = 256 * 1024  // 256KB chunks

      for try await byte in bytes {
        if state.getDictation().downloadCancelled || Task.isCancelled {
          try? fileHandle.close()
          try? FileManager.default.removeItem(at: partialPath)
          return
        }

        chunkBuffer.append(byte)

        if chunkBuffer.count >= flushThreshold {
          try fileHandle.write(contentsOf: chunkBuffer)
          cumulativeBytes += UInt64(chunkBuffer.count)
          chunkBuffer.removeAll(keepingCapacity: true)

          state.withDictation { $0.downloadedBytes = cumulativeBytes }

          // Throttle event emission to ~150ms
          let now = Date()
          if now.timeIntervalSince(lastEmitTime) >= 0.15 {
            lastEmitTime = now
            emitDownloadEvent(
              state: "downloading", modelId: resolvedId,
              progress: DictationDownloadProgress(
                downloadedBytes: cumulativeBytes,
                totalBytes: kEstimatedTotalBytes
              ),
              eventManager: eventManager
            )
          }
        }
      }

      // Flush remaining bytes
      if !chunkBuffer.isEmpty {
        try fileHandle.write(contentsOf: chunkBuffer)
        cumulativeBytes += UInt64(chunkBuffer.count)
        state.withDictation { $0.downloadedBytes = cumulativeBytes }
      }

      try? fileHandle.close()

      // Rename partial → final
      try FileManager.default.moveItem(at: partialPath, to: finalPath)

    } catch {
      try? FileManager.default.removeItem(at: partialPath)
      if state.getDictation().downloadCancelled || Task.isCancelled { return }

      state.withDictation {
        $0.modelStatus = "error"
        $0.modelError = "Download failed (\(filename)): \(error.localizedDescription)"
      }
      emitDownloadEvent(
        state: "error", modelId: resolvedId,
        error: "Download failed (\(filename)): \(error.localizedDescription)",
        eventManager: eventManager
      )
      return
    }
  }

  // All files downloaded successfully
  state.withDictation {
    $0.modelStatus = "ready"
    $0.modelPath = dir.path
    $0.modelError = nil
    $0.downloadTask = nil
  }

  emitDownloadEvent(
    state: "ready", modelId: resolvedId,
    progress: DictationDownloadProgress(
      downloadedBytes: cumulativeBytes,
      totalBytes: cumulativeBytes
    ),
    path: dir.path,
    eventManager: eventManager
  )
}

// MARK: - Transcription

private func performTranscription(state: AppState, eventManager: VeloxEventManager) async {
  let dm = state.getDictation()
  var samples = dm.capturedSamples
  let modelDir = dm.modelDir.path

  guard !samples.isEmpty else {
    state.withDictation { $0.sessionState = "idle"; $0.capturedSamples = [] }
    emitSessionEvent(type: "transcript", text: "", eventManager: eventManager)
    emitSessionEvent(type: "state", state: "idle", eventManager: eventManager)
    return
  }

  // Normalize: DC offset removal + gain
  let mean = samples.reduce(0, +) / Float(samples.count)
  for i in samples.indices { samples[i] -= mean }

  var maxAbs: Float = 0
  for s in samples { maxAbs = max(maxAbs, abs(s)) }
  if maxAbs > 0.01 {
    let gain = min(1.0 / maxAbs, 10.0)  // Cap gain at 10x
    for i in samples.indices { samples[i] *= gain }
  }

  // Load or reuse cached context
  var ctx: UnsafeMutablePointer<vox_ctx_t>?
  state.withDictation { dm in
    if dm.cachedContext != nil {
      ctx = dm.cachedContext
    }
  }

  if ctx == nil {
    ctx = vox_load(modelDir)
    guard ctx != nil else {
      state.withDictation {
        $0.sessionState = "idle"
        $0.capturedSamples = []
      }
      emitSessionEvent(type: "transcript", text: "", eventManager: eventManager)
      emitSessionEvent(type: "state", state: "idle", eventManager: eventManager)
      AppLogger.log("Dictation: vox_load failed for \(modelDir)", level: .error)
      return
    }
    state.withDictation { $0.cachedContext = ctx }
  }

  // Check cancellation
  if state.getDictation().processingCancelled || Task.isCancelled {
    state.withDictation { $0.sessionState = "idle"; $0.capturedSamples = [] }
    return
  }

  // Stream transcription: init → feed all → finish → collect tokens
  let stream = vox_stream_init(ctx)
  guard stream != nil else {
    state.withDictation { $0.sessionState = "idle"; $0.capturedSamples = [] }
    emitSessionEvent(type: "transcript", text: "", eventManager: eventManager)
    emitSessionEvent(type: "state", state: "idle", eventManager: eventManager)
    AppLogger.log("Dictation: vox_stream_init failed", level: .error)
    return
  }

  samples.withUnsafeBufferPointer { buf in
    let _ = vox_stream_feed(stream, buf.baseAddress, Int32(buf.count))
  }

  let _ = vox_stream_finish(stream)

  // Collect all tokens
  var transcript = ""
  var tokenBuf = [UnsafePointer<CChar>?](repeating: nil, count: 64)
  while true {
    let n = tokenBuf.withUnsafeMutableBufferPointer { buf in
      vox_stream_get(stream, buf.baseAddress, Int32(buf.count))
    }
    if n <= 0 { break }
    for i in 0..<Int(n) {
      if let ptr = tokenBuf[i] {
        transcript += String(cString: ptr)
      }
    }
  }

  vox_stream_free(stream)

  // Trim whitespace
  let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

  state.withDictation {
    $0.sessionState = "idle"
    $0.capturedSamples = []
    $0.processingTask = nil
  }

  emitSessionEvent(type: "transcript", text: trimmed, eventManager: eventManager)
  emitSessionEvent(type: "state", state: "idle", eventManager: eventManager)
}

// MARK: - Audio Capture Helpers

private func stopAudioCapture(state: AppState) {
  state.withDictation { dm in
    dm.levelTimer?.cancel()
    dm.levelTimer = nil

    if let engine = dm.audioEngine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      dm.audioEngine = nil
    }
  }
}

// MARK: - Event Emission Helpers

private func emitSessionEvent(
  type: String,
  state: String? = nil,
  level: Float? = nil,
  text: String? = nil,
  eventManager: VeloxEventManager
) {
  let event = DictationSessionEvent(type: type, state: state, level: level, text: text)
  try? eventManager.emit("dictation-event", payload: event)
}

private func emitDownloadEvent(
  state: String,
  modelId: String,
  progress: DictationDownloadProgress? = nil,
  error: String? = nil,
  path: String? = nil,
  eventManager: VeloxEventManager
) {
  let event = DictationDownloadEvent(
    state: state, modelId: modelId, progress: progress, error: error, path: path
  )
  try? eventManager.emit("dictation-download", payload: event)
}
