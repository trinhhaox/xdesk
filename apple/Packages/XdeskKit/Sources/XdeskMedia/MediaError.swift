import CoreFoundation

/// Lỗi tầng media (mã `OSStatus` giữ nguyên để chẩn đoán).
public enum MediaError: Error, Sendable, Equatable {
    case invalidSettings(String)
    case sessionCreationFailed(Int32)
    case propertyRejected(name: String, status: Int32)
    case encodeFailed(Int32)
    case malformedNAL(String)
    case missingParameterSets
    case formatDescriptionFailed(Int32)
    case sampleBufferFailed(Int32)
}
