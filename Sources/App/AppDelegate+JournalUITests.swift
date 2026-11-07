#if DEBUG
import Foundation
import CoreData
import AVFoundation

extension AppDelegate {
    func setupJournalUITests() {
        let config = Config.shared
        config.transEnabled = false
        config.sumEnabled = false
        config.autoSave = !ProcessInfo.processInfo.arguments.contains("-journal-ui-manual-save")
        config.holdToRecordEnabled = ProcessInfo.processInfo.arguments.contains("-journal-ui-hold")
        config.autoStartOnStartup = ""
        guard ProcessInfo.processInfo.arguments.contains("-journal-ui-seed") else { return }
        let context = DataContainer.shared.context
        do {
            for memo in try context.fetch(MemoEntity.all) { context.delete(memo) }
            for thread in try context.fetch(JournalThreadEntity.fetchRequest()) { context.delete(thread) }
            try context.save()
            let destination = FileHelper.fullAudioURL(for: "journal-ui-sample.wav")
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320000)!
            buffer.frameLength = 320000
            buffer.floatChannelData?[0].update(repeating: 0, count: 320000)
            let output = try AVAudioFile(forWriting: destination, settings: format.settings)
            try output.write(from: buffer)
            let wordBoundarySample = ProcessInfo.processInfo.arguments.contains("-journal-ui-word-boundary")
            let firstContent = wordBoundarySample
                ? "This recording is about better transcription quality."
                : "走慢一点，也没有关系。\n不用把每一天都安排得很满。留一点空白，反而能听见自己的想法。"
            let first = try JournalStore.add(content: firstContent, file: destination.lastPathComponent, duration: 20, transcribed: true, in: context)
            first.id = "quiet-root"
            first.createdAt = Date(timeIntervalSince1970: 1762473600)
            let second = try JournalStore.add(content: "开始每周给自己留一个没有安排的下午。原来慢下来，也需要一点练习。", parentID: first.objectID, in: context)
            second.createdAt = Date(timeIntervalSince1970: 1770422400)
            let third = try JournalStore.add(content: "今天又走过那条街。银杏又黄了，我已经不太急着赶路。去年那句话，慢慢成了生活。", parentID: first.objectID, in: context)
            third.createdAt = Date(timeIntervalSince1970: 1794009600)
            let otherContent = wordBoundarySample
                ? "这段日记是在讨论语音识别的准确性，以及使用 SenseVoice transcription 模型时的感受。"
                : "把刚刚的灵感，先存下来。\n关于记录的一点小想法。"
            let other = try JournalStore.add(content: otherContent, in: context)
            other.id = "quiet-other"
            other.createdAt = Date(timeIntervalSince1970: 1794006000)
            if ProcessInfo.processInfo.arguments.contains("-journal-ui-long-list") {
                for index in 0..<12 {
                    let entry = try JournalStore.add(content: "日常记录 \(index + 1)。\n今天记下的几个想法。慢慢整理生活中的变化，让每一段记录都有自己的位置。", in: context)
                    entry.id = "scroll-entry-\(index)"
                    entry.createdAt = Date(timeIntervalSince1970: 1750000000 - Double(index * 86400))
                }
                let tail = try JournalStore.add(content: "最早的一条日记。\n滑到列表底部后，这段内容应该完整保留在工具条上方，松手后也可以正常打开和长按操作。", in: context)
                tail.id = "scroll-tail"
                tail.createdAt = Date(timeIntervalSince1970: 1700000000)
                let addition = try JournalStore.add(content: "留在这里的补充记录，也应该能完整点开。", parentID: tail.objectID, in: context)
                addition.id = "scroll-tail-addition"
                addition.createdAt = Date(timeIntervalSince1970: 1700086400)
            }
            try context.save()
        } catch {
            assertionFailure("Could not prepare isolated journal UI data: \(error)")
        }
    }
}
#endif
