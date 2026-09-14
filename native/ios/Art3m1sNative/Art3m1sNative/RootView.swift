import SwiftUI

struct RootView: View {
  @State private var selection = AppTab.library

  var body: some View {
    TabView(selection: $selection) {
      NavigationStack {
        LibraryView()
      }
      .tabItem {
        Label("资料库", systemImage: "square.grid.2x2")
      }
      .tag(AppTab.library)

      NavigationStack {
        SettingsView()
      }
      .tabItem {
        Label("设置", systemImage: "gearshape")
      }
      .tag(AppTab.settings)

      NavigationStack {
        AboutView()
      }
      .tabItem {
        Label("关于", systemImage: "info.circle")
      }
      .tag(AppTab.about)
    }
  }
}

private enum AppTab: Hashable {
  case library
  case settings
  case about
}

#Preview {
  RootView()
    .environmentObject(LibraryStore.preview)
    .environmentObject(SettingsStore.preview)
}
