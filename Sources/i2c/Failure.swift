//
//  Failure.swift
//
//  Copyright © 2025 Nick Nallick. Licensed under the MIT License.
//

extension I2CBus {

    public struct Failure: Error, CustomStringConvertible {

        public enum ErrorType: Sendable {
            case open
            case read
            case write
            case ioControl
        }

        public let type: ErrorType
        public let detail: String

        #if TRACE_I2C_ERRORS

        public let functionTrace: StaticString
        public let fileTrace: StaticString
        public let lineTrace: UInt

        public var description: String {
            let filename: String.SubSequence = fileTrace.description.split(separator: "/").last ?? "<unknown>"
            return "\(detail), in \(functionTrace) at line \(lineTrace) of \(filename)"
        }

        public init(_ type: ErrorType, detail: String,
                    function: StaticString = #function, file: StaticString = #file, line: UInt = #line) {
            self.type = type
            self.detail = detail
            self.functionTrace = function
            self.fileTrace = file
            self.lineTrace = line
        }

        #else

        public var description: String {
            "\(detail) [\(type)]"
        }

        public init(_ type: ErrorType, detail: String) {
            self.type = type
            self.detail = detail
        }

        #endif
    }
}
