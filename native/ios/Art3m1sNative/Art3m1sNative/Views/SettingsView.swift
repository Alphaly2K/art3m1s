import SwiftUI
import UIKit

struct SettingsView: View {
  @EnvironmentObject private var settings: SettingsStore
  @State private var exportedFile: ExportedFile?
  @State private var isExporting = false
  @State private var exportError: String?

  var body: some View {
    Form {
      Section("渲染") {
        Picker("图形后端", selection: $settings.backend) {
          ForEach(settings.availableBackends, id: \.value) { backend in
            Text(backend.label).tag(backend.value)
          }
        }

        Toggle(
          "超分输出",
          isOn: $settings.renderUpscalingEnabled
        )
      }

      Section("运行时") {
        Toggle(
          "运行时信息浮层",
          isOn: $settings.runtimeHUDEnabled
        )

        NavigationLink {
          TranslationSettingsView()
        } label: {
          LabeledContent("文本翻译", value: settings.translation.mode.label)
        }
      }

      Section("控制") {
        Toggle(
          "触摸板鼠标",
          isOn: $settings.mobileTouchpadEnabled
        )
      }

      Section("诊断") {
        Toggle("调试模式", isOn: $settings.debugModeEnabled)

        Toggle("崩溃与错误上报", isOn: $settings.crashReportingEnabled)

        Button {
          Task {
            await exportProfilerReport()
          }
        } label: {
          Label("导出 Profiler 报告", systemImage: "chart.bar.doc.horizontal")
        }
        .disabled(isExporting)

        Button {
          Task {
            await exportDebugLogs()
          }
        } label: {
          Label("导出调试日志", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(isExporting)
      }
    }
    .navigationTitle("设置")
    .overlay {
      if isExporting {
        ProgressView("正在导出…")
          .padding(20)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
      }
    }
    .sheet(item: $exportedFile) { file in
      ShareSheet(items: [file.url])
    }
    .alert(
      "导出失败",
      isPresented: Binding(
        get: { exportError != nil },
        set: { if !$0 { exportError = nil } }
      )
    ) {
      Button("好", role: .cancel) {
        exportError = nil
      }
    } message: {
      Text(exportError ?? "")
    }
  }

  @MainActor
  private func exportProfilerReport() async {
    isExporting = true
    defer { isExporting = false }
    do {
      exportedFile = ExportedFile(url: try AppDiagnostics.exportProfilerReport())
    } catch {
      exportError = error.localizedDescription
    }
  }

  @MainActor
  private func exportDebugLogs() async {
    isExporting = true
    defer { isExporting = false }
    do {
      exportedFile = ExportedFile(url: try await AppDiagnostics.exportDebugLogs())
    } catch {
      exportError = error.localizedDescription
    }
  }
}

private struct ExportedFile: Identifiable {
  let id = UUID()
  let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(
    _ uiViewController: UIActivityViewController,
    context: Context
  ) {}
}

private struct TranslationSettingsView: View {
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    Form {
      Section("模式") {
        Picker("翻译模式", selection: $settings.translation.mode) {
          ForEach(TranslationMode.allCases, id: \.self) { mode in
            Text(mode.label).tag(mode)
          }
        }
      }

      if settings.translation.mode == .online {
        Section("服务") {
          Picker("提供商", selection: $settings.translation.provider) {
            ForEach(TranslationProvider.allCases, id: \.self) { provider in
              Text(provider.label).tag(provider)
            }
          }

          TextField("接口地址", text: $settings.translation.endpoint)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

          if settings.translation.provider == .openAi
            || settings.translation.provider == .anthropic {
            TextField("模型", text: $settings.translation.model)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
        }

        Section("凭据") {
          switch settings.translation.provider {
          case .baidu, .youdao:
            TextField("App ID", text: $settings.translation.appID)
              .textInputAutocapitalization(.never)
            SecureField("App Secret", text: $settings.translation.appSecret)
          default:
            SecureField("API Key", text: $settings.translation.apiKey)
          }
        }

        Section("语言") {
          Picker("源语言", selection: $settings.translation.sourceLanguage) {
            ForEach(translationLanguages, id: \.self) {
              Text($0).tag($0)
            }
          }
          Picker("目标语言", selection: $settings.translation.targetLanguage) {
            ForEach(translationLanguages.filter { $0 != "自动检测" }, id: \.self) {
              Text($0).tag($0)
            }
          }
        }
      }
    }
    .navigationTitle("文本翻译")
    .navigationBarTitleDisplayMode(.inline)
  }
}
