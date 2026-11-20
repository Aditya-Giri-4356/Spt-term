import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var isNowPlayingExpanded: Bool
    var namespace: Namespace.ID
    @Binding var path: [AppRoute]

    init(
        viewModel: HomeViewModel,
        isNowPlayingExpanded: Binding<Bool>,
        namespace: Namespace.ID,
        path: Binding<[AppRoute]> = .constant([])
    ) {
        self.viewModel = viewModel
        self._isNowPlayingExpanded = isNowPlayingExpanded
        self.namespace = namespace
        self._path = path
    }

    var body: some View {
        HomeDestination(
            viewModel: viewModel,
            namespace: namespace,
            isNowPlayingExpanded: $isNowPlayingExpanded,
            path: $path
        )
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalAppPreview {
            HomePreview()
        }
    }

    private struct HomePreview: View {
        @State private var isExpanded = false
        @State private var path: [AppRoute] = []
        @Namespace private var namespace
        @StateObject private var viewModel = HomeViewModel(
            library: PreviewServices().library,
            player: PreviewServices().player
        )

        var body: some View {
            HomeView(viewModel: viewModel, isNowPlayingExpanded: $isExpanded, namespace: namespace, path: $path)
        }
    }
}
