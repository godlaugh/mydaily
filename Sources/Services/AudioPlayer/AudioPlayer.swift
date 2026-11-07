import AVFoundation
import XLog

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayer()
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentFile: String?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTitle = ""
    @Published var errorMessage: String?

    convenience init(_ url: URL) {
        self.init()
        do { try load(url: url) } catch { errorMessage = error.localizedDescription }
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
    }

    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self) }

    @objc private func interrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              raw == AVAudioSession.InterruptionType.began.rawValue else { return }
        DispatchQueue.main.async { [weak self] in self?.pause() }
    }

    func load(url: URL) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        audioPlayer = player
        duration = player.duration
    }

    func toggle(file: String, title: String) {
        if currentFile == file {
            isPlaying ? pause() : play()
        } else {
            play(file: file, title: title)
        }
    }

    func play(file: String, title: String = "") {
        do {
            try load(url: FileHelper.fullAudioURL(for: file))
            currentFile = file
            currentTitle = title
            errorMessage = nil
            play()
        } catch {
            stop()
            errorMessage = error.localizedDescription
            XLog.error(error, source: "Player")
        }
    }

    func play() {
        guard let audioPlayer else { return }
        duration = audioPlayer.duration
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            if audioPlayer.currentTime >= audioPlayer.duration { audioPlayer.currentTime = 0 }
            guard audioPlayer.play() else { return }
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.currentTime = self.audioPlayer?.currentTime ?? 0
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        audioPlayer?.pause()
        currentTime = audioPlayer?.currentTime ?? 0
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func seek(to position: TimeInterval) {
        guard let audioPlayer else { return }
        audioPlayer.currentTime = min(max(0, position), audioPlayer.duration)
        currentTime = audioPlayer.currentTime
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        timer?.invalidate()
        timer = nil
        currentFile = nil
        currentTitle = ""
        currentTime = 0
        duration = 0
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        player.currentTime = 0
        currentTime = 0
    }
}
