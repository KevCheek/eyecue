import AppKit

/// A slider for the manual scroll speed, shown inside the Scroll Speed menu.
final class SpeedSliderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private let onChange: (Double) -> Void

    init(value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 52))

        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.frame = NSRect(x: 20, y: 28, width: 220, height: 18)
        addSubview(label)

        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.frame = NSRect(x: 18, y: 4, width: 214, height: 22)
        slider.setAccessibilityLabel("Scroll speed in words a minute")
        addSubview(slider)
        show(value)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func changed() {
        let value = (slider.doubleValue / 5).rounded() * 5
        show(value)
        onChange(value)
    }

    private func show(_ value: Double) {
        label.stringValue = "\(Int(value)) words a minute"
    }
}
