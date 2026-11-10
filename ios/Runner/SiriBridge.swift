import Flutter
import Foundation

/// Foreground-only bridge. Requests are never persisted or retried on launch.
@MainActor
final class SiriBridge {
  static let shared = SiriBridge()
  private var channel: FlutterMethodChannel?
  private var isReady = false
  private var isRunning = false

  func attach(to messenger: FlutterBinaryMessenger) {
    isReady = false
    let channel = FlutterMethodChannel(name: "wake_my_pc/siri", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "ready":
        self?.isReady = true
        result(nil)
      case "notReady":
        self?.isReady = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func run(
    action: String,
    confirm: ((String) async throws -> Void)? = nil
  ) async throws -> String {
    guard !isRunning else {
      throw SiriBridgeError("Another Siri request is in progress. Please wait for it to finish.")
    }
    isRunning = true
    defer { isRunning = false }

    // openAppWhenRun launches Flutter; wait for Home to install its handler.
    for _ in 0..<150 {
      try Task.checkCancellation()
      if isReady { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    guard isReady else {
      throw SiriBridgeError("Wake My PC is not ready. Open the app, then ask Siri again.")
    }
    try Task.checkCancellation()

    guard let preparation = try await invoke("prepare", arguments: ["action": action])
      as? [String: Any],
      let ticket = preparation["ticket"] as? String,
      let name = preparation["name"] as? String,
      let delay = preparation["delay"] as? NSNumber else {
      throw SiriBridgeError("Wake My PC could not prepare this request. Please open the app.")
    }

    do {
      try Task.checkCancellation()
      if action == "sleep" || action == "shutdown" {
        guard let confirm = confirm else {
          throw SiriBridgeError("This power action requires confirmation.")
        }
        let question = action == "sleep"
          ? "Put \(name) to sleep in \(delay.intValue) seconds?"
          : "Shut down \(name) in \(delay.intValue) seconds? Save your work before continuing."
        try await confirm(question)
      }
      try Task.checkCancellation()
      guard let reply = try await invoke("execute", arguments: ["ticket": ticket]) as? String else {
        throw SiriBridgeError("No result was confirmed. Check your PC before trying again.")
      }
      return reply
    } catch {
      // Cancelling Siri's prompt invalidates the preparation without sending.
      _ = try? await invoke("discard", arguments: ["ticket": ticket])
      throw error
    }
  }

  private func invoke(_ method: String, arguments: [String: Any]) async throws -> Any? {
    guard isReady, let channel = channel else {
      throw SiriBridgeError("Wake My PC is not ready. Please open the app.")
    }
    return try await withCheckedThrowingContinuation { continuation in
      // Also bound a missing Dart reply. A timeout must never cause a resend.
      var completed = false
      let timeout = DispatchWorkItem {
        guard !completed else { return }
        completed = true
        continuation.resume(throwing: SiriBridgeError(
          "The request timed out. It may have reached your PC. Check your PC before trying again."
        ))
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
      channel.invokeMethod(method, arguments: arguments) { result in
        guard !completed else { return }
        completed = true
        timeout.cancel()
        if let error = result as? FlutterError {
          continuation.resume(throwing: SiriBridgeError(
            error.message ?? "The request failed. Open Wake My PC to check your settings."
          ))
        } else {
          continuation.resume(returning: result)
        }
      }
    }
  }
}

struct SiriBridgeError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
