import Foundation

enum TopologyValidationErrorCode: String, Equatable {
    case missingNodeIdentifier
    case unknownNodeKind
    case nodeNotFound
    case malformedActionPayload
    case invalidPortIdentifier
    case noFreePort
    case duplicateLink
    case incompatibleEndpoint
    case connectionSourceNotSelected
    case selfConnectionNotAllowed
}
