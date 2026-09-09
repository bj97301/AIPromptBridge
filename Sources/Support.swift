import AppKit
import ApplicationServices
import Foundation
import Darwin

typealias JSON = [String: Any]

let bridgeID = "io.github.bj97301.aipromptbridge"
let socketDirectory = "/tmp/\(bridgeID)-\(getuid())"
let socketPath = socketDirectory + "/control.sock"

func failure(_ code: String, _ message: String, extra: JSON = [:]) -> JSON {
    var result = extra
    result["status"] = code
    result["message"] = message
    return result
}

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

func axString(_ element: AXUIElement, _ attribute: String) -> String {
    axValue(element, attribute) as? String ?? ""
}

func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
    axValue(element, attribute) as? Bool ?? false
}

func axElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
    axValue(element, attribute) as? [AXUIElement] ?? []
}

func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = axValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
}

func axActions(_ element: AXUIElement) -> [String] {
    var value: CFArray?
    guard AXUIElementCopyActionNames(element, &value) == .success else { return [] }
    return value as? [String] ?? []
}

func axSettable(_ element: AXUIElement) -> Bool {
    var value = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &value) == .success && value.boolValue
}

func axFrame(_ element: AXUIElement) -> JSON {
    var point = CGPoint.zero
    var size = CGSize.zero
    if let raw = axValue(element, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
        AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgPoint, &point)
    }
    if let raw = axValue(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
        AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgSize, &size)
    }
    return ["x": point.x, "y": point.y, "width": size.width, "height": size.height]
}

func axError(_ error: AXError) -> JSON {
    if error == .cannotComplete {
        return failure("unverified", "The app did not confirm the Accessibility request. Inspect fresh state before retrying.", extra: ["ax_error": error.rawValue])
    }
    return failure("user_interaction_required", "macOS or the target app did not allow this Accessibility operation. Complete it in the target app.", extra: ["ax_error": error.rawValue])
}

final class LocalServer {
    private var listener: Int32 = -1
    private var lockFD: Int32 = -1
    var handle: ((JSON, @escaping (JSON) -> Void) -> Void)?

    func start() throws {
        if mkdir(socketDirectory, 0o700) != 0 && errno != EEXIST { throw serverError("Cannot create private socket directory") }
        var info = stat()
        guard lstat(socketDirectory, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else {
            throw serverError("Socket directory must be owned by this account with mode 0700")
        }
        lockFD = Darwin.open(socketDirectory + "/instance.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0, fstat(lockFD, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            throw serverError("Another AIPromptBridge instance is running, or its lock is unavailable")
        }
        if lstat(socketPath, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else {
                throw serverError("Unexpected file at socket path")
            }
            unlink(socketPath)
        }
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw serverError("Cannot create local socket") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw serverError("Socket path is too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(listener, 8) == 0 else {
            throw serverError("Cannot bind local socket")
        }
        let fd = listener
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let self = self {
                let client = accept(fd, nil, nil)
                if client < 0 { if errno == EINTR { continue }; break }
                // One bounded connection at a time limits resource use. UI work remains on the main queue.
                self.receive(client)
            }
        }
    }

    private func receive(_ fd: Int32) {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { close(fd); return }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= 65_536 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { close(fd); return }
            data.append(contentsOf: buffer.prefix(count))
            if data.contains(10) { break }
        }
        guard data.count <= 65_536, let newline = data.firstIndex(of: 10), newline == data.count - 1,
              let request = try? JSONSerialization.jsonObject(with: data[..<newline]) as? JSON,
              let deadline = request["deadline"] as? Double, deadline > Date().timeIntervalSince1970,
              deadline <= Date().timeIntervalSince1970 + 120 else {
            send(failure("invalid_request", "Expected one JSON request with a current deadline."), to: fd)
            return
        }
        data.resetBytes(in: data.startIndex..<data.endIndex)
        let done = DispatchSemaphore(value: 0)
        let replyLock = NSLock()
        var didReply = false
        let finish: (JSON) -> Void = { [weak self] response in
            replyLock.lock()
            let shouldSend = !didReply
            didReply = true
            replyLock.unlock()
            guard shouldSend else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                if let self = self { self.send(response, to: fd) } else { close(fd) }
                done.signal()
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard deadline > Date().timeIntervalSince1970, let handler = self?.handle else {
                finish(failure("expired", "Request expired before execution."))
                return
            }
            handler(request, finish)
        }
        if done.wait(timeout: .now() + 30) == .timedOut {
            finish(failure("unverified", "The request did not finish in time. Inspect fresh state before retrying."))
        }
    }

    private func send(_ response: JSON, to fd: Int32) {
        defer { close(fd) }
        guard var data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) else { return }
        data.append(10)
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count <= 0 { break }
                offset += count
            }
        }
    }

    private func serverError(_ text: String) -> NSError {
        NSError(domain: bridgeID, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: text])
    }
}
