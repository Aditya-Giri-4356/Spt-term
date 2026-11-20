import SwiftUI

struct SearchView: View {
    @StateObject var viewModel: SearchViewModel
    @Binding var path: [AppRoute]

    @EnvironmentObject private var theme: TerminalTheme
    @Environment(\.artworkProvider) private var artworkProvider
    @Environment(\.playerService) private var player

    init(viewModel: SearchViewModel, path: Binding<[AppRoute]> = .constant([])) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _path = path
    }

    var body: some View {
        SearchContent(viewModel: viewModel, path: $path)
    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            SearchPreview()
        }
    }

    private struct SearchPreview: View {
        @State private var path: [AppRoute] = []
        @StateObject private var viewModel = SearchViewModel(library: PreviewServices().library)

        var body: some View {
            SearchView(viewModel: viewModel, path: $path)
        }
    }
}
