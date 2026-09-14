import SwiftUI
import UIKit

@main
struct Art3m1sApp: App {
  @UIApplicationDelegateAdaptor(Art3m1sAppDelegate.self)
  private var appDelegate
  @StateObject private var libraryStore = LibraryStore()
  @StateObject private var settingsStore = SettingsStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(libraryStore)
        .environmentObject(settingsStore)
        .task {
          settingsStore.activateDebugMode()
          await libraryStore.prepare()
        }
    }
  }
}

final class Art3m1sAppDelegate: NSObject, UIApplicationDelegate {
  static var orientationLock: UIInterfaceOrientationMask = .all

  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    Self.orientationLock
  }
}

enum AppOrientation {
  static func lockLandscape() {
    Art3m1sAppDelegate.orientationLock = .landscape
    update(.landscape)
  }

  static func unlock() {
    Art3m1sAppDelegate.orientationLock = .all
    update(.all)
  }

  private static func update(_ mask: UIInterfaceOrientationMask) {
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    else {
      return
    }
    scene.windows.first(where: \.isKeyWindow)?.rootViewController?
      .setNeedsUpdateOfSupportedInterfaceOrientations()
    if #available(iOS 16.0, *) {
      scene.requestGeometryUpdate(
        .iOS(interfaceOrientations: mask)
      )
    }
  }
}
