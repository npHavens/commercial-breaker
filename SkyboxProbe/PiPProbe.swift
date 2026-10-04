import AVKit
import Combine
import MediaPlayer
import UIKit

/// Tests actual app execution separately from system-managed video playback.
final class PiPProbe: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var status = "Select Prepare video, then Start PiP"
    @Published private(set) var ready = false
    @Published private(set) var active = false
    @Published private(set) var running = false
    @Published private(set) var heartbeatCount = 0
    @Published private(set) var networkCount = 0
    @Published private(set) var lastGap: TimeInterval = 0

    let player = AVQueuePlayer()
    let playerLayer = AVPlayerLayer()
    var onEvent: ((String) -> Void)?
    private var controller: AVPictureInPictureController?
    private var nowPlaying: MPNowPlayingSession?
    private var looper: AVPlayerLooper?
    private var observations: [NSKeyValueObservation] = []
    private var interruptionObserver: NSObjectProtocol?
    private var timer: Timer?
    private var request: URLSessionDataTask?
    private var generation = UUID()
    private var previousTick: TimeInterval?
    private var elapsed: TimeInterval = 0
    private var scene = "active"
    private let network = URLSession(configuration: .ephemeral)

    override init() {
        super.init()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        player.isMuted = true
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            self?.onEvent?("PiP audio interruption: \(notification.userInfo ?? [:])")
        }
    }

    deinit {
        timer?.invalidate()
        request?.cancel()
        network.invalidateAndCancel()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func prepare() {
        guard !running else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let url = Bundle.main.url(forResource: "PiPTest", withExtension: "mp4") else {
            update("PiP unsupported or test video missing")
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audio.setActive(true)
        } catch { update("Audio session error: \(error as NSError)"); return }

        if controller == nil {
            guard let pip = AVPictureInPictureController(playerLayer: playerLayer) else {
                update("Could not create PiP controller")
                return
            }
            controller = pip
            pip.delegate = self
            nowPlaying = MPNowPlayingSession(players: [player])
            nowPlaying?.nowPlayingInfoCenter.nowPlayingInfo = [MPMediaItemPropertyTitle: "Skybox PiP test"]
            observations = [
                pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
                    DispatchQueue.main.async { self?.ready = pip.isPictureInPicturePossible }
                },
                pip.observe(\.isPictureInPictureSuspended, options: [.new]) { [weak self] pip, _ in
                    DispatchQueue.main.async { self?.onEvent?("PiP suspended: \(pip.isPictureInPictureSuspended)") }
                },
                player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                    DispatchQueue.main.async { self?.onEvent?("Player state: \(player.timeControlStatus.rawValue) (0 paused, 1 waiting, 2 playing)") }
                }
            ]
        }
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        generation = UUID()
        heartbeatCount = 0
        networkCount = 0
        lastGap = 0
        elapsed = 0
        previousTick = ProcessInfo.processInfo.systemUptime
        running = true
        player.play()
        nowPlaying?.becomeActiveIfPossible { [weak self] success in
            DispatchQueue.main.async { self?.onEvent?("Now Playing session active: \(success)") }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        update("Video prepared — select Start PiP when enabled")
        onEvent?("PiP test started; muted local video; mixed audio; network probe every 10 seconds; auto-stop after 5 minutes")
        logAudioRoute()
    }

    func startPiP() {
        guard running, ready, !active else { return }
        update("Starting PiP")
        controller?.startPictureInPicture()
    }

    func stop() {
        guard running else { return }
        if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
        endRun()
        update("Test stopped")
    }

    private func endRun() {
        running = false
        generation = UUID()
        timer?.invalidate()
        timer = nil
        request?.cancel()
        request = nil
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { onEvent?("Audio cleanup error: \(error as NSError)") }
    }

    func sceneChanged(_ value: String) {
        scene = value
        onEvent?("PiP scene: \(value); active: \(active)")
    }

    func logAudioRoute() {
        let audio = AVAudioSession.sharedInstance()
        let ports = audio.currentRoute.outputs.map { "\($0.portName) [\($0.portType.rawValue)]" }.joined(separator: ", ")
        onEvent?("Audio route: \(ports); reported output volume (read-only): \(audio.outputVolume)")
    }

    private func tick() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lastGap = now - (previousTick ?? now)
        previousTick = now
        elapsed += lastGap
        heartbeatCount += 1
        onEvent?("Heartbeat \(heartbeatCount); scene \(scene); PiP \(active); gap \(String(format: "%.1f", lastGap))s")
        if elapsed >= 300 { stop(); return }
        if heartbeatCount.isMultiple(of: 2), request == nil { checkNetwork() }
        if let error = player.currentItem?.error {
            stop()
            update("Player failed: \(error as NSError)")
        }
    }

    private func checkNetwork() {
        // Small public response to prove network execution without a paid sports-data key.
        let url = URL(string: "https://www.apple.com/library/test/success.html")!
        var query = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        query.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let currentGeneration = generation
        let started = Date()
        onEvent?("Network request started; scene \(scene)")
        request = network.dataTask(with: query) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.running, self.generation == currentGeneration else { return }
                self.request = nil
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if error == nil, code == 200, data?.isEmpty == false { self.networkCount += 1 }
                self.onEvent?("Network finished; HTTP \(code); scene \(self.scene); elapsed \(String(format: "%.1f", Date().timeIntervalSince(started)))s; error \(error.map { String(describing: $0) } ?? "none")")
            }
        }
        request?.resume()
    }

    private func update(_ message: String) {
        status = message
        onEvent?(message)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        active = true
        update("PiP active — open DIRECTV and watch for two minutes")
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   failedToStartPictureInPictureWithError error: Error) {
        update("PiP start failed: \(error as NSError)")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        active = false
        if running { endRun() }
        update("PiP stopped")
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // The inline player remains in the root view throughout the test.
        completionHandler(true)
    }
}
