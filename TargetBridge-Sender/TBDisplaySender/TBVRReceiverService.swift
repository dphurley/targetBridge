import AppKit
import ApplicationServices
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Network
import UniformTypeIdentifiers

struct TBVRRemoteInput: Decodable {
    let kind: String
    let x: Double?
    let y: Double?
    let dx: Double?
    let dy: Double?
    let button: String?
    let pressed: Bool?
}

/// A lightweight browser receiver for standalone headsets. It deliberately uses
/// HTTP/MJPEG so Quest 1 users do not need a companion APK or developer mode.
// Network callbacks stay on `queue`; UI state is dispatched back to the main queue.
final class TBVRReceiverService: ObservableObject, @unchecked Sendable {
    private static let port = NWEndpoint.Port(rawValue: 51239)!
    private let queue = DispatchQueue(label: "com.targetbridge.vr-receiver")
    private let jpegContext = CIContext(options: [.useSoftwareRenderer: false])
    private var listener: NWListener?
    private var captureTimer: DispatchSourceTimer?
    private var streamClients: [UUID: NWConnection] = [:]
    private var inputHandler: ((TBVRRemoteInput) -> Void)?
    private var accessToken = ""

    @Published private(set) var isRunning = false
    @Published private(set) var address = ""
    @Published private(set) var errorMessage: String?

    var browserURL: String {
        guard !address.isEmpty else { return "" }
        return "http://\(address):\(Self.port.rawValue)/?token=\(accessToken)"
    }

    func start(inputHandler: @escaping (TBVRRemoteInput) -> Void, requiresMacPermissions: Bool = true) {
        guard !isRunning else { return }
        guard !requiresMacPermissions || CGPreflightScreenCaptureAccess() else {
            errorMessage = "Screen Recording permission is required to start Receiver VR."
            return
        }
        guard !requiresMacPermissions || AXIsProcessTrusted() else {
            errorMessage = "Accessibility permission is required to control this Mac from Receiver VR."
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: Self.port)
            accessToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            self.inputHandler = inputHandler
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        self?.address = Self.localIPv4Address() ?? ""
                        self?.errorMessage = nil
                        self?.isRunning = true
                    }
                case let .failed(error):
                    DispatchQueue.main.async {
                        self?.errorMessage = "Receiver VR could not start: \(error.localizedDescription)"
                        self?.stop()
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
            startCaptureTimer()
        } catch {
            errorMessage = "Receiver VR could not reserve its local connection."
        }
    }

    func stop() {
        captureTimer?.cancel()
        captureTimer = nil
        listener?.cancel()
        listener = nil
        streamClients.values.forEach { $0.cancel() }
        streamClients.removeAll()
        inputHandler = nil
        accessToken = ""
        isRunning = false
        address = ""
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var received = buffer
            if let data { received.append(data) }
            if let request = Self.parseRequest(from: received) {
                if request.body.count < request.contentLength, !complete, error == nil {
                    self.receiveRequest(on: connection, buffer: received)
                    return
                }
                self.handle(request, on: connection)
                return
            }
            if !complete, error == nil, received.count < 65_536 {
                self.receiveRequest(on: connection, buffer: received)
            } else {
                connection.cancel()
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        guard request.token == accessToken, !accessToken.isEmpty else {
            respond(Data("Receiver VR pairing code required".utf8), contentType: "text/plain", status: "403 Forbidden", on: connection)
            return
        }
        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            respond(htmlPage.data(using: .utf8)!, contentType: "text/html; charset=utf-8", on: connection)
        case ("GET", "/stream.mjpg"):
            let header = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=targetbridge\r\nCache-Control: no-store\r\nConnection: keep-alive\r\n\r\n"
            connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
            streamClients[UUID()] = connection
        case ("POST", "/input"):
            if let event = try? JSONDecoder().decode(TBVRRemoteInput.self, from: request.body) {
                let handler = inputHandler
                DispatchQueue.main.async { handler?(event) }
            }
            respond(Data("{}".utf8), contentType: "application/json", on: connection)
        case ("GET", "/health"):
            respond(Data("{\"status\":\"ok\"}".utf8), contentType: "application/json", on: connection)
        default:
            respond(Data("Not found".utf8), contentType: "text/plain", status: "404 Not Found", on: connection)
        }
    }

    private func respond(_ body: Data, contentType: String, status: String = "200 OK", on connection: NWConnection) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func startCaptureTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(67), leeway: .milliseconds(8))
        timer.setEventHandler { [weak self] in self?.broadcastFrame() }
        captureTimer = timer
        timer.resume()
    }

    private func broadcastFrame() {
        guard !streamClients.isEmpty, let jpeg = makeJPEGFrame() else { return }
        var part = Data("--targetbridge\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
        part.append(jpeg)
        part.append(Data("\r\n".utf8))
        for (id, connection) in streamClients {
            connection.send(content: part, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.streamClients.removeValue(forKey: id) }
            })
        }
    }

    private func makeJPEGFrame() -> Data? {
        guard let sourceImage = CGDisplayCreateImage(CGMainDisplayID()) else { return nil }
        let source = CIImage(cgImage: sourceImage)
        let scale = min(1, 1440 / max(source.extent.width, 1))
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = jpegContext.createCGImage(scaled, from: scaled.extent) else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.68] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func parseRequest(from data: Data) -> HTTPRequest? {
        guard let delimiter = data.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: data[..<delimiter.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first?.split(separator: " "), requestLine.count >= 2 else { return nil }
        let target = String(requestLine[1])
        let components = URLComponents(string: "http://targetbridge.local\(target)")
        let headers = Dictionary(uniqueKeysWithValues: lines.dropFirst().compactMap { line -> (String, String)? in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            return (line[..<separator].lowercased(), line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces))
        })
        let bodyStart = delimiter.upperBound
        return HTTPRequest(
            method: String(requestLine[0]),
            path: components?.path ?? target,
            body: Data(data[bodyStart...]),
            contentLength: Int(headers["content-length"] ?? "0") ?? 0,
            token: components?.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
        )
    }

    private static func localIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  let name = interface.ifa_name.map({ String(cString: $0) }),
                  name.hasPrefix("en")
            else { continue }
            var address = interface.ifa_addr.pointee
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(&address, socklen_t(interface.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(cString: host)
        }
        return nil
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
    let contentLength: Int
    let token: String
}

