import SwiftUI
import UIKit

struct GameInputSurface: UIViewRepresentable {
  let stageSize: CGSize
  let touchpadEnabled: Bool
  let inputGate: InputGatePolicy
  let onMouse: (CGPoint) -> Void
  let onMouseButton: (UInt32, Bool) -> Void
  let onTouch: (UInt32, UInt8, CGPoint) -> Void
  let onKey: (Int, Bool) -> Void
  let onForwardedWheelKey: (Int) -> Void

  func makeUIView(context: Context) -> GameInputUIView {
    let view = GameInputUIView()
    configure(view)
    return view
  }

  func updateUIView(_ uiView: GameInputUIView, context: Context) {
    configure(uiView)
  }

  private func configure(_ view: GameInputUIView) {
    view.stageSize = stageSize
    view.touchpadEnabled = touchpadEnabled
    view.inputGate = inputGate
    view.onMouse = onMouse
    view.onMouseButton = onMouseButton
    view.onTouch = onTouch
    view.onKey = onKey
    view.onForwardedWheelKey = onForwardedWheelKey
  }
}

final class GameInputUIView: UIView {
  var stageSize = CGSize(width: 1280, height: 720)
  var touchpadEnabled = false
  var inputGate = InputGatePolicy.full
  var onMouse: ((CGPoint) -> Void)?
  var onMouseButton: ((UInt32, Bool) -> Void)?
  var onTouch: ((UInt32, UInt8, CGPoint) -> Void)?
  var onKey: ((Int, Bool) -> Void)?
  var onForwardedWheelKey: ((Int) -> Void)?

  private final class WheelQueue {
    static let up = 136
    static let down = 137
    static let maximum = 12

    private var pending: [Int] = []

    func addScrollDelta(_ delta: CGFloat) {
      guard delta != 0 else { return }
      add(delta < 0 ? Self.up : Self.down)
    }

    func add(_ key: Int) {
      guard key == Self.up || key == Self.down else { return }
      if let last = pending.last, last != key {
        pending.removeAll()
      }
      if pending.count >= Self.maximum {
        pending.removeFirst()
      }
      pending.append(key)
    }

    func take() -> Int? {
      pending.isEmpty ? nil : pending.removeFirst()
    }

    func clear() {
      pending.removeAll()
    }
  }

  private final class TwoFingerTracker {
    private static let dragThreshold: CGFloat = 6
    private static let wheelNotch: CGFloat = 40

    private var start: CGPoint?
    private var last: CGPoint?
    private var dragged = false
    private var scrollAccumulator: CGFloat = 0

    var active: Bool {
      start != nil
    }

    func begin(_ positions: [CGPoint]) {
      reset()
      guard positions.count == 2 else { return }
      start = midpoint(positions)
      last = start
    }

    func move(
      _ positions: [CGPoint],
      scrollEnabled: Bool
    ) -> [Int] {
      guard let start, let last, positions.count == 2 else { return [] }
      let point = midpoint(positions)
      if hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold {
        dragged = true
      }
      let deltaY = point.y - last.y
      self.last = point
      guard scrollEnabled else { return [] }

      scrollAccumulator += deltaY
      var keys: [Int] = []
      while scrollAccumulator >= Self.wheelNotch {
        scrollAccumulator -= Self.wheelNotch
        keys.append(WheelQueue.up)
      }
      while scrollAccumulator <= -Self.wheelNotch {
        scrollAccumulator += Self.wheelNotch
        keys.append(WheelQueue.down)
      }
      return keys
    }

    func end(cancelled: Bool = false) -> Bool {
      let tapped = active && !cancelled && !dragged
      reset()
      return tapped
    }

    func reset() {
      start = nil
      last = nil
      dragged = false
      scrollAccumulator = 0
    }

    private func midpoint(_ positions: [CGPoint]) -> CGPoint {
      CGPoint(
        x: (positions[0].x + positions[1].x) / 2,
        y: (positions[0].y + positions[1].y) / 2
      )
    }
  }

  private final class TouchpadPointer {
    var stageSize = CGSize(width: 1280, height: 720)
    var position = CGPoint(x: 640, y: 360)

    func updateStageSize(_ value: CGSize) {
      stageSize = value
      position = clamped(position)
    }

