import AppKit
import Metal
import MetalKit
import QuartzCore
import simd

private struct EdgeGlowUniforms {
    var size: SIMD2<Float>
    var time: Float
    var fadeInDuration: Float
    var fadeOutStart: Float
    var fadeOutEnd: Float
    var animateThickness: Float
    var animateFade: Float
    var thickness: Float
    var glowWidth: Float
    var waveDensity: Float
    var waveSpeed: Float
    var primaryColor: SIMD3<Float>
    var accentColor: SIMD3<Float>

    init(size: SIMD2<Float>, time: Float) {
        self.size = size
        self.time = time
        self.fadeInDuration = EdgeGlowSettings.value(EdgeGlowSettings.fadeInDurationKey)
        self.fadeOutStart = EdgeGlowSettings.value(EdgeGlowSettings.fadeOutStartKey)
        self.fadeOutEnd = EdgeGlowSettings.value(EdgeGlowSettings.fadeOutEndKey)
        self.animateThickness = EdgeGlowSettings.animateThickness ? 1 : 0
        self.animateFade = EdgeGlowSettings.animateFade ? 1 : 0
        self.thickness = EdgeGlowSettings.value(EdgeGlowSettings.thicknessKey)
        self.glowWidth = EdgeGlowSettings.value(EdgeGlowSettings.glowWidthKey)
        self.waveDensity = EdgeGlowSettings.value(EdgeGlowSettings.waveDensityKey)
        self.waveSpeed = EdgeGlowSettings.value(EdgeGlowSettings.waveSpeedKey)
        self.primaryColor = EdgeGlowColorSettings.primarySIMD()
        self.accentColor = EdgeGlowColorSettings.accentSIMD()
    }
}

final class EdgeGlowOverlayView: MTKView, SwitchOverlayRenderable {
    private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
          float4 position [[position]];
          float2 uv;
        };

        struct Uniforms {
          float2 size;
          float time;
          float fadeInDuration;
          float fadeOutStart;
          float fadeOutEnd;
          float animateThickness;
          float animateFade;
          float thickness;
          float glowWidth;
          float waveDensity;
          float waveSpeed;
          float3 primaryColor;
          float3 accentColor;
        };

        vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
          float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
          };

          VertexOut out;
          out.position = float4(positions[vertexID], 0.0, 1.0);
          out.uv = positions[vertexID] * 0.5 + 0.5;
          return out;
        }

        float perimeterPosition(float2 pixel, float2 size) {
          if (pixel.y < pixel.x && pixel.y < size.x - pixel.x) {
            return pixel.x;
          } else if (size.x - pixel.x < pixel.y && size.x - pixel.x < size.y - pixel.y) {
            return size.x + pixel.y;
          } else if (size.y - pixel.y < pixel.x && size.y - pixel.y < size.x - pixel.x) {
            return size.x + size.y + (size.x - pixel.x);
          } else {
            return 2.0 * size.x + size.y + (size.y - pixel.y);
          }
        }

        float4 edgeGlowEffect(
          float edgeDistance,
          float perimeter,
          float perimeterLength,
          float t,
          float thicknessScale,
          float fadeEnvelope,
          constant Uniforms &uniforms
        ) {
          float effectiveThickness = uniforms.thickness * thicknessScale;
          float effectiveGlowWidth = uniforms.glowWidth * thicknessScale;
          if (effectiveThickness <= 0.0 && effectiveGlowWidth <= 0.0) {
            return float4(uniforms.primaryColor, 0.0);
          }

          float thickness = max(0.001, effectiveThickness);
          float glowWidth = max(0.001, effectiveGlowWidth);

          float wave = sin((perimeter / max(perimeterLength, 1.0)) * uniforms.waveDensity - t * uniforms.waveSpeed) * 0.5 + 0.5;
          float waveScale = 0.58 + 0.42 * wave;
          float border = 1.0 - smoothstep(thickness * waveScale, (thickness + 3.2) * waveScale, edgeDistance);
          float glow = 1.0 - smoothstep(0.0, glowWidth * waveScale, edgeDistance);

          float glowAlpha = glow * 0.35 * fadeEnvelope;
          float borderAlpha = border * 0.98 * fadeEnvelope;

          float alpha = borderAlpha + glowAlpha * (1.0 - borderAlpha);
          float3 color = uniforms.primaryColor;
          if (alpha > 0.001) {
            color =
              (uniforms.primaryColor * borderAlpha
                + uniforms.accentColor * glowAlpha * (1.0 - borderAlpha)) / alpha;
          }
          return float4(color, alpha);
        }

        fragment half4 fragment_main(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(0)]]) {
          float2 pixel = clamp(in.uv, 0.0, 1.0) * uniforms.size;
          float edgeDistance = min(min(pixel.x, uniforms.size.x - pixel.x), min(pixel.y, uniforms.size.y - pixel.y));
          float t = uniforms.time;
          float fadeInDuration = max(uniforms.fadeInDuration, 0.01);
          float fadeOutStart = max(uniforms.fadeOutStart, 0.0);
          float fadeOutEnd = max(uniforms.fadeOutEnd, fadeOutStart + 0.01);
          float intro = 1.0 - pow(1.0 - clamp(t / fadeInDuration, 0.0, 1.0), 3.0);
          float outro = 1.0 - smoothstep(fadeOutStart, fadeOutEnd, t);
          float thicknessScale = (uniforms.animateThickness > 0.5) ? intro * outro : 1.0;
          float fadeEnvelope = (uniforms.animateFade > 0.5) ? intro * outro : 1.0;
          float perimeter = perimeterPosition(pixel, uniforms.size);
          float perimeterLength = 2.0 * (uniforms.size.x + uniforms.size.y);

          float4 effect = edgeGlowEffect(
            edgeDistance, perimeter, perimeterLength, t, thicknessScale, fadeEnvelope, uniforms);

          float alpha = clamp(effect.a, 0.0, 1.0);
          return half4(half3(effect.rgb * alpha), half(alpha));
        }
        """

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var lastDrawMediaTime: CFTimeInterval?
    private var playedTime: CFTimeInterval = 0
    private var playCompletion: (() -> Void)?
    private var animationDuration: CFTimeInterval {
        TimeInterval(EdgeGlowSettings.value(EdgeGlowSettings.durationKey))
    }

    static func make(frame: NSRect) -> EdgeGlowOverlayView? {
        guard let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let pipelineState = makePipelineState(device: device)
        else {
            return nil
        }

        return EdgeGlowOverlayView(
            frame: frame,
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState
        )
    }

    private init(
        frame frameRect: NSRect,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipelineState: MTLRenderPipelineState
    ) {
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        super.init(frame: frameRect, device: device)

        isPaused = true
        enableSetNeedsDisplay = false
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.masksToBounds = true
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func play(completion: (() -> Void)?) {
        playCompletion = completion
        lastDrawMediaTime = nil
        playedTime = 0
        isPaused = false
        draw()
    }

    private static func makePipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to create edge glow overlay Metal pipeline: \(error)")
            return nil
        }
    }
}

extension EdgeGlowOverlayView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        if let lastDrawMediaTime {
            playedTime += now - lastDrawMediaTime
        }
        lastDrawMediaTime = now

        if playedTime >= animationDuration {
            isPaused = true
            if let completion = playCompletion {
                playCompletion = nil
                completion()
            }
            return
        }

        let elapsed = playedTime

        guard let descriptor = currentRenderPassDescriptor,
            let drawable = currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        var uniforms = EdgeGlowUniforms(
            size: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            time: Float(elapsed)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<EdgeGlowUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
