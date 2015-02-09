//
//  ViewController.swift
//  FreeStreamerSeekTest
//
//  Created by Gurpartap Singh on 09/02/15.
//  Copyright (c) 2015 Gurpartap Singh. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet var statusLabel: UILabel!
    @IBOutlet var timeRemainingLabel: UILabel!
    @IBOutlet var timeElapsedLabel: UILabel!
    @IBOutlet var playbackProgressSlider: UISlider!
    @IBOutlet var bufferProgressView: UIProgressView!
    @IBOutlet var playButton: UIButton!
    @IBOutlet var pauseButton: UIButton!
    
    var cachedAudioController: FSAudioController?
    var audioController: FSAudioController! {
        get {
            if cachedAudioController != nil {
                return cachedAudioController
            } else {
                cachedAudioController = FSAudioController()
                enableEventHandlersForStream(cachedAudioController!.stream)
                return cachedAudioController
            }
        }
        set(newValue) {
            if newValue != nil {
                cachedAudioController = newValue
                enableEventHandlersForStream(cachedAudioController!.stream)
            } else {
                cachedAudioController = nil
            }
        }
    }
    
    var isPaused: Bool?
    var lastPlaybackURL: String?
    var progressMonitorTimer: NSTimer?
    var bufferingProgressOffset: Float = 0
    var maxPrebufferedByteCount: Float {
        get {
            return Float(audioController.stream.configuration.maxPrebufferedByteCount)
        }
    }
    var errorMessage: String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        resetPlayer()
        play()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func play() {
        if isPaused != nil && isPaused == true {
            audioController.pause()
        } else {
            audioController.play()
        }
        
        // Show pause button.
        pauseButton.hidden = false
        playButton.hidden = true
    }
    
    @IBAction func pause() {
        audioController.pause()
        isPaused = true
        showPlayButton()
    }
    
    @IBAction func resetPlayer() {
        stopMonitoringAudioPosition()
        bufferingProgressOffset = 0
        isPaused = nil
        
        audioController = FSAudioController()
        audioController.url = NSURL(string: "http://www.stephaniequinn.com/Music/Canon.mp3")!
        
        bufferProgressView.progress = 0
        bufferProgressView.hidden = true
        
        playbackProgressSlider.value = 0
        playbackProgressSlider.userInteractionEnabled = false
        
        timeRemainingLabel.text = "--:--"
        timeElapsedLabel.text = "--:--"
        
        statusLabel.text = "Player"
        
        showPlayButton()
    }
    
    func showPlayButton() {
        pauseButton.hidden = true
        playButton.hidden = false
    }
    
    func showPauseButton() {
        pauseButton.hidden = false
        playButton.hidden = true
    }
    
    @IBAction func sliderTouchDown(sender: UISlider) {
        stopMonitoringAudioPosition()
    }
    
    @IBAction func sliderTouchUp(sender: UISlider) {
        var pos = FSStreamPosition(minute: 0, second: 0, playbackTimeInSeconds: 0, position: 0)
        
        // 1.0 causes fsaudiostream to replay the audio within the same session, doubling the duration, etc.
        // Have to check if this still occurs.
        pos.position = min(playbackProgressSlider.value, 0.98)
        
        audioController.stream.seekToPosition(pos)
    }
    
    @IBAction func sliderValueChanged(sender: UISlider) {
        let durationInSeconds = Float((audioController.stream.duration.minute * 60) + audioController.stream.duration.second)
        
        var seekDurationInSeconds = durationInSeconds * playbackProgressSlider.value
        var seekTimeMins = Int(seekDurationInSeconds / 60)
        var seekTimeSecs = Int(seekDurationInSeconds % 60)
        timeElapsedLabel.text = String(format: "%01d:%02d", seekTimeMins, seekTimeSecs) as String!
        
        seekDurationInSeconds = durationInSeconds - seekDurationInSeconds
        seekTimeMins = Int(seekDurationInSeconds / 60)
        seekTimeSecs = Int(seekDurationInSeconds % 60)
        timeRemainingLabel.text = String(format: "-%01d:%02d", seekTimeMins, seekTimeSecs) as String!
    }
    
    func startMonitoringAudioPosition() {
        stopMonitoringAudioPosition()
        progressMonitorTimer = NSTimer.scheduledTimerWithTimeInterval(0.5, target: self, selector: "updatePlaybackProgress:", userInfo: nil, repeats: true)
    }
    
    func stopMonitoringAudioPosition() {
        if let timer = progressMonitorTimer {
            progressMonitorTimer?.invalidate()
            progressMonitorTimer = nil
        }
    }
    
    func updatePlaybackProgress(timer: NSTimer!) {
        if let controller = audioController {
            if !controller.stream.continuous && controller.isPlaying() {
                let timeElapsed = controller.stream.currentTimePlayed
                
                
                let duration = controller.stream.duration
                let durationInSeconds = Float((duration.minute * 60) + duration.second)
                var timePendingInSeconds = durationInSeconds - timeElapsed.playbackTimeInSeconds
                
                var timePendingMinutes = Int(timePendingInSeconds / 60)
                var timePendingSeconds = Int(timePendingInSeconds % 60)
                
                playbackProgressSlider.setValue(timeElapsed.position, animated: true)
                timeElapsedLabel.text = String(format: "%01d:%02d", timeElapsed.minute, timeElapsed.second) as String!
                timeRemainingLabel.text = String(format: "-%01d:%02d", timePendingMinutes, timePendingSeconds) as String!
            }
            
            if controller.stream != nil && controller.stream.contentLength > 0 {
                bufferProgressView.hidden = false
                
                // prebufferedByteCount......................... :(
                var progress: Float = Float(controller.stream.prebufferedByteCount) / Float(controller.stream.configuration.maxPrebufferedByteCount)
                
                if progress > 1.0 {
                    progress = 1.0
                } else if bufferingProgressOffset > 0 {
                    progress /= (1 / bufferingProgressOffset)
                    progress += bufferingProgressOffset
                }
                
                progress = max(0, min(progress, 1.0))
                
                bufferProgressView.setProgress(progress, animated: true)
            }
        }
    }

    // MARK: - FSAudioStream handlers
    
    func enableEventHandlersForStream(stream: FSAudioStream) {
        stream.onStateChange = streamStateChangeHandler()
        stream.onFailure = streamFailureHandler()
    }
    
    func streamStateChangeHandler() -> (FSAudioStreamState) -> Void {
        return { state in
            switch state.value {
            case kFsAudioStreamRetrievingURL.value:
                UIApplication.sharedApplication().networkActivityIndicatorVisible = true
                self.statusLabel.text = "Retreiving URL..."
                self.playbackProgressSlider.userInteractionEnabled = false
                self.showPauseButton()
                self.isPaused = false
                
                break
            case kFsAudioStreamBuffering.value:
                UIApplication.sharedApplication().networkActivityIndicatorVisible = true
                self.statusLabel.text = "Buffering..."
                
                self.bufferingProgressOffset = self.playbackProgressSlider.value
                self.bufferProgressView.progress = self.bufferingProgressOffset
                
                self.playbackProgressSlider.userInteractionEnabled = false
                self.showPauseButton()
                self.isPaused = false
                
                break
            case kFsAudioStreamSeeking.value:
                UIApplication.sharedApplication().networkActivityIndicatorVisible = true
                self.statusLabel.text = "Seeking..."
                self.playbackProgressSlider.userInteractionEnabled = true
                self.showPauseButton()
                self.isPaused = false
                
                break
            case kFsAudioStreamPlaying.value:
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                self.statusLabel.text = "Playing"
                self.playbackProgressSlider.userInteractionEnabled = true
                
                self.showPauseButton()
                self.isPaused = false
                self.startMonitoringAudioPosition()
                
                break
            case kFsAudioStreamPlaybackCompleted.value:
                self.stopMonitoringAudioPosition()
                self.resetPlayer()
                
                break
            case kFsAudioStreamPaused.value:
                self.statusLabel.text = "Paused"
                
                break
            case kFsAudioStreamStopped.value:
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                self.stopMonitoringAudioPosition()
                self.resetPlayer()
                self.playbackProgressSlider.userInteractionEnabled = false
                self.showPlayButton()
                self.isPaused = false
                
                break
            case kFsAudioStreamFailed.value:
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                self.stopMonitoringAudioPosition()
                self.playbackProgressSlider.userInteractionEnabled = false
                self.showPlayButton()
                self.isPaused = false
                
                self.statusLabel.text = countElements(self.errorMessage) > 0 ? self.errorMessage : ""
                
                break
            default:
                break
            }
        }
    }
    
    func streamFailureHandler() -> (FSAudioStreamError, String!) -> Void {
        return { error, errorDescription in
            var errorCategory: String!
            switch error.value {
            case kFsAudioStreamErrorOpen.value:
                errorCategory = "Cannot open the audio stream"
                break
            case kFsAudioStreamErrorStreamParse.value:
                errorCategory = "Cannot read the audio stream"
                break
            case kFsAudioStreamErrorNetwork.value:
                errorCategory = "The Internet connection appears to be offline"
                break
            case kFsAudioStreamErrorUnsupportedFormat.value:
                errorCategory = "Unsupported format"
                break
            case kFsAudioStreamErrorStreamBouncing.value:
                errorCategory = "Network error. Cannot get enough data to play"
                break
            default:
                errorCategory = "Unknown error occurred"
                break
            }
            self.errorMessage = errorCategory
        }
    }
    
}
