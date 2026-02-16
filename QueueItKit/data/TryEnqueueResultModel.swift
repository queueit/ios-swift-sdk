struct TryEnqueueResult: Sendable {
    public let result: QueueTryPassResult?
    public let error: QueueError?
    public let errorMessage: String?

    public init(result: QueueTryPassResult? = nil, error: QueueError? = nil, errorMessage: String? = nil) {
        self.result = result
        self.error = error
        self.errorMessage = errorMessage
    }
}
