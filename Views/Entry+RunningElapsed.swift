// Models/Extensions/Entry+RunningElapsed.swift
import Foundation

extension Entry {
    /// Returns the current running elapsed hours, or 0 if unavailable.
    var runningElapsedHoursOrZero: Double {
        return runningElapsedHours ?? 0
    }
}
