import CoreGraphics
import Foundation
import VisorCore

enum FinderScriptingError: Error, Equatable {
    /// Automation → Finder denied (-1743) or not yet determined and refused.
    case notAuthorized
    /// Finder did not answer within the 2 s reply timeout (-1712).
    case timeout
    case failed(code: Int, message: String)
    case unexpectedReply
}

/// Apple Events to Finder. Every call runs on one serial background queue and never on the main thread.
protocol FinderScripting: Sendable {
    /// `make new Finder window to home`, sets `bounds` to `frame` (global top-left coordinates), returns the AE id
    /// (== CGWindowID).
    func createWindow(frame: CGRect) async throws -> Int
    /// All Finder windows (every tab is its own window) with bounds and target, for re-attach.
    func allWindows() async throws -> [FinderWindowCandidate]
    /// Target folder of window `id` as a file URL, or `nil` if it has no file-system target (e.g. Recents).
    func targetURL(ofWindow id: Int) async throws -> URL?
    /// `name` of window `id` (equals the AX title of the window).
    func name(ofWindow id: Int) async throws -> String
}

final class LiveFinderScripting: FinderScripting, @unchecked Sendable {
    /// Handlers compiled once. `with timeout of 2 seconds` bounds every Finder reply.
    private static let source = """
    on createwindow(l, t, r, b)
        with timeout of 2 seconds
            tell application "Finder"
                set w to make new Finder window to home
                set bounds of w to {l, t, r, b}
                return id of w
            end tell
        end timeout
    end createwindow

    on allwindows()
        with timeout of 2 seconds
            tell application "Finder"
                set out to {}
                repeat with w in every Finder window
                    set p to ""
                    try
                        set p to POSIX path of (target of w as alias)
                    end try
                    set end of out to {id of w, bounds of w, p}
                end repeat
                return out
            end tell
        end timeout
    end allwindows

    on targetpath(i)
        with timeout of 2 seconds
            tell application "Finder"
                try
                    return POSIX path of (target of Finder window id i as alias)
                end try
                return ""
            end tell
        end timeout
    end targetpath

    on windowname(i)
        with timeout of 2 seconds
            tell application "Finder" to return name of Finder window id i
        end timeout
    end windowname
    """

    private let queue = DispatchQueue(label: "io.github.findervisor.finder-scripting", qos: .userInitiated)
    /// Only touched on `queue`.
    private var script: NSAppleScript?

    func createWindow(frame: CGRect) async throws -> Int {
        let args = [frame.minX, frame.minY, frame.maxX, frame.maxY].map { Int32($0.rounded()) }
        let reply = try await call("createwindow", args.map { NSAppleEventDescriptor(int32: $0) })
        guard reply.descriptorType == typeSInt32 || reply.descriptorType == typeSInt16 else {
            throw FinderScriptingError.unexpectedReply
        }
        return Int(reply.int32Value)
    }

    func allWindows() async throws -> [FinderWindowCandidate] {
        let reply = try await call("allwindows", [])
        guard reply.numberOfItems > 0 else { return [] }
        return (1...reply.numberOfItems).compactMap { index in
            guard let item = reply.atIndex(index), item.numberOfItems == 3,
                  let id = item.atIndex(1)?.int32Value,
                  let bounds = item.atIndex(2), bounds.numberOfItems == 4 else { return nil }
            let edges = (1...4).map { CGFloat(bounds.atIndex($0)?.int32Value ?? 0) }
            let frame = CGRect(x: edges[0], y: edges[1], width: edges[2] - edges[0], height: edges[3] - edges[1])
            return FinderWindowCandidate(aeID: Int(id), frame: frame, targetURL: Self.url(item.atIndex(3)?.stringValue))
        }
    }

    func targetURL(ofWindow id: Int) async throws -> URL? {
        Self.url(try await call("targetpath", [NSAppleEventDescriptor(int32: Int32(id))]).stringValue)
    }

    func name(ofWindow id: Int) async throws -> String {
        guard let name = try await call("windowname", [NSAppleEventDescriptor(int32: Int32(id))]).stringValue else {
            throw FinderScriptingError.unexpectedReply
        }
        return name
    }

    private static func url(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Runs a handler of the compiled script on `queue`. Replies are copied into plain values before leaving the
    /// queue's closure only through `SendableReply`.
    private func call(_ handler: String, _ args: [NSAppleEventDescriptor]) async throws -> NSAppleEventDescriptor {
        let reply: SendableReply = try await withCheckedThrowingContinuation { continuation in
            let argsBox = SendableReply(descriptor: Self.list(args))
            queue.async {
                continuation.resume(with: Result { SendableReply(descriptor: try self.run(handler, argsBox.descriptor)) })
            }
        }
        return reply.descriptor
    }

    private static func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (offset, item) in items.enumerated() { list.insert(item, at: offset + 1) }
        return list
    }

    /// Must run on `queue`.
    private func run(_ handler: String, _ args: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        dispatchPrecondition(condition: .onQueue(queue))
        let script = try compiledScript()
        // kASAppleScriptSuite 'ascr' / kASSubroutineEvent 'psbr' / keyASSubroutineName 'snam'.
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(0x6173_6372),
            eventID: AEEventID(0x7073_6272),
            targetDescriptor: NSAppleEventDescriptor.currentProcess(),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(0x736E_616D))
        event.setParam(args, forKeyword: keyDirectObject)
        var errorInfo: NSDictionary?
        let reply = script.executeAppleEvent(event, error: &errorInfo)
        if let errorInfo { throw Self.error(from: errorInfo) }
        return reply
    }

    private func compiledScript() throws -> NSAppleScript {
        if let script { return script }
        guard let compiled = NSAppleScript(source: Self.source) else {
            throw FinderScriptingError.failed(code: 0, message: "could not create script")
        }
        var errorInfo: NSDictionary?
        guard compiled.compileAndReturnError(&errorInfo) else {
            throw errorInfo.map(Self.error(from:)) ?? FinderScriptingError.failed(code: 0, message: "compile failed")
        }
        script = compiled
        return compiled
    }

    private static func error(from info: NSDictionary) -> FinderScriptingError {
        let code = (info[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        switch code {
        case -1743, -1744: return .notAuthorized
        case -1712: return .timeout
        default: return .failed(code: code, message: info[NSAppleScript.errorMessage] as? String ?? "")
        }
    }
}

/// Carries an Apple Event descriptor across the scripting queue boundary. Descriptors are never mutated after
/// being handed over.
private struct SendableReply: @unchecked Sendable {
    let descriptor: NSAppleEventDescriptor
}
