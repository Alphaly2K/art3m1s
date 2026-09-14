import Foundation
import SwiftUI

struct LicensesView: View {
  @State private var query = ""

  private var filteredPackages: [LicensePackage] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !normalized.isEmpty else {
      return LicenseCatalog.rustPackages
    }
    return LicenseCatalog.rustPackages.filter { package in
      package.displayName.lowercased().contains(normalized)
        || package.licenseIdentifier.lowercased().contains(normalized)
    }
  }

  var body: some View {
    List {
      Section("Art3m1s") {
        NavigationLink {
          LicenseDetailView(document: LicenseCatalog.applicationLicense)
        } label: {
          LabeledContent("应用许可证", value: "MPL-2.0")
        }
      }

      Section("原生组件") {
        ForEach(LicenseCatalog.nativeDocuments) { document in
          NavigationLink {
            LicenseDetailView(document: document)
          } label: {
            LabeledContent(document.title, value: document.license)
          }
        }
      }

      Section("Rust Crates") {
        if filteredPackages.isEmpty {
          Text("没有匹配的许可证")
            .foregroundStyle(.secondary)
        } else {
          ForEach(filteredPackages) { package in
            NavigationLink {
              LicenseDetailView(document: package.document)
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(package.displayName)
                Text(package.licenseIdentifier)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .navigationTitle("开源许可证")
    .searchable(
      text: $query,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "搜索包名或许可证"
    )
  }
}

private struct LicenseDetailView: View {
  let document: LicenseDocument

  var body: some View {
    ScrollView {
      Text(document.text)
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
    .navigationTitle(document.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct LicenseDocument: Identifiable {
  let id: String
  let title: String
  let license: String
  let text: String
}

private struct LicensePackage: Decodable, Identifiable {
  let package: String
  let version: String?
  let spdx: String?
  let text: String?

  var id: String {
    "\(package):\(version ?? "")"
  }

  var displayName: String {
    guard let version, !version.isEmpty else { return package }
    return "\(package) \(version)"
  }

  var licenseIdentifier: String {
    guard let spdx, !spdx.isEmpty else { return "未标注" }
    return spdx
  }

  var document: LicenseDocument {
    var body = ""
    if let spdx, !spdx.isEmpty,
       text?.contains("SPDX-License-Identifier:") != true {
      body += "SPDX-License-Identifier: \(spdx)\n\n"
    }
    body += text?.isEmpty == false
      ? text!
      : "This crate did not bundle a license text."
    return LicenseDocument(
      id: id,
      title: displayName,
      license: licenseIdentifier,
      text: body
    )
  }
}

private enum LicenseCatalog {
  static let applicationLicense = loadDocument(
    title: "Art3m1s",
    license: "MPL-2.0",
    resource: "Art3m1s-LICENSE",
    extension: "txt",
    fallback: "Mozilla Public License Version 2.0"
  )

  static let nativeDocuments: [LicenseDocument] = [
    loadDocument(
      title: "FFmpeg",
      license: "LGPL-2.1-or-later",
      resource: "FFmpeg-LICENSE",
      extension: "txt",
      fallback: "FFmpeg is licensed under the GNU Lesser General Public License."
    ),
    loadDocument(
      title: "ANGLE",
      license: "BSD-3-Clause",
      resource: "ANGLE-NOTICE",
      extension: "txt",
      fallback: "ANGLE is licensed under the BSD 3-Clause License."
    ),
    loadDocument(
      title: "stb_vorbis / minimp3",
      license: "Public Domain / MIT / CC0",
      resource: "AudioDecode-THIRD-PARTY-NOTICES",
      extension: "txt",
      fallback: "stb_vorbis and minimp3 third-party notices."
    ),
  ]

  static let rustPackages: [LicensePackage] = {
    guard let url = Bundle.main.url(
      forResource: "rust_third_party",
      withExtension: "json"
    ), let data = try? Data(contentsOf: url),
      let packages = try? JSONDecoder().decode([LicensePackage].self, from: data)
    else {
      return []
    }
    return packages.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
        == .orderedAscending
    }
  }()

  private static func loadDocument(
    title: String,
    license: String,
    resource: String,
    extension fileExtension: String,
    fallback: String
  ) -> LicenseDocument {
    let text: String
    if let url = Bundle.main.url(
      forResource: resource,
      withExtension: fileExtension
    ), let contents = try? String(contentsOf: url, encoding: .utf8) {
      text = contents
    } else {
      text = fallback
    }
    return LicenseDocument(
      id: resource,
      title: title,
      license: license,
      text: text
    )
  }
}
