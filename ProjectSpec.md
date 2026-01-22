Technical Specification: Volleyball Auto-Editor (Apple Silicon)

1. Project Overview

Objective: Build a native macOS/iPadOS application that autonomously edits raw volleyball footage (1 hr+) into a "Action Only" highlight reel.
Core Constraint: Processing must happen locally on Apple Silicon (M-Series) using the Neural Engine.
Video Output: Lossless "Passthrough" stitching (No re-encoding).
Target Formats: Beach (2s), Grass (2s/3s/4s), Indoor (6s).

2. Technology Stack

Language: Swift 6.0+

UI Framework: SwiftUI

Computer Vision: Vision Framework (VNRecognizeBodyPoseRequest)

Media Processing: AVFoundation (AVAssetReader, AVMutableComposition)

Concurrency: Swift Actors (actor)

3. High-Level Architecture

The system operates in a linear Three-Stage Pipeline to manage memory efficiency on large video files.

Ingest & Analysis (The "Eye"): Reads video, downsamples to RAM-friendly resolution, extracts skeletal poses.

Heuristic Classification (The "Brain"): A Time-Series State Machine that interprets skeletal data into "Game States" (Idle, Ready, Rally).

Lossless Assembly (The "Hands"): Maps timestamps to the original 4K/1080p file and exports without re-encoding.

4. Detailed Component Specifications

Component A: The Efficient Video Reader (VideoAnalyzer)

Critical Requirement: Do NOT decode full 1080p/4K frames into memory. The Vision framework does not need high resolution.

Implementation:

Use AVAssetReader to read the video track.

Downsampling: Configure AVAssetReaderTrackOutput with kCVPixelBufferWidthKey: 640, kCVPixelBufferHeightKey: 360.

Format: kCVPixelFormatType_32BGRA (Native format for Vision).

Data Extraction Strategy:

Run VNRecognizeBodyPoseRequest on every frame (or every 2nd frame if 60fps).

Filtering: Ignore players where boundingBox.height < 0.15 (15% of screen height). This automatically removes players on the far side of the net, reducing noise.

Component B: The Heuristic Classifier (RallyProcessor)

This is the most complex component. It must handle variable player counts (2 vs 6) and variable end-of-play behaviors (Huddle vs Reset).

1. Frame Metrics (The Raw Data)

For every frame $t$, calculate:

ActiveCount: Number of players detected on the Near Side (height > 15%).

TeamEnergy: Sum of the velocity deltas of all active wrists and ankles.

Low Energy (< 0.2): Standing/Walking.

High Energy (> 0.5): Running/Jumping.

HuddleScore: The inverse of the Standard Deviation of player Centroids.

High Score: Players are clustered (Huddle).

Low Score: Players are spread out (Defense positions).

2. The State Machine

The system transitions between four states: IDLE -> READY -> ACTION -> COOLDOWN.

State 1: IDLE (Downtime)

Behavior: Players are walking, picking up balls.

Transition to READY:

ActiveCount stabilizes (Variance < 1.0 for 1s).

TeamEnergy drops to "Static" levels (Players freezing to receive).

Action: Mark PotentialStartTime.

State 2: READY (The Serve)

Behavior: Players are frozen, waiting for serve.

Transition to ACTION:

TeamEnergy spikes > Threshold (The receive/pass).

Transition to IDLE (False Alarm):

TeamEnergy remains low, but players break formation (walking away).

State 3: ACTION (The Rally)

Behavior: High energy, erratic movement.

Transition to COOLDOWN (The Compound Trigger):

Trigger A (Beach/Grass): HuddleScore spikes (Celebration).

Trigger B (Indoor/Reset): TeamEnergy drops below WalkingThreshold and stays there for > 2.0 seconds.

State 4: COOLDOWN (Padding)

Action: Record EndTime.

Logic: Apply User Configurable Post-Padding (e.g., +3 seconds) to capture the reaction, then cut.

Component C: The Stitcher (VideoStitcher)

Critical Requirement: Frame-Accurate cutting without re-encoding.

Implementation:

Use AVMutableComposition.

Keyframe Alignment: When inserting a CMTimeRange, the system must preserve the GOP (Group of Pictures).

Preset: AVAssetExportPresetPassthrough.

Warmup Skipping:

The RallyProcessor must discard all events before the First Valid Huddle or First Sustained Action to avoid processing warmups.

5. Implementation Roadmap (Swift)

Step 1: Data Models

struct FrameMetrics {
    let timestamp: Double
    let activePlayerCount: Int
    let teamEnergy: Float // Normalized 0.0 to 1.0
    let isHuddled: Bool
}

struct ProcessingConfig {
    var prePadding: TimeInterval = 2.0
    var postPadding: TimeInterval = 3.0
    var minRallyDuration: TimeInterval = 3.0
}


Step 2: The Core Logic Loop (Pseudocode)

func process(frames: [FrameMetrics]) -> [CMTimeRange] {
    var clips: [CMTimeRange] = []
    var state = State.IDLE
    var bufferStart = 0.0
    var lowEnergyTimer = 0.0

    for frame in frames {
        switch state {
        case .IDLE:
            if frame.isReadyPosition {
                state = .READY
                bufferStart = frame.timestamp
            }
        case .READY:
            if frame.teamEnergy > 0.6 {
                state = .ACTION
            } else if !frame.isReadyPosition {
                state = .IDLE // False start
            }
        case .ACTION:
            // The Compound Stop Trigger
            let isHuddled = frame.isHuddled
            let isReset = frame.teamEnergy < 0.2
            
            if isReset { lowEnergyTimer += delta } else { lowEnergyTimer = 0 }

            if isHuddled || lowEnergyTimer > 2.0 {
                // End of Play Detected
                let end = isHuddled ? frame.timestamp : (frame.timestamp - 2.0)
                clips.append(CMTimeRange(start: bufferStart, end: end))
                state = .IDLE
            }
        }
    }
    return mergeClips(clips) // Handle overlapping padding
}


6. Project Configuration Requirements

To ensure the "Agent" implements this correctly in Xcode:

Sandbox Permissions:

Key: com.apple.security.files.user-selected.read-write -> true

Reason: Required to save the exported video to the disk.

Info.plist Keys:

NSPhotoLibraryUsageDescription: "Required to analyze video."

NSDesktopFolderUsageDescription: "Required to save exports." (If macOS target).

Performance Tuning:

Vision requests must be run on a background Task or DispatchQueue.

UI must show a ProgressView as analysis of 1hr video takes ~3-5 mins on M1/M2.

7. Edge Case Handling

The "Ball Roll": In indoor, rolling the ball under the net looks like low energy. The lowEnergyTimer > 2.0s logic handles this (it counts as a stop, which is correct).

The "Long Serve Routine": If a server takes 8 seconds to serve, the READY state might timeout.

Fix: Increase READY timeout logic or ensure isReadyPosition checks for "Static Stance" specifically.

The "Screening" (Indoor): Front row players block the camera view of the server.

Fix: The logic relies on the Receivers (Near Side), so screening of the server is irrelevant.
