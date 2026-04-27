import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = ReaderViewModel()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                Image(uiImage: model.renderImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(touchGesture)

                Button(action: model.openMenu) {
                    Color.clear
                        .frame(width: 96, height: 72)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: size.width, height: size.height)
            .onAppear { model.setViewportSize(size) }
            .onChange(of: size) { _, newSize in
                model.setViewportSize(newSize)
            }
            .fileImporter(
                isPresented: $model.importing,
                allowedContentTypes: [.rsvp, .plainText, .text, .html, .epub, .markdownBook],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result {
                    model.importURLs(urls)
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea(.all)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    private var touchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                model.touchChanged(value.translation)
            }
            .onEnded { value in
                model.touchEnded(value.translation)
            }
    }
}

