import UIKit
import WebKit
import Combine

public class QueueWebViewController: UIViewController {
    
    private let viewManager: QueueItViewManager
    private let webView: WKWebView
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    
    private var cancellables = Set<AnyCancellable>()

    private var progressBackgroundColor: UIColor
    private var progressColor: UIColor
    
    public init(
        viewManager: QueueItViewManager,
        progressBackgroundColor: UIColor = .white,
        progressColor: UIColor = .gray
    ) {
        self.viewManager = viewManager
        self.webView = viewManager.webView
        self.progressBackgroundColor = progressBackgroundColor
        self.progressColor = progressColor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(webView)
        view.addSubview(loadingIndicator)

        webView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.backgroundColor = progressBackgroundColor
        loadingIndicator.color = progressColor

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            loadingIndicator.topAnchor.constraint(equalTo: view.topAnchor),
            loadingIndicator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingIndicator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingIndicator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        viewManager.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] isLoading in
                guard let self = self else { return }
                if isLoading {
                    self.loadingIndicator.startAnimating()
                    self.loadingIndicator.isHidden = false
                } else {
                    self.loadingIndicator.stopAnimating()
                    self.loadingIndicator.isHidden = true
                }
            }
            .store(in: &cancellables)
    }
}
