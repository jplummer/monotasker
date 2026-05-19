import Foundation

/// Shared launch-time reference for [TIMING] instrumentation.
/// Remove this file once the cold-launch bottleneck is identified.
enum MonotaskerTiming {
  static let t0 = Date()
}
