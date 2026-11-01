import SwiftUI
import UIKit

struct MarqueeText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    var isActive: Bool = true
    var speed: CGFloat = 30
    var gap: CGFloat = 36

    func makeUIView(context: Context) -> MarqueeLabelView {
        let view = MarqueeLabelView()
        view.configure(
            text: text,
            font: font,
            textColor: textColor,
            speed: speed,
            gap: gap
        )
        view.setAnimating(isActive)
        return view
    }

    func updateUIView(_ uiView: MarqueeLabelView, context: Context) {
        uiView.configure(
            text: text,
            font: font,
            textColor: textColor,
            speed: speed,
            gap: gap
        )
        uiView.setAnimating(isActive)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MarqueeLabelView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? 280,
            height: proposal.height ?? 34
        )
    }
}

final class MarqueeLabelView: UIView {
    private let contentView = UIView()
    private let primaryLabel = UILabel()
    private let secondaryLabel = UILabel()

    private var text = ""
    private var font = UIFont.systemFont(ofSize: 17, weight: .semibold)
    private var textColor = UIColor.label
    private var speed: CGFloat = 30
    private var gap: CGFloat = 36
    private var isAnimating = false
    private var lastLayoutSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        text: String,
        font: UIFont,
        textColor: UIColor,
        speed: CGFloat,
        gap: CGFloat
    ) {
        let textChanged = self.text != text
        let fontChanged = !self.font.isEqual(font)
        let colorChanged = !self.textColor.isEqual(textColor)
        let metricsChanged = self.speed != speed || self.gap != gap

        guard textChanged || fontChanged || colorChanged || metricsChanged else {
            return
        }

        self.text = text
        self.font = font
        self.textColor = textColor
        self.speed = max(speed, 1)
        self.gap = max(gap, 0)

        primaryLabel.text = text
        secondaryLabel.text = text
        primaryLabel.font = font
        secondaryLabel.font = font
        primaryLabel.textColor = textColor
        secondaryLabel.textColor = textColor
        accessibilityLabel = text
        lastLayoutSize = .zero
        setNeedsLayout()
    }

    func setAnimating(_ animating: Bool) {
        guard isAnimating != animating else { return }
        isAnimating = animating
        applyAnimation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard bounds.width > 0, bounds.height > 0 else { return }
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        layoutLabels()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyAnimation()
    }

    private func setUp() {
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        backgroundColor = .clear

        contentView.backgroundColor = .clear
        addSubview(contentView)

        for label in [primaryLabel, secondaryLabel] {
            label.numberOfLines = 1
            label.lineBreakMode = .byClipping
            label.backgroundColor = .clear
            contentView.addSubview(label)
        }

        secondaryLabel.isHidden = true
    }

    private func layoutLabels() {
        contentView.layer.removeAnimation(forKey: "marquee")
        contentView.layer.transform = CATransform3DIdentity

        let measuredWidth = ceil(
            (text as NSString).size(withAttributes: [.font: font]).width
        )
        let overflows = measuredWidth > bounds.width + 1

        if overflows {
            let contentWidth = measuredWidth * 2 + gap
            contentView.frame = CGRect(
                x: 0,
                y: 0,
                width: contentWidth,
                height: bounds.height
            )
            primaryLabel.frame = CGRect(
                x: 0,
                y: 0,
                width: measuredWidth,
                height: bounds.height
            )
            secondaryLabel.frame = CGRect(
                x: measuredWidth + gap,
                y: 0,
                width: measuredWidth,
                height: bounds.height
            )
            primaryLabel.textAlignment = .left
            secondaryLabel.textAlignment = .left
            secondaryLabel.isHidden = false
        } else {
            contentView.frame = bounds
            primaryLabel.frame = bounds
            primaryLabel.textAlignment = .center
            secondaryLabel.isHidden = true
        }

        applyAnimation()
    }

    private func applyAnimation() {
        contentView.layer.removeAnimation(forKey: "marquee")
        contentView.layer.transform = CATransform3DIdentity

        let textWidth = primaryLabel.frame.width
        let overflows = textWidth > bounds.width + 1

        guard isAnimating,
              overflows,
              window != nil,
              bounds.width > 0 else {
            return
        }

        let distance = textWidth + gap
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -distance
        animation.duration = max(TimeInterval(distance / max(speed, 1)), 2.2)
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        contentView.layer.add(animation, forKey: "marquee")
    }
}
