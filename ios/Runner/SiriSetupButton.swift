import AppIntents
import Flutter
import UIKit

/// Uses Apple's actual control so a tap opens this app's App Shortcuts page.
/// Creating or tapping this view never invokes a PC command.
final class SiriSetupButtonFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let dark = (args as? [String: Any])?["dark"] as? Bool ?? false
    return SiriSetupButtonView(frame: frame, dark: dark)
  }
}

final class SiriSetupButtonView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect, dark: Bool) {
    container = UIView(frame: frame)
    super.init()

    let content: UIView
    if #available(iOS 16.0, *) {
      PcAppShortcuts.updateAppShortcutParameters()
      content = ShortcutsUIButton(style: dark ? .light : .dark)
    } else {
      let label = UILabel()
      label.text = "Siri setup requires iOS 16 or later."
      label.textColor = .secondaryLabel
      label.font = .preferredFont(forTextStyle: .footnote)
      label.adjustsFontForContentSizeCategory = true
      label.textAlignment = .center
      label.numberOfLines = 0
      content = label
    }
    content.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      content.topAnchor.constraint(equalTo: container.topAnchor),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
  }

  func view() -> UIView { container }
}
