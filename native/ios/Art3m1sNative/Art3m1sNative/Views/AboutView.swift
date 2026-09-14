import SwiftUI

struct AboutView: View {
  private let appRepository = URL(string: "https://github.com/Alphaly2K/art3m1s")!
  private let coreRepository = URL(
    string: "https://github.com/Alphaly2K/art3m1s-core"
  )!

  var body: some View {
    List {
      Section {
        HStack(spacing: 16) {
          Image(systemName: "sparkles.rectangle.stack")
            .font(.system(size: 34, weight: .semibold))
            .frame(width: 64, height: 64)
            .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

          VStack(alignment: .leading, spacing: 4) {
            Text("Art3m1s")
              .font(.title2.weight(.bold))
            Text("Artemis 视觉小说引擎前端")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Text("版本 \(versionText) · MPL-2.0")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.vertical, 6)
      }

      Section("仓库") {
        Link(destination: appRepository) {
          LabeledContent("Flutter App", value: "GitHub")
        }
        Link(destination: coreRepository) {
          LabeledContent("Rust Core", value: "GitHub")
        }
      }

      Section("主要模块") {
        LabeledContent("界面", value: "SwiftUI")
        LabeledContent("核心", value: "art3m1s-core")
        LabeledContent("图形", value: "Metal / ANGLE")
      }
    }
    .navigationTitle("关于")
  }

  private var versionText: String {
    let version = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "1.0"
    let build = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleVersion"
    ) as? String ?? "1"
    return "\(version) (\(build))"
  }
}