    func move(displayDelta: CGPoint, displayScale: CGFloat) -> CGPoint {
      guard displayScale > 0 else { return position }
      position = clamped(
        CGPoint(
          x: position.x + displayDelta.x / displayScale,
          y: position.y + displayDelta.y / displayScale
        )
      )
      return position
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
      CGPoint(
        x: min(max(point.x, 0), max(stageSize.width - 1, 0)),
        y: min(max(point.y, 0), max(stageSize.height - 1, 0))
      )
    }
  }

  private var pointerIDs: [ObjectIdentifier: UInt32] = [:]
  private var activeTouches: [ObjectIdentifier: CGPoint] = [:]
  private var lastTouchpadPoint: CGPoint?
  private var touchpadDragging = false
  private var twoFingerRouting = false
  private let twoFinger = TwoFingerTracker()
  private let wheel = WheelQueue()
  private let touchpad = TouchpadPointer()
  private let cursorLayer = CAShapeLayer()
  private lazy var wheelTimer = Timer.scheduledTimer(
    withTimeInterval: 1.0 / 60.0,
    repeats: true
  ) { [weak self] _ in
    guard let self, let key = self.wheel.take() else { return }
    self.onForwardedWheelKey?(key)
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isMultipleTouchEnabled = true
    isOpaque = false
    backgroundColor = .clear
    cursorLayer.fillColor = UIColor.white.withAlphaComponent(0.72).cgColor
    cursorLayer.strokeColor = UIColor.black.withAlphaComponent(0.75).cgColor
    cursorLayer.lineWidth = 2
    cursorLayer.isHidden = true
    layer.addSublayer(cursorLayer)

    let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
    addGestureRecognizer(hover)

    let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
    scroll.minimumNumberOfTouches = 1
    scroll.maximumNumberOfTouches = 2
    scroll.allowedScrollTypesMask = .all
    scroll.cancelsTouchesInView = false
    addGestureRecognizer(scroll)

    RunLoop.main.add(wheelTimer, forMode: .common)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    wheelTimer.invalidate()
  }

  override var canBecomeFirstResponder: Bool {
    true
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateCursorLayer()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      becomeFirstResponder()
    }
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    becomeFirstResponder()
    for touch in touches {
      let identity = ObjectIdentifier(touch)
      let point = stagePoint(touch.location(in: self))
      pointerIDs[identity] = nextPointerID()
      activeTouches[identity] = point

      if touchpadEnabled {
        lastTouchpadPoint = touch.location(in: self)
        continue
      }

      if activeTouches.count == 2 {
        beginTwoFingerGesture()
      }
      let id = pointerIDs[identity] ?? 1
      if !twoFingerRouting {
        onMouse?(point)
        onMouseButton?(1, true)
      }
      onTouch?(id, 0, point)
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      let identity = ObjectIdentifier(touch)
      let displayPoint = touch.location(in: self)
      let point = stagePoint(displayPoint)
      activeTouches[identity] = point

      if touchpadEnabled {
        if activeTouches.count == 2 {
          handleTwoFingerMove()
          continue
        }
        let previous = lastTouchpadPoint ?? displayPoint
        let delta = CGPoint(
          x: displayPoint.x - previous.x,
          y: displayPoint.y - previous.y
        )
        lastTouchpadPoint = displayPoint
        if !touchpadDragging, hypot(delta.x, delta.y) >= 2 {
          touchpadDragging = true
          onMouseButton?(1, true)
        }
        let moved = touchpad.move(displayDelta: delta, displayScale: displayScale)
        onMouse?(moved)
        updateCursorLayer()
        continue
      }

      if activeTouches.count >= 2 {
        handleTwoFingerMove()
        let id = pointerIDs[identity] ?? 1
        onTouch?(id, 1, point)
        continue
      }

      onMouse?(point)
      let id = pointerIDs[identity] ?? 1
      onTouch?(id, 1, point)
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishTouches(touches, cancelled: false)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishTouches(touches, cancelled: true)
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    var handled = false
    for press in presses {
      guard let key = press.key.flatMap(virtualKey) else { continue }
      handled = true
      onKey?(key, true)
    }
    if !handled {
      super.pressesBegan(presses, with: event)
    }
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    var handled = false
    for press in presses {
      guard let key = press.key.flatMap(virtualKey) else { continue }
      handled = true
      onKey?(key, false)
    }
    if !handled {
      super.pressesEnded(presses, with: event)
    }
  }

  override func pressesCancelled(
    _ presses: Set<UIPress>,
    with event: UIPressesEvent?
  ) {
    pressesEnded(presses, with: event)
  }

