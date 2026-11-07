//
//  TimelineViewModel.swift
//  ALog
//
//  Created by Xin Du on 2023/07/19.
//

import Foundation
import Combine
import XLog
import CoreData
import SwiftUI

class TimelineViewModel: ObservableObject {
    @Published var showDeleteAlert = false
    @Published var memoToDelete: MemoEntity? {
        didSet {
            if memoToDelete != nil {
                showDeleteAlert = true
            }
        }
    }
    @Published var memoToShare: MemoEntity?
    
    @Published var transcribingMemos = Set<MemoEntity>()
    @Published var failedMemos = [MemoEntity: Error]()
    @Published var showReviewDialog = false
    
    @Published var isHoldingToRecord = false
    @Published var recordingError: String?
    
    @Published var isMultiSelectMode = false
    @Published var selectedMemos = Set<MemoEntity>()
    
    let recorder = AudioRecorder()
    
    @AppStorage("requested_review_at") var requestedReviewAt = Date(timeIntervalSince1970: 0).timeIntervalSince1970
    
    private var transCount = 0
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(contextDidSave), name: .NSManagedObjectContextDidSave, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func contextDidSave(notification: Notification) {
        guard Config.shared.transEnabled else { return }
        guard let userInfo = notification.userInfo else { return }
        if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>, !insertedObjects.isEmpty {
            for obj in insertedObjects {
                guard let memo = obj as? MemoEntity else { continue }
                guard memo.needsTranscription else { continue }
                transcribe(memo)
            }
        }
    }
    
    func transcribe(_ memo: MemoEntity) {
        guard memo.file != nil, !memo.isDeleted, !transcribingMemos.contains(memo) else { return }
        failedMemos[memo] = nil
        transcribingMemos.insert(memo)
        Transcription.shared.transcribe(memo) { [weak self] result in
            self?.transcribingMemos.remove(memo)
            guard !memo.isDeleted, memo.managedObjectContext != nil else { return }
            switch result {
            case .success(let text):
                // Silence is a completed transcription, but must not erase existing edits.
                let content = text.isEmpty ? (memo.content ?? "") : text
                if memo.content != content || !memo.transcribed {
                    memo.content = content
                    memo.transcribed = true
                    try? DataContainer.shared.context.save()
                    if !text.isEmpty {
                        self?.transCount += 1
                        self?.requestReview()
                    }
                }
            case .failure(let error):
                self?.failedMemos[memo] = error
                XLog.error(error, source: "Timeline")
            }
        }
    }
    
    func toggleVisibility(_ memo: MemoEntity) {
        memo.isHidden.toggle()
        do {
            try DataContainer.shared.context.save()
        } catch {
            XLog.error(error, source: "Timeline")
        }
    }
    
    private func requestReview() {
        guard transCount > 5 else { return }
        let timeInterval = Date().timeIntervalSince1970
        if timeInterval - requestedReviewAt > 3600 * 24 * 10 {
            showReviewDialog = true
            requestedReviewAt = timeInterval
        }
    }
    
    
    func beginHoldToRecord() {
        recordingError = nil
        recorder.didFinishCallback = { [weak self] in self?.isHoldingToRecord = false }
        recorder.startRecording()
        isHoldingToRecord = true
    }
    
    func endHoldToRecord() {
        isHoldingToRecord = false
        guard recorder.isRecording else { recorder.terminate(); return }
        recorder.didCompleteCallback = { [weak self] in
            guard let self = self, let url = self.recorder.voiceFile else {
                return
            }
            self.saveVoice(url)
        }
        recorder.stopRecording()
    }
    
    func cancelHoldToRecord() {
        recorder.terminate()
        isHoldingToRecord = false
    }
    
    private func saveVoice(_ voiceURL: URL) {
        Task { @MainActor in
            do {
                let duration = await FileHelper.getAudioDuration(voiceURL)
                let destination = try FileHelper.moveAudioFile(voiceURL)
                try JournalStore.add(content: "", file: destination.lastPathComponent,
                                     duration: duration, in: DataContainer.shared.context)
            } catch {
                recordingError = error.localizedDescription
                XLog.error(error, source: "recording")
            }
        }
    }
    
    func toggleMemoSelection(_ memo: MemoEntity) {
        if selectedMemos.contains(memo) {
            selectedMemos.remove(memo)
        } else {
            selectedMemos.insert(memo)
        }
    }
    
    func deleteSelectedMemos(moc: NSManagedObjectContext) {
        if isMultiSelectMode {
            MemoEntity.deleteMemos(moc: moc, memos: selectedMemos)
            selectedMemos.removeAll()
            isMultiSelectMode = false
            memoToDelete = nil
        } else {
            guard let memo = memoToDelete else { return }
            MemoEntity.delete(moc: moc, memo: memo)
            memoToDelete = nil
        }
    }
    
}
