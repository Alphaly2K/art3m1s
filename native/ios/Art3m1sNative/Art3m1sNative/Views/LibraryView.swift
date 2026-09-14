import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
  @EnvironmentObject private var library: LibraryStore
  @State private var isImporting = false
  @State private var selectedGame: GameEntry?

  var body: some View {
    Group {
      if library.games.isEmpty {
        ScrollView {
          VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
              .font(.system(size: 44, weight: .regular))
              .foregroundStyle(.secondary)
            Text("库中暂无项目")
              .font(.title3.weight(.semibold))
            Text("将游戏文件夹导入本 App 的 Games 目录，或下拉重新扫描")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            Button("导入外部文件夹") {
              isImporting = true
            }
            .buttonStyle(.borderedProminent)
          }
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 24)
          .frame(maxWidth: .infinity, minHeight: 480)
        }
        .refreshable {
          await library.scanAppFolder()
        }
      } else {
        List {
          ForEach(library.games.sorted { $0.addedAt > $1.addedAt }) { game in
            Button {
              selectedGame = game
            } label: {
              GameRowView(game: game)
            }
            .buttonStyle(.plain)
            .contextMenu {
              Button("开始游戏", systemImage: "play.fill") {
                library.markPlayed(game)
              }
              Button("编辑", systemImage: "pencil") {
                selectedGame = game
              }
              Button("从库中移除", systemImage: "trash", role: .destructive) {
                library.delete(game)
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                library.delete(game)
              } label: {
                Label("移除", systemImage: "trash")
              }
            }
          }
        }
        .listStyle(.insetGrouped)
        .refreshable {
          await library.scanAppFolder()
        }
      }
    }
    .navigationTitle("资料库")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isImporting = true
        } label: {
          Label("导入外部文件夹", systemImage: "plus")
        }
        .help("导入外部文件夹到本 App 的 Games 目录")
      }
    }
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls):
        Task {
          await library.importFolders(urls)
        }
      case .failure(let error):
        library.message = "选择目录失败：\(error.localizedDescription)"
      }
    }
    .sheet(item: $selectedGame) { game in
      NavigationStack {
        GameDetailView(game: game)
      }
      .environmentObject(library)
    }
    .alert(
      "Art3m1s",
      isPresented: Binding(
        get: { library.message != nil },
        set: { if !$0 { library.message = nil } }
      )
    ) {
      Button("好", role: .cancel) {
        library.message = nil
      }
    } message: {
      Text(library.message ?? "")
    }
    .overlay {
      if library.isWorking {
        ProgressView("正在处理…")
          .padding(20)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
      }
    }
  }
}

private struct GameRowView: View {
  let game: GameEntry

