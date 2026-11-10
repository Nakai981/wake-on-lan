import AppIntents

// Keep iOS 15 app support; Siri actions require iOS 16 or newer.
@available(iOS 16.0, *)
struct WakePcIntent: AppIntent {
  static var title: LocalizedStringResource = "Turn on my PC"
  static var description = IntentDescription("Send Wake-on-LAN to your default PC on the local network.")
  static var openAppWhenRun: Bool = false
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
  static var openAppWhenRun: Bool = false
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
  static var openAppWhenRun: Bool = false
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
  static var openAppWhenRun: Bool = false
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
        "Wake with \(.applicationName)",
        "Turn on my PC with \(.applicationName)",
        "Wake my computer with \(.applicationName)",
      ],
      shortTitle: "PC On",
      systemImageName: "power"
    )
    AppShortcut(
      intent: SleepPcIntent(),
      phrases: [
        "Sleep with \(.applicationName)",
        "Put my PC to sleep with \(.applicationName)",
      ],
      shortTitle: "PC Sleep",
      systemImageName: "moon.zzz"
    )
    AppShortcut(
      intent: ShutdownPcIntent(),
      phrases: [
        "Shut down with \(.applicationName)",
        "Shut down my PC with \(.applicationName)",
      ],
      shortTitle: "PC Off",
      systemImageName: "power.circle"
    )
    AppShortcut(
      intent: CancelPcPowerIntent(),
      phrases: [
        "Cancel power with \(.applicationName)",
        "Cancel my PC power command with \(.applicationName)",
      ],
      shortTitle: "Cancel PC",
      systemImageName: "xmark.circle"
    )
  }
}
