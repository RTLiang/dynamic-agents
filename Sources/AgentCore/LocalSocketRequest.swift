import Foundation
import Darwin

public enum LocalSocketRequest {
    public static func send(path: String, payload: Data, timeout: TimeInterval = 4) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try exchange(path: path, payload: payload, timeout: timeout)
        }.value
    }

    private static func exchange(path: String, payload: Data, timeout: TimeInterval) throws -> Data {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path), !path.utf8.contains(0) else {
            throw HerdrError.message(L10n.text("The herdr socket path is invalid or too long."))
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw socketError() }
        defer { close(descriptor) }
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal))) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else { throw socketError() }
        let deadline = Date.now.addingTimeInterval(timeout)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { throw socketError() }
            try wait(descriptor, events: Int16(POLLOUT), until: deadline)
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout.size(ofValue: error))
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { throw socketError() }
            guard error == 0 else { throw socketError(error) }
        }
        var request = payload
        request.append(10)
        var written = 0
        while written < request.count {
            try wait(descriptor, events: Int16(POLLOUT), until: deadline)
            let count = request.withUnsafeBytes { bytes in
                Darwin.send(descriptor, bytes.baseAddress!.advanced(by: written), request.count - written, 0)
            }
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            guard count > 0 else { throw socketError() }
            written += count
        }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while response.count <= 1_048_576 {
            try wait(descriptor, events: Int16(POLLIN), until: deadline)
            let count = recv(descriptor, &buffer, buffer.count, 0)
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            guard count > 0 else {
                throw HerdrError.message(L10n.text("herdr closed the connection before completing its response."))
            }
            response.append(contentsOf: buffer.prefix(count))
            guard response.count <= 1_048_576 else {
                throw HerdrError.message(L10n.text("The herdr response exceeded the size limit."))
            }
            if let end = response.firstIndex(of: 10) { return Data(response[..<end]) }
        }
        throw HerdrError.message(L10n.text("The herdr response exceeded the size limit."))
    }

    private static func wait(_ descriptor: Int32, events: Int16, until deadline: Date) throws {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw timeoutError() }
            var descriptor = pollfd(fd: descriptor, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(remaining * 1000 + 1, Double(Int32.max))))
            if result < 0, errno == EINTR { continue }
            guard result >= 0 else { throw socketError() }
            guard result > 0 else { throw timeoutError() }
            if descriptor.revents & events != 0 { return }
            throw HerdrError.message(L10n.text("The herdr socket connection was interrupted."))
        }
    }

    private static func timeoutError() -> HerdrError {
        .message(L10n.text("The herdr request timed out. Refresh the integration status before retrying."))
    }

    private static func socketError(_ code: Int32 = errno) -> HerdrError {
        .message(L10n.format("Unable to connect to the local herdr socket: %@", String(cString: strerror(code))))
    }
}
