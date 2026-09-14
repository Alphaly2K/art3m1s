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
          Image("BrandLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
            }

          VStack(alignment: .leading, spacing: 4) {
            Text("Art3m1s")
              .font(.title2.weight(.bold))
            Text("Art3m1s Native Host")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Text("版本 \(versionText) · MPL-2.0")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.vertical, 6)
      }

      Section("许可证") {
        NavigationLink {
          LicensesView()
        } label: {
          LabeledContent("开源许可证", value: "MPL-2.0")
        }
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
    ) as? String ?? "1.4.0"
    let build = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleVersion"
    ) as? String ?? "1"
    return "\(version) (\(build))"
  }
}
