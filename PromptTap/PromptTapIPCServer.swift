//
//  PromptTapIPCServer.swift
//  PromptTap
//
//  Created by OpenAI on 2026/05/19.
//

import Foundation

final class PromptTapIPCServer {
    private let socketPath: String
    private weak var model: PromptTapModel?
    private let listenQueue = DispatchQueue(label: "work.spinners.PromptTap.ipc.listen", qos: .userInitiated)
    private let clientQueue = DispatchQueue(label: "work.spinners.PromptTap.ipc.client", qos: .userInitiated, attributes: .concurrent)
    private var serverSocket: Int32 = -1
    private var isRunning = false

    init(model: PromptTapModel) {
        self.model = model
        self.socketPath = Self.defaultSocketPath
    }

    static var defaultSocketPath: String {
        "/tmp/prompttap-\(getuid()).sock"
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        listenQueue.async { [weak self] in
            self?.listen()
        }
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(socketPath)
    }

    private func listen() {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            perror("PromptTap IPC socket")
            return
        }
        serverSocket = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard socketPath.utf8.count < maxPathLength else {
            close(fd)
            return
        }

        _ = withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
            socketPath.withCString { pathPointer in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), pathPointer, maxPathLength)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            perror("PromptTap IPC bind")
            close(fd)
            return
        }

        chmod(socketPath, 0o600)

        guard Foundation.listen(fd, SOMAXCONN) == 0 else {
            perror("PromptTap IPC listen")
            close(fd)
            return
        }

        while isRunning {
            let client = accept(fd, nil, nil)
            guard client >= 0 else {
                if isRunning {
                    perror("PromptTap IPC accept")
                }
                continue
            }

            clientQueue.async { [weak self] in
                self?.handleClient(client)
            }
        }
    }

    private func handleClient(_ client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else {
            close(client)
            return
        }

        let data = Data(buffer.prefix(count))
        do {
            let request = try JSONDecoder().decode(ExternalEditOpenRequest.self, from: data)
            guard request.type == "open-session" else {
                sendImmediateError(client: client, sessionId: request.sessionId, message: "Unsupported request type")
                return
            }

            let waitingClient = request.wait ? PromptTapIPCWaitingClient(fileDescriptor: client) : nil
            Task { @MainActor [weak self] in
                self?.model?.openExternalEditSession(request, waitingClient: waitingClient)
            }

            if !request.wait {
                let response = ExternalEditSessionCompleteResponse(
                    sessionId: request.sessionId,
                    result: .saved,
                    exitCode: 0,
                    message: "opened"
                )
                send(response, to: client)
            }
        } catch {
            sendImmediateError(client: client, sessionId: "unknown", message: error.localizedDescription)
        }
    }

    private func sendImmediateError(client: Int32, sessionId: String, message: String) {
        let response = ExternalEditSessionCompleteResponse(
            sessionId: sessionId,
            result: .error,
            exitCode: 1,
            message: message
        )
        send(response, to: client)
    }

    private func send(_ response: ExternalEditSessionCompleteResponse, to client: Int32) {
        do {
            let data = try JSONEncoder().encode(response)
            data.withUnsafeBytes { bytes in
                _ = write(client, bytes.baseAddress, bytes.count)
            }
            _ = write(client, "\n", 1)
        } catch {
            let fallback = #"{"type":"session-complete","sessionId":"\#(response.sessionId)","result":"error","exitCode":1}"#
            fallback.withCString { pointer in
                _ = write(client, pointer, strlen(pointer))
            }
            _ = write(client, "\n", 1)
        }
        close(client)
    }
}
