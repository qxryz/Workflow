import SwiftUI

@MainActor
struct RegistrationPanel<Content: View>: View {
    let title: String
    let icon: String
    let help: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.callout.weight(.semibold))
                HelpBadge(text: help)
                Spacer()
            }
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.secondary.opacity(0.14)))
    }
}

@MainActor
struct RegistrationFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .frame(width: 106, alignment: .leading)
    }
}

@MainActor
struct RegistrationInputSlotRow: View {
    @Binding var slot: ModelRegistrationInputSlot
    let interfaceTemplateId: String?
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: slot.modality.symbolName)
                    .foregroundStyle(Color.accentColor)
                TextField("Input", text: $slot.label)
                Picker("", selection: $slot.source) {
                    ForEach(ModelRegistrationSlotSource.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 92)
                Toggle("Required", isOn: $slot.required)
                    .labelsHidden()
                Image(systemName: "asterisk")
                    .font(.caption2)
                    .foregroundStyle(slot.required ? .orange : .secondary)
                Button(action: onMoveUp) { Image(systemName: "arrow.up") }
                Button(action: onMoveDown) { Image(systemName: "arrow.down") }
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
            }
            .buttonStyle(.borderless)
            HStack {
                Picker("", selection: $slot.modality) {
                    ForEach(Modality.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                TextField("input.image_url", text: $slot.parameterPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                Toggle("[]", isOn: $slot.acceptsMultiple)
                    .help("Array / Multiple values")
                if slot.availableValueFormats.count > 1 {
                    Picker("", selection: $slot.valueFormat) {
                        ForEach(slot.availableValueFormats) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 108)
                    .help("Choose how this attachment is serialized into the request.")
                }
            }
            if slot.source == .fixedValue {
                TextField("fixed value", text: $slot.fixedValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }
            DisclosureGroup("Advanced mapping") {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Collect values into an array", isOn: $slot.collectsAsArray)
                        TextField(#"Optional JSON wrapper, use "$value""#, text: $slot.valueTemplateJSON, axis: .vertical)
                            .lineLimit(3...7)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    inputWrapperTemplateSidebar
                        .frame(width: 190, alignment: .topLeading)
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let modality = Modality(rawValue: raw) else { return false }
            slot.modality = modality
            slot.source = modality == .text ? .prompt : .attachment
            slot.normalizeValueFormat()
            return true
        }
        .onChange(of: slot.modality) {
            slot.normalizeValueFormat()
        }
        .onChange(of: slot.source) {
            slot.normalizeValueFormat()
        }
    }

    private var inputWrapperTemplateSidebar: some View {
        let recommended = InputWrapperTemplateRegistry.recommended(
            for: slot,
            interfaceTemplateId: interfaceTemplateId
        )
        let additional = InputWrapperTemplateRegistry.additional(
            for: slot,
            interfaceTemplateId: interfaceTemplateId
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(Color.accentColor)
                Text("常用模板")
                    .font(.caption.weight(.semibold))
            }
            Text("选择后仍可继续编辑")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(recommended) { template in
                inputWrapperTemplateButton(template)
            }
            if !additional.isEmpty {
                DisclosureGroup("更多模板") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(additional) { template in
                            inputWrapperTemplateButton(template)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption2.weight(.medium))
            }
        }
    }

    private func inputWrapperTemplateButton(_ template: InputWrapperTemplate) -> some View {
        Button {
            var updated = slot
            template.apply(to: &updated)
            slot = updated
        } label: {
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(template.title)
                        .font(.caption)
                        .lineLimit(1)
                    Text(template.protocolFamily.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if slot.valueTemplateJSON == template.wrapperJSON,
                   slot.collectsAsArray == template.collectsAsArray {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .quickHelp(template.wrapperJSON.isEmpty ? template.help : "\(template.help)\n\n\(template.wrapperJSON)")
    }
}

@MainActor
struct RegistrationOutputSlotRow: View {
    @Binding var slot: ModelRegistrationOutputSlot
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: slot.modality.symbolName)
                .foregroundStyle(Color.accentColor)
            TextField("Output", text: $slot.label)
            Picker("", selection: $slot.kind) {
                ForEach(ModelRegistrationOutputKind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 88)
            Picker("", selection: $slot.modality) {
                ForEach(Modality.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 110)
            TextField("output.results.*.url", text: $slot.jsonPath)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

@MainActor
struct RegistrationPollingFields: View {
    @Binding var polling: ModelRegistrationPolling

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(summaryText, systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 7) {
                pollingRow(title: "Task ID", text: $polling.taskIdPath)
                pollingRow(title: "Polling Path", text: $polling.pollingPath)
                GridRow {
                    RegistrationFieldLabel("Method")
                    Picker("", selection: $polling.method) {
                        ForEach(EndpointHTTPMethod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                pollingRow(title: "Status", text: $polling.statusPath)
                pollingRow(title: "Success", text: Binding(get: { polling.successValues.joined(separator: ", ") }, set: { polling.successValues = split($0) }))
                pollingRow(title: "Failure", text: Binding(get: { polling.failureValues.joined(separator: ", ") }, set: { polling.failureValues = split($0) }))
                GridRow {
                    RegistrationFieldLabel("Interval")
                    Stepper("\(polling.intervalSeconds)s", value: $polling.intervalSeconds, in: 1...120)
                }
                GridRow {
                    RegistrationFieldLabel("Attempts")
                    Stepper("\(polling.maxAttempts)", value: $polling.maxAttempts, in: 1...1000)
                }
            }
        }
    }

    private var summaryText: String {
        let totalSeconds = polling.intervalSeconds * polling.maxAttempts
        return "Polling: \(polling.method.rawValue) \(polling.pollingPath), every \(polling.intervalSeconds)s, up to \(polling.maxAttempts)x (~\(formattedDuration(totalSeconds))). Status: \(polling.statusPath)"
    }

    private func formattedDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    private func pollingRow(title: String, text: Binding<String>) -> some View {
        GridRow {
            RegistrationFieldLabel(title)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
        }
    }

    private func split(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

@MainActor
struct RegistrationHeaderFields: View {
    @Binding var headers: [String: String]
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Headers")
                .font(.caption.weight(.semibold))
            TextEditor(text: $text)
                .font(.caption.monospaced())
                .frame(minHeight: 55)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.2)))
                .onAppear { text = headers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n") }
                .onChange(of: text) { _, value in
                    headers = Dictionary(uniqueKeysWithValues: value.split(separator: "\n").compactMap { line in
                        guard let colon = line.firstIndex(of: ":") else { return nil }
                        return (
                            String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                            String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        )
                    })
                }
        }
    }
}