private let htmlPage = #"""
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><title>TargetBridge VR</title><style>
*{box-sizing:border-box}body{margin:0;background:#11151d;color:#f4f6f8;font:16px -apple-system,BlinkMacSystemFont,sans-serif;overflow:hidden}header{height:52px;display:flex;align-items:center;justify-content:space-between;padding:0 18px;background:#18212c;border-bottom:1px solid #344254}strong{font-size:18px}small{color:#a7b3c2}.screen{height:calc(100vh - 142px);display:flex;align-items:center;justify-content:center;background:#070a0f}.screen img{max-width:100%;max-height:100%;object-fit:contain;touch-action:none}.controls{height:90px;display:flex;align-items:center;justify-content:center;gap:10px;background:#18212c;border-top:1px solid #344254}button{min-width:58px;padding:11px;border:1px solid #52647a;border-radius:12px;background:#263548;color:white;font-size:20px}button:active{background:#0d8a70}.hint{position:fixed;left:12px;bottom:97px;color:#a7b3c2;font-size:12px;background:#111a;padding:6px;border-radius:8px}</style></head><body>
<header><strong>TargetBridge VR</strong><small id="status">Connected locally</small></header><main class="screen"><img id="desktop" alt="Mac desktop"></main><div class="hint">Point at the desktop and press to click. Controls move or scroll when the browser does not expose the controller joystick.</div><nav class="controls"><button data-move="0,-1">↑</button><button data-move="-1,0">←</button><button data-move="0,1">↓</button><button data-move="1,0">→</button><button data-scroll="1">Scroll ↑</button><button data-scroll="-1">Scroll ↓</button></nav>
<script>const key=location.search,image=document.querySelector('#desktop');image.src='/stream.mjpg'+key;const post=e=>fetch('/input'+key,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(e)}).catch(()=>{});let last=0,down=false;function point(e){const r=image.getBoundingClientRect();return{x:Math.max(0,Math.min(1,(e.clientX-r.left)/r.width)),y:Math.max(0,Math.min(1,(e.clientY-r.top)/r.height))}}image.addEventListener('pointermove',e=>{if(performance.now()-last<32)return;last=performance.now();post({kind:'pointer',...point(e)})});image.addEventListener('pointerdown',e=>{down=true;image.setPointerCapture(e.pointerId);post({kind:'button',button:'left',pressed:true})});image.addEventListener('pointerup',e=>{if(down)post({kind:'button',button:'left',pressed:false});down=false});document.querySelectorAll('[data-move]').forEach(b=>b.addEventListener('pointerdown',()=>{const [dx,dy]=b.dataset.move.split(',').map(Number);post({kind:'move',dx:dx*18,dy:dy*18})}));document.querySelectorAll('[data-scroll]').forEach(b=>b.addEventListener('pointerdown',()=>post({kind:'scroll',dy:Number(b.dataset.scroll)*3})));setInterval(()=>{for(const p of navigator.getGamepads?.()||[]){if(!p)continue;const[x=0,y=0]=p.axes;if(Math.abs(x)>.15||Math.abs(y)>.15)post({kind:'move',dx:x*12,dy:y*12});if(p.buttons[0]?.pressed&&!down){down=true;post({kind:'button',button:'left',pressed:true})}if(!p.buttons[0]?.pressed&&down){down=false;post({kind:'button',button:'left',pressed:false})}}},40);</script></body></html>
"""#
