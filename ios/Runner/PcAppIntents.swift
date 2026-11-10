import AppIntents

// Keep iOS 15 app support; Siri actions require iOS 16 or newer.
@available(iOS 16.0, *)
struct WakePcIntent: AppIntent {
  static var title: LocalizedStringResource = "Turn on my PC"
  static var description = IntentDescription("Send Wake-on-LAN to your default PC on the local network.")
  static var openAppWhenRun: Bool = true
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let reply = try await SiriBridge.shared.run(action: "wake")
    return .result(dialog: IntentDialog(stringLiteral: reply))
  }
}

@available(iOS 16.0, *)
struct SleepPcIntent: AppIntent {
  static var title: LocalizedStringResource = "Put my PC to sleep"
  static var description = IntentDescription("Ask for confirmation, then put your default PC to sleep using its paired Windows Agent.")
  static var openAppWhenRun: Bool = true
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let reply = try await SiriBridge.shared.run(action: "sleep") { question in
      try await requestConfirmation(result: .result(dialog: IntentDialog(stringLiteral: question)))
    }
    return .result(dialog: IntentDialog(stringLiteral: reply))
  }
}

@available(iOS 16.0, *)
struct ShutdownPcIntent: AppIntent {
  static var title: LocalizedStringResource = "Shut down my PC"
  static var description = IntentDescription("Ask for confirmation, then shut down your default PC using its paired Windows Agent.")
  static var openAppWhenRun: Bool = true
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let reply = try await SiriBridge.shared.run(action: "shutdown") { question in
      try await requestConfirmation(result: .result(dialog: IntentDialog(stringLiteral: question)))
    }
    return .result(dialog: IntentDialog(stringLiteral: reply))
  }
}

@available(iOS 16.0, *)
struct CancelPcPowerIntent: AppIntent {
  static var title: LocalizedStringResource = "Cancel PC power command"
  static var description = IntentDescription("Cancel a pending sleep or shutdown command on your default PC, if Windows Agent can still cancel it.")
  static var openAppWhenRun: Bool = true
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let reply = try await SiriBridge.shared.run(action: "cancel")
    return .result(dialog: IntentDialog(stringLiteral: reply))
  }
}

@available(iOS 16.0, *)
struct PcAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: WakePcIntent(),
      phrases: [
        "Turn on my PC with \(.applicationName)",
        "Wake my computer with \(.applicationName)",
      ],
      shortTitle: "Turn on my PC",
      systemImageName: "power"
    )
    AppShortcut(
      intent: SleepPcIntent(),
      phrases: ["Put my PC to sleep with \(.applicationName)"],
      shortTitle: "Put my PC to sleep",
      systemImageName: "moon.zzz"
    )
    AppShortcut(
      intent: ShutdownPcIntent(),
      phrases: ["Shut down my PC with \(.applicationName)"],
      shortTitle: "Shut down my PC",
      systemImageName: "power.circle"
    )
    AppShortcut(
      intent: CancelPcPowerIntent(),
      phrases: ["Cancel my PC power command with \(.applicationName)"],
      shortTitle: "Cancel PC power",
      systemImageName: "xmark.circle"
    )
  }
}
