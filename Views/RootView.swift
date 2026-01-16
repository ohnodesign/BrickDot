// RootView.swift
import SwiftUI
import SwiftData

enum RootTab: Hashable { case home, stats, new, clients, log, export }

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {

            NavigationStack {
                HomeView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Home", systemImage: "house") }
            .tag(RootTab.home)

            NavigationStack {
                StatsPageView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            .tag(RootTab.stats)

            NavigationStack {
                NewEntryView(onSaved: { selectedTab = .home })   // 👈 bounce to Home on save
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("New", systemImage: "plus.circle") }
            .tag(RootTab.new)

            NavigationStack {
                ClientListView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Clients", systemImage: "person.2") }
            .tag(RootTab.clients)

            NavigationStack {
                LogView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Log", systemImage: "doc.text") }
            .tag(RootTab.log)

            NavigationStack {
                ExportView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            .tag(RootTab.export)
        }
    }
}
