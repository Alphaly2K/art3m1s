import Foundation
import OSLog

enum AppLogger {
  private static let logger = Logger(
    subsystem: "moe.alphaly.art3m1s",
    category: "native"
  )

  static func info(_ message: String) {
    logger.info("\(message, privacy: .public)")
  }

  static func debug(_ message: String) {
    logger.debug("\(message, privacy: .public)")
  }

  static func warning(_ message: String) {
    logger.warning("\(message, privacy: .public)")
  }

  static func error(_ message: String) {
    logger.error("\(message, privacy: .public)")
  }
}
