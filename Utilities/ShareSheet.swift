// Utilities/ShareSheet.swift
import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Wrapper so we can use .sheet(item:)
struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
