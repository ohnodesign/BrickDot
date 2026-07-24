import SwiftUI

/// Returns `mac` when running as a true Mac Catalyst app ("Optimize
/// Interface for Mac", no automatic point scaling), `base` everywhere else.
///
/// Several controls (filter chips, status pills, row metadata) use
/// iPhone-touch-tuned caption-sized type. On iPhone/iPad that's correct;
/// on Mac, with scaling opted out of, those same point sizes read as
/// undersized next to native Mac app conventions (~13pt body as a floor).
/// This gives those spots a one-step bump on Mac without touching iPhone/iPad.
func macSized<T>(_ base: T, _ mac: T) -> T {
    #if targetEnvironment(macCatalyst)
    return mac
    #else
    return base
    #endif
}
