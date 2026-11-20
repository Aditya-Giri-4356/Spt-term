import SwiftUI

struct LibraryShellContent: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Binding var isNowPlayingExpanded: Bool
    @Binding var path: [AppRoute]

    init(
        viewModel: LibraryViewModel,
        isNowPlayingExpanded: Binding<Bool>,
        path: Binding<[AppRoute]> = .constant([])
    ) {
        self.viewModel = viewModel
        self._isNowPlayingExpanded = isNowPlayingExpanded
        self._path = path
    }

    var body: some View {
        LibraryView(
            viewModel: viewModel,
            isNowPlayingExpanded: $isNowPlayingExpanded,
            path: $path
        )
    }
}
