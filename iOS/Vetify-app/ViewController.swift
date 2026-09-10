import UIKit
@preconcurrency import WebKit
import Network

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, WKScriptMessageHandler {

    var webView: WKWebView!
    var refreshControl = UIRefreshControl()
    let monitor = NWPathMonitor()
    var progressView: UIProgressView!
    var loadingLabel: UILabel!
    var imagePickerCompletion: (([URL]?) -> Void)?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    func makeWebViewWithCustomScripts() -> WKWebView {
        let contentController = WKUserContentController()

        // Puente JS → nativo: window.webkit.messageHandlers.push.postMessage({action: "clearToken"})
        contentController.add(WeakScriptMessageHandler(self), name: "push")

        if let cssPath = Bundle.main.path(forResource: "style", ofType: "css"),
           let cssContent = try? String(contentsOfFile: cssPath, encoding: .utf8).replacingOccurrences(of: "\n", with: "") {
            let cssWrappedInJS = """
            var style = document.createElement('style');
            style.type = 'text/css';
            style.appendChild(document.createTextNode(\(cssContent)));
            document.head.appendChild(style);
            """
            let cssScript = WKUserScript(source: cssWrappedInJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            contentController.addUserScript(cssScript)
        }

        if let jsPath = Bundle.main.path(forResource: "script", ofType: "js"),
           var jsContent = try? String(contentsOfFile: jsPath, encoding: .utf8) {
            jsContent = """
            document.addEventListener("DOMContentLoaded", function() {
                \(jsContent)
            });
            """
            let jsScript = WKUserScript(source: jsContent, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            contentController.addUserScript(jsScript)
        }

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        return WKWebView(frame: .zero, configuration: config)
    }

    override func loadView() {
        webView = makeWebViewWithCustomScripts()
        webView.navigationDelegate = self
        webView.uiDelegate = self

        view = UIView()
        view.backgroundColor = .white
        view.addSubview(webView)

        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        loadingLabel = UILabel()
        loadingLabel.text = "vetify"
        loadingLabel.textAlignment = .center
        loadingLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingLabel)

        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        progressView = UIProgressView(progressViewStyle: .default)
        progressView.sizeToFit()
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: progressView)

        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)

        let scrollView = webView.scrollView
        refreshControl.addTarget(self, action: #selector(refreshWebView), for: .valueChanged)
        scrollView.addSubview(refreshControl)

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareURL))

        let url = AppConfiguration.baseURL
        webView.load(URLRequest(url: url))
        webView.allowsBackForwardNavigationGestures = true

        monitor.pathUpdateHandler = { path in
            if path.status == .unsatisfied {
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Sin conexión", message: "No tenés conexión a internet.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }

        let queue = DispatchQueue(label: "InternetMonitor")
        monitor.start(queue: queue)

        NotificationCenter.default.addObserver(self, selector: #selector(handlePushTokenChange),
                                               name: PushBridge.tokenDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePushDeepLink),
                                               name: PushBridge.deepLinkReceived, object: nil)
    }

    @objc func refreshWebView() {
        webView.reload()
    }

    @objc func shareURL() {
        if let url = webView.url {
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            present(activityVC, animated: true)
        }
    }

    // MARK: - Push notifications

    @objc private func handlePushTokenChange() {
        DispatchQueue.main.async { [weak self] in self?.deliverPushTokenToWeb() }
    }

    @objc private func handlePushDeepLink() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let path = PushBridge.shared.consumePendingDeepLink() else { return }
            self.navigateToDeepLink(path)
        }
    }

    // Entrega el token a la web vía window.onPushToken({token, platform}).
    // La web lo retiene y lo registra en backend (POST /users/register-token) tras el login.
    private func deliverPushTokenToWeb() {
        guard let token = PushBridge.shared.deviceToken else { return }
        let js = "if (typeof window.onPushToken === 'function') { window.onPushToken({token: '\(token)', platform: 'ios'}); }"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func navigateToDeepLink(_ path: String) {
        guard let url = AppConfiguration.url(forPath: path) else { return }
        webView.load(URLRequest(url: url))
    }

    // Puente JS → nativo (window.NativeBridge.clearPushToken() en logout).
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "push" else { return }
        if let body = message.body as? [String: Any],
           let action = body["action"] as? String, action == "clearToken" {
            PushBridge.shared.clearToken()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        progressView.isHidden = true
        loadingLabel.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    private func showError(_ error: Error) {
        // Ignorar errores menores que no afectan la carga visible
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled || nsError.domain == "WebKitErrorDomain" {
            return
        }

        let alert = UIAlertController(title: "Error de carga", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reintentar", style: .default, handler: { _ in
            self.webView.reload()
        }))
        present(alert, animated: true)
    }

    // MARK: - Manejo de navegación

    // window.open() en WKWebView no dispara decidePolicyFor sino este delegate.
    // Sin esta implementación, window.open() se ignora silenciosamente.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        if let url = navigationAction.request.url {

            // Abrir mailto o tel en apps del sistema
            if url.scheme == "mailto" || url.scheme == "tel" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            // 👇 Manejo de PDF fuera del WebView
            if url.pathExtension.lowercased() == "pdf" {
                decisionHandler(.cancel)

                URLSession.shared.downloadTask(with: url) { localURL, response, error in
                    guard let localURL = localURL, error == nil else { return }

                    DispatchQueue.main.async {
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                            let activityVC = UIActivityViewController(activityItems: [localURL], applicationActivities: nil)
                            rootVC.present(activityVC, animated: true)
                        } else {
                            self.present(UIActivityViewController(activityItems: [localURL], applicationActivities: nil), animated: true)
                        }
                    }
                }.resume()
                return
            }

            // Abrir links externos fuera del dominio
            let allowedHost = AppConfiguration.allowedHost
            if let host = url.host, !allowedHost.isEmpty, !host.contains(allowedHost) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }
    
    // MARK: - Interceptar respuestas para PDFs
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {

        if let response = navigationResponse.response as? HTTPURLResponse,
           let url = response.url,
           response.mimeType == "application/pdf" {

            decisionHandler(.cancel)

            // Intentar obtener el nombre del archivo desde las cabeceras
            let suggestedFilename: String
            if let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition"),
               let filenamePart = contentDisposition.split(separator: ";").first(where: { $0.contains("filename=") }),
               let name = filenamePart.split(separator: "=").last {
                suggestedFilename = name.replacingOccurrences(of: "\"", with: "")
            } else {
                suggestedFilename = url.lastPathComponent.isEmpty ? "documento.pdf" : url.lastPathComponent
            }

            // Descargar el PDF
            URLSession.shared.downloadTask(with: url) { tempURL, _, error in
                guard let tempURL = tempURL, error == nil else { return }

                // Crear una ruta temporal con el nombre correcto
                let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)

                // Mover el archivo al destino con el nombre deseado
                try? FileManager.default.removeItem(at: destinationURL)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                } catch {
                    print("Error moviendo archivo:", error)
                    return
                }

                DispatchQueue.main.async {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                        let activityVC = UIActivityViewController(activityItems: [destinationURL], applicationActivities: nil)
                        rootVC.present(activityVC, animated: true)
                    } else {
                        self.present(UIActivityViewController(activityItems: [destinationURL], applicationActivities: nil), animated: true)
                    }
                }
            }.resume()

            return
        }

        decisionHandler(.allow)
    }



    // MARK: - Soporte para input type="file"
    @available(iOS 14.0, *)
    @MainActor
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: Any,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        self.imagePickerCompletion = completionHandler

        let picker = UIImagePickerController()
        picker.delegate = self

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }

        self.present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: nil)

        if let imageURL = info[.imageURL] as? URL {
            imagePickerCompletion?([imageURL])
        } else if let image = info[.originalImage] as? UIImage {
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: tmpURL)
                imagePickerCompletion?([tmpURL])
            } else {
                imagePickerCompletion?(nil)
            }
        } else {
            imagePickerCompletion?(nil)
        }
        imagePickerCompletion = nil
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
        imagePickerCompletion?(nil)
        imagePickerCompletion = nil
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = progressView.progress == 1
        }
    }

    deinit {
        webView.removeObserver(self, forKeyPath: "estimatedProgress")
        NotificationCenter.default.removeObserver(self)
    }
}
