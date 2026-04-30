import AppKit

extension WalkerCharacter {
    func horizontalRangeMetrics(screen: NSScreen, dockX: CGFloat, dockWidth: CGFloat) -> (minX: CGFloat, travelDistance: CGFloat) {
        // Pin Orion to the centred 25% slice of the visible screen. Earlier
        // logic let him roam the dock width (or the full screen when
        // `usesExpandedHorizontalRange` was set) — both paths could put him
        // close enough to the dock edges that a flick of motion walked him
        // off the visible rail. The 25% band is wide enough to feel alive
        // and narrow enough to keep him safely on the dock.
        //
        // `dockX` and `dockWidth` are unused but kept in the signature so
        // every caller in the rendering pipeline continues to work without
        // a sweep through Movement / Visuals.
        _ = dockX
        _ = dockWidth
        let visible = screen.visibleFrame
        let bandWidth = visible.width * 0.25
        let minX = visible.minX + (visible.width - bandWidth) / 2.0
        let travel = max(bandWidth - displayWidth, 0)
        return (minX, travel)
    }

    func startWalk() {
        isPaused = false
        isWalking = true
        walkStartTime = CACurrentMediaTime()

        if positionProgress > 0.85 {
            goingRight = false
        } else if positionProgress < 0.15 {
            goingRight = true
        } else {
            goingRight = Bool.random()
        }

        walkStartPos = positionProgress
        let referenceWidth: CGFloat = 500.0
        let walkPixels = CGFloat.random(in: walkAmountRange) * referenceWidth
        let walkAmount = currentTravelDistance > 0 ? walkPixels / currentTravelDistance : 0.3
        if goingRight {
            walkEndPos = min(walkStartPos + walkAmount, 1.0)
        } else {
            walkEndPos = max(walkStartPos - walkAmount, 0.0)
        }
        walkStartPixel = walkStartPos * currentTravelDistance
        walkEndPixel = walkEndPos * currentTravelDistance

        let minSeparation: CGFloat = 0.12
        if let siblings = controller?.characters {
            for sibling in siblings where sibling !== self {
                let sibPos = sibling.positionProgress
                if abs(walkEndPos - sibPos) < minSeparation {
                    if goingRight {
                        walkEndPos = max(walkStartPos, sibPos - minSeparation)
                    } else {
                        walkEndPos = min(walkStartPos, sibPos + minSeparation)
                    }
                }
            }
        }

        setFacing(goingRight ? .right : .left)
    }

    func enterPause() {
        isWalking = false
        isPaused = true
        // Idle facing variety — most pauses face the camera, ~40% turn
        // their back (looking out at the wallpaper). Mid-pause, the
        // facing re-rolls every ~3–5s (see update()) so longer pauses
        // visibly cycle through facings instead of locking on one.
        let facing: WalkerFacing = Double.random(in: 0...1) < 0.40 ? .back : .front
        setFacing(facing)
        let now = CACurrentMediaTime()
        let delay = Double.random(in: 5.0...12.0)
        pauseEndTime = now + delay
        nextIdleFacingRollAt = now + Double.random(in: 3.0...5.0)
    }

    /// Mid-pause facing re-roll. Called from update() while the
    /// character is paused. Picks front or back at random with a
    /// modest bias toward the OPPOSITE of the current facing so the
    /// user actually sees the change rather than rolling the same
    /// face twice in a row most of the time.
    func rerollIdleFacingIfDue() {
        let now = CACurrentMediaTime()
        guard now >= nextIdleFacingRollAt else { return }
        // 60% chance to flip to the OPPOSITE facing, 40% to stay /
        // re-pick from scratch — keeps it from feeling metronomic.
        let currentlyBack = (imageView?.image === directionalImages[.back])
        if Double.random(in: 0...1) < 0.60 {
            setFacing(currentlyBack ? .front : .back)
        } else {
            let next: WalkerFacing = Double.random(in: 0...1) < 0.40 ? .back : .front
            setFacing(next)
        }
        nextIdleFacingRollAt = now + Double.random(in: 3.0...5.0)
    }

    func movementPosition(at videoTime: CFTimeInterval) -> CGFloat {
        let dIn = fullSpeedStart - accelStart
        let dLin = decelStart - fullSpeedStart
        let dOut = walkStop - decelStart
        let v = 1.0 / (dIn / 2.0 + dLin + dOut / 2.0)

        if videoTime <= accelStart {
            return 0.0
        } else if videoTime <= fullSpeedStart {
            let t = videoTime - accelStart
            return CGFloat(v * t * t / (2.0 * dIn))
        } else if videoTime <= decelStart {
            let easeInDist = v * dIn / 2.0
            let t = videoTime - fullSpeedStart
            return CGFloat(easeInDist + v * t)
        } else if videoTime <= walkStop {
            let easeInDist = v * dIn / 2.0
            let linearDist = v * dLin
            let t = videoTime - decelStart
            return CGFloat(easeInDist + linearDist + v * (t - t * t / (2.0 * dOut)))
        } else {
            return 1.0
        }
    }