  @objc
  private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
    guard !twoFingerRouting else { return }
    switch recognizer.state {
    case .began, .changed:
      onMouse?(stagePoint(recognizer.location(in: self)))
    default:
      break
    }
  }

  @objc
  private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
    guard inputGate.wheelToKeys else { return }
    guard recognizer.state == .began || recognizer.state == .changed else {
      return
    }
    // Direct two-finger touches are already translated by touchesMoved.
    guard activeTouches.isEmpty else { return }
    let delta = recognizer.translation(in: self).y
    recognizer.setTranslation(.zero, in: self)
    wheel.addScrollDelta(delta)
  }

  private func finishTouches(
    _ touches: Set<UITouch>,
    cancelled: Bool
  ) {
    for touch in touches {
      let identity = ObjectIdentifier(touch)
      let point = stagePoint(touch.location(in: self))
      let id = pointerIDs.removeValue(forKey: identity) ?? 1
      activeTouches.removeValue(forKey: identity)

      if touchpadEnabled {
        if activeTouches.isEmpty {
          if touchpadDragging {
            onMouseButton?(1, false)
            touchpadDragging = false
          } else if !cancelled {
            onMouseButton?(1, true)
            onMouseButton?(1, false)
          }
          lastTouchpadPoint = nil
        }
        continue
      }

      onTouch?(id, 2, point)
      if activeTouches.isEmpty {
        let tapped = twoFinger.end(cancelled: cancelled)
        if tapped, inputGate.twoFingerRightClick {
          onMouseButton?(2, true)
          onMouseButton?(2, false)
        }
        twoFingerRouting = false
        onMouseButton?(1, false)
      } else if !twoFingerRouting {
        onMouse?(point)
      }
    }
  }

  private func beginTwoFingerGesture() {
    guard activeTouches.count == 2 else { return }
    twoFingerRouting = true
    onMouseButton?(1, false)
    let points = Array(activeTouches.values)
    twoFinger.begin(points)
  }

  private func handleTwoFingerMove() {
    guard activeTouches.count == 2 else { return }
    for key in twoFinger.move(Array(activeTouches.values), scrollEnabled: true) {
      wheel.add(key)
    }
  }

  private func virtualKey(_ key: UIKey) -> Int? {
    switch key.keyCode.rawValue {
    case 0x04...0x1D:
      return Int(key.keyCode.rawValue - 0x04 + 65)
    case 0x1E:
      return 49
    case 0x1F...0x26:
      return Int(key.keyCode.rawValue - 0x1F + 50)
    case 0x27:
      return 48
    case 0x28:
      return 13
    case 0x29:
      return 27
    case 0x2A:
      return 8
    case 0x2B:
      return 9
    case 0x2C:
      return 32
    case 0x4F:
      return 39
    case 0x50:
      return 37
    case 0x51:
      return 40
    case 0x52:
      return 38
    case 0x3A...0x45:
      return Int(key.keyCode.rawValue - 0x3A + 112)
    case 0xE0, 0xE4:
      return 17
    case 0xE1, 0xE5:
      return 16
    case 0xE2, 0xE6:
      return 18
    default:
      return nil
    }
  }

  private func stagePoint(_ point: CGPoint) -> CGPoint {
    let scaleX = stageSize.width / max(bounds.width, 1)
    let scaleY = stageSize.height / max(bounds.height, 1)
    return CGPoint(
      x: min(max(point.x * scaleX, 0), max(stageSize.width - 1, 0)),
      y: min(max(point.y * scaleY, 0), max(stageSize.height - 1, 0))
    )
  }

  private var displayScale: CGFloat {
    max(bounds.width / max(stageSize.width, 1), 0.0001)
  }

  private func updateCursorLayer() {
    cursorLayer.isHidden = !touchpadEnabled
    let scale = displayScale
    let point = CGPoint(
      x: touchpad.position.x * scale,
      y: touchpad.position.y * scale
    )
    let path = UIBezierPath(ovalIn: CGRect(
      x: point.x - 7,
      y: point.y - 7,
      width: 14,
      height: 14
    ))
    cursorLayer.path = path.cgPath
  }

  private func nextPointerID() -> UInt32 {
    var value = UInt32.random(in: 1...UInt32.max)
    while pointerIDs.values.contains(value) {
      value = UInt32.random(in: 1...UInt32.max)
    }
    return value
  }
}