  var body: some View {
    HStack(spacing: 14) {
      GameCoverView(path: game.coverPath)
        .frame(width: 64, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 5) {
        Text(game.displayNameOrName)
          .font(.headline)
          .lineLimit(1)
        Text(game.engine.label)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text(AppDataPaths.displayPath(for: game.path))
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
  }
}

private struct GameCoverView: View {
  let path: String?

  var body: some View {
    if let path,
       let image = UIImage(contentsOfFile: path) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        Color.secondary.opacity(0.12)
        Image(systemName: "folder")
          .font(.title2)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct GameDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var settings: SettingsStore
  @State private var edited: GameEntry
  @State private var showingPlayer = false
  @State private var dialogText = ""

  init(game: GameEntry) {
    _edited = State(initialValue: game)
  }

  var body: some View {
    Form {
      Section("游戏") {
        TextField("显示名称", text: $edited.name)
        LabeledContent(
          "路径",
          value: AppDataPaths.displayPath(for: edited.path)
        )
        LabeledContent("引擎", value: edited.engine.label)
      }

      Section {
        Button {
          library.markPlayed(edited)
          dialogText = ""
          showingPlayer = true
          let feedback = UIImpactFeedbackGenerator(style: .light)
          feedback.impactOccurred()
        } label: {
          Label("开始游戏", systemImage: "play.fill")
        }
      } footer: {
        Text("使用 art3m1s-core 原生运行时启动。")
      }

      Section("项目补丁") {
        Toggle("文本翻译", isOn: $edited.translationEnabled)
        Toggle("环境补丁", isOn: $edited.environmentPatchEnabled)
        Toggle("实验性 Eluna", isOn: $edited.experimentalElunaEnabled)
      }
    }
    .navigationTitle(edited.displayNameOrName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("取消") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("保存") {
          library.update(edited)
          dismiss()
        }
      }
    }
    .fullScreenCover(isPresented: $showingPlayer) {
      NativePlayerView(
        game: edited,
        backend: settings.backend,
        translationSettings: settings.translation,
        renderUpscalingEnabled: settings.renderUpscalingEnabled,
        debugModeEnabled: settings.debugModeEnabled
      )
    }
  }
}

private struct NativePlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var settings: SettingsStore
  @StateObject private var runtime: NativePlayerRuntime
  @State private var dialogText = ""

  init(
    game: GameEntry,
    backend: Int,
    translationSettings: TranslationSettings,
    renderUpscalingEnabled: Bool,
    debugModeEnabled: Bool
  ) {
    _runtime = StateObject(
      wrappedValue: NativePlayerRuntime(
        game: game,
        backend: backend,
        translationSettings: translationSettings,
        renderUpscalingEnabled: renderUpscalingEnabled,
        debugModeEnabled: debugModeEnabled
      )
    )
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      GeometryReader { geometry in
        let rect = aspectFitRect(
          contentSize: CGSize(
            width: runtime.stageWidth,
            height: runtime.stageHeight
          ),
          containerSize: geometry.size
        )

        ZStack {
          if runtime.externalSurfaceKind != 4, let frame = runtime.frame {
            Image(decorative: frame, scale: 1)
              .resizable()
              .interpolation(.high)
          } else if !runtime.isRunning {
            ProgressView()
              .tint(.white)
          }

          MetalHostView { layer, size in
            runtime.attachMetalLayer(layer, size: size)
          }
            .opacity(runtime.externalSurfaceKind == 4 ? 1 : 0)

          GameInputSurface(
            stageSize: CGSize(
              width: runtime.stageWidth,
              height: runtime.stageHeight
            ),
            touchpadEnabled: settings.mobileTouchpadEnabled,
            inputGate: runtime.effectiveInputGate,
            onMouse: { runtime.feedMouse(point: $0) },
            onMouseButton: { runtime.feedMouseButton(button: $0, pressed: $1) },
            onTouch: { runtime.feedTouch(id: $0, phase: $1, point: $2) },
            onKey: { runtime.feedKey($0, pressed: $1) },
            onForwardedWheelKey: { runtime.feedWheel($0) }
          )
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
      }
      .ignoresSafeArea()

      VStack(spacing: 0) {
        HStack {
          if settings.runtimeHUDEnabled,
             runtime.isRunning || runtime.frame != nil {
            RuntimeHUDView(hud: runtime.hud)
          }

          Spacer()

          Button {
            dismiss()
          } label: {
            Label("退出", systemImage: "chevron.down")
              .labelStyle(.iconOnly)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.bordered)
          .tint(.white)
        }
        .padding()
        Spacer()
      }

      if let error = runtime.errorMessage {
        Text(error)
          .font(.callout)
          .multilineTextAlignment(.center)
          .foregroundStyle(.white)
          .padding(.horizontal, 18)
          .padding(.vertical, 12)
          .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
          .padding(.horizontal, 24)
      }

      if runtime.avoidOverlay {
        Color.black
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }
    }
    .statusBarHidden(!runtime.showStatusBar)
    .persistentSystemOverlays(.hidden)
    .onAppear {
      AppOrientation.lockLandscape()
    }
    .task {
      await runtime.start()
    }
    .onDisappear {
      AppOrientation.unlock()
      runtime.stop()
    }
    .onChange(of: runtime.shouldClose) { value in
      if value {
        dismiss()
      }
    }
    .onChange(of: scenePhase) { phase in
      switch phase {
      case .active:
        runtime.setSuspended(false)
      case .inactive, .background:
        runtime.setSuspended(true)
      @unknown default:
        break
      }
    }
    .alert(
      runtime.dialog?.title ?? "",
      isPresented: Binding(
        get: { runtime.dialog != nil },
        set: { if !$0 { runtime.submitDialog(accepted: false, text: "") } }
      )
    ) {
      if runtime.dialog?.hasTextField == true {
        TextField("输入", text: $dialogText)
      }
      if runtime.dialog?.hasCancel == true {
        Button("取消", role: .cancel) {
          runtime.submitDialog(accepted: false, text: dialogText)
        }
      }
      Button("确定") {
        runtime.submitDialog(accepted: true, text: dialogText)
      }
    } message: {
      Text(runtime.dialog?.message ?? "")
    }
    .onChange(of: runtime.dialog?.id) { _ in
      dialogText = runtime.dialog?.initialText ?? ""
    }
  }
}

private struct RuntimeHUDView: View {
  let hud: NativeRuntimeHUD

  var body: some View {
    Text(
      """
      \(hud.graphicsAPI)
      零拷贝：\(hud.zeroCopyPath)
      \(hud.metalFXStatus.map { "MetalFX：\($0)\n" } ?? "")
      内存：\(String(format: "%.1f", hud.residentMiB)) MB
      FPS：\(String(format: "%.1f", hud.fps))
      """
    )
    .font(.system(.caption2, design: .monospaced).weight(.semibold))
    .foregroundStyle(.white)
    .multilineTextAlignment(.leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .combine)
  }
}

private func aspectFitRect(
  contentSize: CGSize,
  containerSize: CGSize
) -> CGRect {
  guard contentSize.width > 0,
        contentSize.height > 0,
        containerSize.width > 0,
        containerSize.height > 0
  else {
    return .zero
  }
  let scale = min(
    containerSize.width / contentSize.width,
    containerSize.height / contentSize.height
  )
  let size = CGSize(
    width: contentSize.width * scale,
    height: contentSize.height * scale
  )
  return CGRect(
    x: (containerSize.width - size.width) / 2,
    y: (containerSize.height - size.height) / 2,
    width: size.width,
    height: size.height
  )
}
