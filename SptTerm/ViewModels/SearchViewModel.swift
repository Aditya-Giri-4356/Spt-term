import Combine
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: SearchResults?
    @Published private(set) var isSearching = false
    @Published private(set) var recentSearches: [String] = []

    let library: LibraryServiceProtocol
    private var cancellable: AnyCancellable?

    private static let recentKey = "search.recent"

    init(library: LibraryServiceProtocol) {
        self.library = library
        recentSearches = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        cancellable = $query
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] value in
                self?.runSearch(value)
            }
    }

    deinit {
        cancellable?.cancel()
    }

    private func runSearch(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = nil
            isSearching = false
            return
        }
        isSearching = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await library.search(query: trimmed)
                guard self.query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                results = found
                recordRecent(trimmed)
            } catch {
                guard self.query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                results = SearchResults(query: trimmed, artists: [], albums: [], tracks: [], playlists: [])
            }
            isSearching = false
        }
    }

    func clearRecent() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: Self.recentKey)
    }

    private func recordRecent(_ term: String) {
        var list = recentSearches.filter { $0 != term }
        list.insert(term, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        recentSearches = list
        UserDefaults.standard.set(list, forKey: Self.recentKey)
    }
}
