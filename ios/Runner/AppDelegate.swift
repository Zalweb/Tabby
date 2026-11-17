import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let qrExport = TabbyQrExport()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "tabby/receiving_qr",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "QR export is unavailable.", details: nil))
        return
      }
      self.qrExport.handle(call, result: result)
    }
  }
}

/// The Dart caller downloads with current authorization and validates the QR.
/// Exporting an image never records or confirms a payment.
private final class TabbyQrExport: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate {
  private var pendingResult: FlutterResult?
  private var temporaryDirectory: URL?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "capabilities" {
      result(["save": true, "share": true, "platform": "ios"])
      return
    }
    guard call.method == "save" || call.method == "share" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: "Finish the current QR export first.", details: nil))
      return
    }
    guard let arguments = call.arguments as? [String: Any],
      let typed = arguments["bytes"] as? FlutterStandardTypedData,
      !typed.data.isEmpty, typed.data.count <= 10 * 1024 * 1024,
      Array(typed.data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10],
      UIImage(data: typed.data) != nil else {
      result(FlutterError(code: "invalid_image", message: "Choose a valid QR image.", details: nil))
      return
    }
    guard UIApplication.shared.applicationState == .active,
      let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "unavailable", message: "Reopen Tabby to export this QR.", details: nil))
      return
    }
    var presenter = root
    while let presented = presenter.presentedViewController {
      presenter = presented
    }
    guard !presenter.isBeingDismissed, !presenter.isBeingPresented else {
      result(FlutterError(code: "busy", message: "Try QR export again in a moment.", details: nil))
      return
    }
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("tabby-qr-" + UUID().uuidString, isDirectory: true)
    let file = folder.appendingPathComponent("Tabby-receiving-QR.png")
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try typed.data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    } catch {
      try? FileManager.default.removeItem(at: folder)
      result(FlutterError(code: "export_failed", message: "Could not prepare this QR image.", details: nil))
      return
    }
    temporaryDirectory = folder
    pendingResult = result
    if call.method == "share" {
      let controller = UIActivityViewController(activityItems: [file], applicationActivities: nil)
      // iPad requires an anchored popover, even for a full-width Flutter page.
      controller.popoverPresentationController?.sourceView = presenter.view
      controller.popoverPresentationController?.sourceRect = CGRect(
        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1
      )
      controller.popoverPresentationController?.permittedArrowDirections = []
      controller.completionWithItemsHandler = { [weak self] _, completed, _, error in
        if error != nil {
          self?.finish(FlutterError(code: "share_failed", message: "Could not share this QR image.", details: nil))
        } else {
          self?.finish(completed)
        }
      }
      presenter.present(controller, animated: true)
    } else {
      let controller: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        controller = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
      } else {
        controller = UIDocumentPickerViewController(urls: [file], in: .exportToService)
      }
      controller.delegate = self
      presenter.present(controller, animated: true) {
        controller.presentationController?.delegate = self
      }
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]) {
    finish(!urls.isEmpty)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(false)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(false)
  }

  private func finish(_ value: Any?) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    if let folder = temporaryDirectory {
      try? FileManager.default.removeItem(at: folder)
    }
    temporaryDirectory = nil
    result(value)
  }
}
