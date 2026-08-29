import CoreGraphics

enum AspectFit {
    static func size(content: CGSize, inside container: CGSize) -> CGSize {
        guard content.width > 0,
              content.height > 0,
              container.width > 0,
              container.height > 0 else {
            return .zero
        }

        let scale = min(
            container.width / content.width,
            container.height / content.height
        )

        return CGSize(
            width: content.width * scale,
            height: content.height * scale
        )
    }
}
