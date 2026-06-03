//
//  ExternalEditSession.swift
//  PromptTap
//
//  Created by OpenAI on 2026/05/19.
//

import Foundation

enum ExternalEditCompletionState: String, Codable {
    case pending
    case saved
    case unchanged
    case discarded
    case cancelled
    case error
}

struct ExternalEditSession: Identifiable {
    let sessionId: String
    let filePath: String
    let originalMtime: Date?
    let originalExists: Bool
    let originalText: String
    let newline: String
    var completionState: ExternalEditCompletionState
    let waitingClient: PromptTapIPCWaitingClient?

    var id: String {
        sessionId
    }
}

struct ExternalEditOpenRequest: Decodable {
    let type: String
    let sessionId: String
    let filePath: String
    let wait: Bool
}

struct ExternalEditSessionCompleteResponse: Encodable {
    let type: String
    let sessionId: String
    let result: ExternalEditCompletionState
    let exitCode: Int
    let message: String?

    init(sessionId: String, result: ExternalEditCompletionState, exitCode: Int, message: String? = nil) {
        self.type = "session-complete"
        self.sessionId = sessionId
        self.result = result
        self.exitCode = exitCode
        self.message = message
    }
}

final class PromptTapIPCWaitingClient: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let lock = NSLock()
    private var isCompleted = false

    init(fileDescriptor: Int32) {
        self.fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
    }

    func complete(_ response: ExternalEditSessionCompleteResponse) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        lock.unlock()

        do {
            let data = try JSONEncoder().encode(response)
            fileHandle.write(data)
            fileHandle.write(Data("\n".utf8))
        } catch {
            let fallback = #"{"type":"session-complete","sessionId":"\#(response.sessionId)","result":"error","exitCode":1}"#
            fileHandle.write(Data((fallback + "\n").utf8))
        }
        try? fileHandle.close()
    }
}