    func update(screen: NSScreen, dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat) {
        let horizontalMetrics = horizontalRangeMetrics(screen: screen, dockX: dockX, dockWidth: dockWidth)
        currentTravelDistance = horizontalMetrics.travelDistance
        if isDraggingHorizontally {
            // Drag is now free-fly (cursor pulls character anywhere on
            // screen, including off the dock). continueHorizontalDrag
            // sets window.frameOrigin directly from the cursor each
            // mouseDragged event, so the per-tick update has no
            // position to apply — early-return without touching
            // window.frame at all. Otherwise the tick-loop would
            // override the cursor-set position back onto the dock and
            // the drag would feel anchored.
            updatePopoverPosition()
            updateThinkingBubble()
            updateExpertNameTag()
            return
        }
        if isCompanionAvatar {
            let travelDistance = currentTravelDistance
            let x = horizontalMetrics.minX + travelDistance * positionProgress + flipXOffset
            let bottomPadding = displayHeight * 0.15
            let y = dockTopY - bottomPadding + yOffset
            window.setFrameOrigin(NSPoint(x: x, y: y))
            hideBubble()
            updateExpertNameTag()
            return
        }
        if focusedExpert != nil {
            isWalking = false
            isPaused = true
            pauseEndTime = .greatestFiniteMagnitude
            setFacing(.front)
            let travelDistance = currentTravelDistance
            let x = horizontalMetrics.minX + travelDistance * positionProgress + flipXOffset
            let bottomPadding = displayHeight * 0.15
            let y = dockTopY - bottomPadding + yOffset
            window.setFrameOrigin(NSPoint(x: x, y: y))
            updatePopoverPosition()
            updateThinkingBubble()
            updateExpertNameTag()
            return
        }
        if isIdleForPopover {
            let travelDistance = currentTravelDistance
            let x = horizontalMetrics.minX + travelDistance * positionProgress + flipXOffset
            let bottomPadding = displayHeight * 0.15
            let y = dockTopY - bottomPadding + yOffset
            window.setFrameOrigin(NSPoint(x: x, y: y))
            updatePopoverPosition()
            updateThinkingBubble()
            updateExpertNameTag()
            return
        }

        if movementLocked {
            isWalking = false
            isPaused = true
            pauseEndTime = .greatestFiniteMagnitude
            setFacing(.front)
            let x = horizontalMetrics.minX + currentTravelDistance * positionProgress + flipXOffset
            let bottomPadding = displayHeight * 0.15
            let y = dockTopY - bottomPadding + yOffset
            window.setFrameOrigin(NSPoint(x: x, y: y))
            updateThinkingBubble()
            updateExpertNameTag()
            return
        }

        // Sleep check — if Orion is sleeping (or just transitioned
        // into sleep), hold position and skip all movement logic. The
        // sleeping GIF is already swapped in by enterSleep().
        if updateSleepState() {
            let x = horizontalMetrics.minX + currentTravelDistance * positionProgress + flipXOffset
            let bottomPadding = displayHeight * 0.15
            let y = dockTopY - bottomPadding + yOffset
            window.setFrameOrigin(NSPoint(x: x, y: y))
            updateExpertNameTag()
            return
        }

        let now = CACurrentMediaTime()

        if isPaused {
            if now >= pauseEndTime {
                startWalk()
            } else {
                // Mid-pause facing re-roll — periodically swap between
                // front and back so longer idle stretches cycle through
                // facings instead of locking on the one chosen at
                // pause start.
                rerollIdleFacingIfDue()
                // Ambient bubble check — periodically pop a short
                // Justin-voice comment (CRM tip / dry remark) if we're
                // genuinely idle. Suppressed automatically while chat
                // is open or model is busy (see tickAmbientBubble).
                tickAmbientBubble()
                let x = horizontalMetrics.minX + currentTravelDistance * positionProgress + flipXOffset
                let bottomPadding = displayHeight * 0.15
                let y = dockTopY - bottomPadding + yOffset
                window.setFrameOrigin(NSPoint(x: x, y: y))
                updateExpertNameTag()
                return
            }
        }

        if isWalking {
            let elapsed = now - walkStartTime
            // Skip the front-loaded idle lead-in of the source walk cycle so movement
            // starts as soon as we switch into the walking state.
            let videoTime = min(elapsed + accelStart, walkStop)
            let travelDistance = currentTravelDistance

            let walkNorm = videoTime >= walkStop ? 1.0 : movementPosition(at: videoTime)
            let currentPixel = walkStartPixel + (walkEndPixel - walkStartPixel) * walkNorm

            if travelDistance > 0 {
                positionProgress = min(max(currentPixel / travelDistance, 0), 1)
            }

            let x = horizontalMetrics.minX + travelDistance * positionProgress + flipXOffset
            let bottomPadding = displayHeight * 0.15
            let y = dockTopY - bottomPadding + yOffset
            window.setFrameOrigin(NSPoint(x: x, y: y))

            if videoTime >= walkStop {
                positionProgress = walkEndPos
                window.setFrameOrigin(NSPoint(
                    x: horizontalMetrics.minX + travelDistance * positionProgress + flipXOffset,
                    y: y
                ))
                enterPause()
                return
            }
        }

        updateThinkingBubble()
        updateExpertNameTag()
    }
}
