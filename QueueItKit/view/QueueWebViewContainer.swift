import SwiftUI

public struct QueueWebViewContainer: View {

    @StateObject var viewManager: QueueItViewManager
    
    private var progressBackgroundColor: Color
    private var progressColor: Color

    public init(
        viewManager: QueueItViewManager,
        progressBackgroundColor: Color = .white,
        progressColor: Color = .gray
    ) {
        _viewManager = StateObject(wrappedValue: viewManager)
        self.progressBackgroundColor = progressBackgroundColor
        self.progressColor = progressColor
    }

    public var body: some View {
        ZStack {
            QueueWebView(viewManager: viewManager)

            if viewManager.isLoading {
                VStack {
                    ProgressView()
                        .tint(progressColor)
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .padding()

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(progressBackgroundColor)
            }
        }
        .navigationBarHidden(true)
    }
}
