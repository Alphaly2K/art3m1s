import Metal
import QuartzCore
import SwiftUI
import UIKit

struct MetalHostView: UIViewRepresentable {
  let onLayerReady: (CAMetalLayer, CGSize) -> Void

  func makeUIView(context: Context) -> MetalLayerView {
    let view = MetalLayerView()
    view.onLayerReady = onLayerReady
    return view
  }

  func updateUIView(_ uiView: MetalLayerView, context: Context) {
    uiView.onLayerReady = onLayerReady
    uiView.setNeedsLayout()
  }
}

final class MetalLayerView: UIView {
  var onLayerReady: ((CAMetalLayer, CGSize) -> Void)?
  private var lastSize = CGSize.zero

  override class var layerClass: AnyClass {
    CAMetalLayer.self
  }

  var metalLayer: CAMetalLayer {
    layer as! CAMetalLayer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = true
    backgroundColor = .black
    metalLayer.framebufferOnly = true
    metalLayer.presentsWithTransaction = false
    metalLayer.magnificationFilter = .linear
    metalLayer.minificationFilter = .linear
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let displayScale = max(
      contentScaleFactor,
      window?.screen.scale ?? UIScreen.main.scale
    )
    let size = CGSize(
      width: max(bounds.width * displayScale, 1),
      height: max(bounds.height * displayScale, 1)
    )
    metalLayer.contentsScale = displayScale
    guard size != lastSize else { return }
    lastSize = size
    onLayerReady?(metalLayer, size)
  }
}
