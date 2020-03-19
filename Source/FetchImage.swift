import SwiftUI
import Nuke

/// - WARNING: This is an API preview. It is not battle-tested yet and might signficantly change in the future.
public final class FetchImage: ObservableObject, Identifiable {
    /// The original request.
    public let request: ImageRequest

    /// The request to be performed if the original request fails with
    /// `networkUnavailableReason` `.constrained` (low data mode).
    public let lowDataRequest: ImageRequest?

    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    @Published public private(set) var image: PlatformImage?

    /// Returns an error if the previous attempt to fetch the most recent attempt
    /// to load the image failed with an error.
    @Published public private(set) var error: Error?

    /// Returns `true` if the image is being loaded.
    @Published public private(set) var isLoading: Bool = false

    public struct Progress {
        /// The number of bytes that the task has received.
        public let completed: Int64

        /// A best-guess upper bound on the number of bytes the client expects to send.
        public let total: Int64
    }

    /// The progress of the image download.
    @Published public var progress = Progress(completed: 0, total: 0)

    /// Updates the priority of the task, even if the task is already running.
    public var priority: ImageRequest.Priority {
        didSet { task?.priority = priority }
    }

    private let pipeline: ImagePipeline
    private var task: ImageTask?
    private var loadedImageQuality: ImageQuality? = nil

    private enum ImageQuality {
        case regular, low
    }

    deinit {
        cancel()
    }

    /// Initializes the fetch request and immediately start loading.
    public init(request: ImageRequest, lowDataRequest: ImageRequest? = nil, pipeline: ImagePipeline = .shared) {
        self.request = request
        self.lowDataRequest = lowDataRequest
        self.priority = request.priority
        self.pipeline = pipeline

        self.fetch()
    }

    /// Initializes the fetch request and immediately start loading.
    public convenience init(url: URL, pipeline: ImagePipeline = .shared) {
        self.init(request: ImageRequest(url: url), pipeline: pipeline)
    }

    /// A convenience initializer that fetches the image with a regular URL with
    /// constrained network access disabled, and if the download fails because of
    /// the constrained network access, uses a low data URL instead.
    public convenience init(regularUrl: URL, lowDataUrl: URL, pipeline: ImagePipeline = .shared) {
        var request = URLRequest(url: regularUrl)
        request.allowsConstrainedNetworkAccess = false

        self.init(request: ImageRequest(urlRequest: request), lowDataRequest: ImageRequest(url: lowDataUrl), pipeline: pipeline)
    }

    /// Starts loading the image if not already loaded and the download is not
    /// already in progress.
    ///
    /// - note: Low Data Mode. If the `lowDataRequest` is provided and the regular
    /// request fails because of the constrained network access, the fetcher tries
    /// to download the low-quality image. The fetcher always tries to get the high
    /// quality image. If the first attempt fails, the next time you call `fetch`,
    /// it is going to attempt to fetch the regular quality image again.
    public func fetch() {
        guard !isLoading, loadedImageQuality != .regular else {
            return
        }

        error = nil

        // Try to display the regular image if it is available in memory cache
        if let response = pipeline.cachedResponse(for: request) {
            (image, loadedImageQuality) = (response.image, .regular)
            return // Nothing to do
        }

        // Try to display the low data image and retry loading the regular image
        if let response = lowDataRequest.flatMap(pipeline.cachedResponse(for:)) {
            (image, loadedImageQuality) = (response.image, .low)
        }

        isLoading = true
        loadImage(request: request, quality: .regular)
    }

    private func loadImage(request: ImageRequest, quality: ImageQuality) {
        progress = Progress(completed: 0, total: 0)

        task = pipeline.loadImage(
            with: request,
            progress: { [weak self] response, completed, total in
                guard let self = self else { return }

                self.progress = Progress(completed: completed, total: total)

                if let image = response?.image {
                    self.image = image // Display progressively decoded image
                }
            },
            completion: { [weak self] in
                self?.didFinishRequest(result: $0, quality: quality)
            }
        )

        if priority != request.priority {
            task?.priority = priority
        }
    }

    private func didFinishRequest(result: Result<ImageResponse, ImagePipeline.Error>, quality: ImageQuality) {
        task = nil

        switch result {
        case let .success(response):
            isLoading = false
            (image, loadedImageQuality) = (response.image, quality)
        case let .failure(error):
            // If the regular request fails because of the low data mode,
            // use an alternative source.
            if quality == .regular, error.isConstrainedNetwork, let request = self.lowDataRequest {
                if loadedImageQuality == .low {
                    isLoading = false // Low-quality image already loaded
                } else {
                    loadImage(request: request, quality: .low)
                }
            } else {
                self.error = error
                isLoading = false
            }
        }
    }

    /// Marks the request as being cancelled.
    public func cancel() {
        task?.cancel() // Guarantees that no more callbacks are will be delivered
        task = nil
        isLoading = false
    }
}

private extension ImagePipeline.Error {
    var isConstrainedNetwork: Bool {
        if case let .dataLoadingFailed(error) = self,
            (error as? URLError)?.networkUnavailableReason == .constrained {
            return true
        }
        return false
    }
}

public extension FetchImage {
    var view: SwiftUI.Image? {
        #if os(macOS)
        return image.map(Image.init(nsImage:))
        #else
        return image.map(Image.init(uiImage:))
        #endif
    }
}
