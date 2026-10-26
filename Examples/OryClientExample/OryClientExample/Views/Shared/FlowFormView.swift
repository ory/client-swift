import OryClient
import SwiftUI

/// Renders any server-driven Ory flow — inputs from `flow.nodes`, buttons from
/// `flow.actions`, messages — so login and registration reuse one view. `OryClient`
/// stays UI-agnostic; this is the glue an integrator writes once.
///
/// When the flow offers several methods (`flow.availableMethods`, for example a password and a
/// one-time code), a picker shows one method at a time: the shared fields such as the
/// identifier stay visible, and only the chosen method's fields and buttons are added.
struct FlowFormView: View {

    let flow: OryFlow
    @Binding var values: OryFormValues
    let isSubmitting: Bool
    let submitError: String?
    let onSubmit: (OryInputField) -> Void

    @State private var selectedMethod: OryNodeGroup?

    /// Device authentication signs with this device's key, so the app offers it on its own
    /// screens (`loginWithDevice`, `authenticateWithDevice`) instead of in the generic form.
    /// Social sign-in and SSO continue in a browser (`browserLocationChangeRequired`), which this
    /// app does not handle, so their buttons are not shown.
    private static let hiddenGroups: Set<OryNodeGroup> = [.deviceAuthn, .oidc, .saml]

    private var methods: [OryNodeGroup] {
        flow.availableMethods.filter { !Self.hiddenGroups.contains($0) }
    }

    private var activeMethod: OryNodeGroup? {
        selectedMethod.flatMap { methods.contains($0) ? $0 : nil } ?? methods.first
    }

    /// A node or action is shown when it is shared, or belongs to the chosen method.
    private func isShown(_ group: OryNodeGroup) -> Bool {
        guard !Self.hiddenGroups.contains(group) else { return false }
        return !methods.contains(group) || methods.count == 1 || group == activeMethod
    }

    var body: some View {
        Form {
            if let submitError {
                Section {
                    Text(submitError).foregroundStyle(.red)
                }
            }

            if !flow.messages.isEmpty {
                Section {
                    ForEach(flow.messages, id: \.id) { message in
                        Text(message.text)
                            .foregroundStyle(message.kind == .error ? .red : .primary)
                    }
                }
            }

            if methods.count > 1 {
                Section {
                    Picker("Method", selection: Binding(get: { activeMethod }, set: { selectedMethod = $0 })) {
                        ForEach(methods, id: \.self) { method in
                            Text(methodTitle(method)).tag(Optional(method))
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                ForEach(flow.nodes.filter { isShown($0.group) }) { node in
                    row(for: node)
                }
            }

            Section {
                ForEach(flow.actions.filter { isShown($0.group) }, id: \.self) { action in
                    Button(actionTitle(for: action)) { onSubmit(action) }
                        .disabled(action.isDisabled)
                }
            }
        }
        .disabled(isSubmitting)
        .overlay {
            if isSubmitting {
                ProgressView().controlSize(.large)
            }
        }
    }

    private func methodTitle(_ method: OryNodeGroup) -> String {
        switch method {
        case .password: "Password"
        case .code: "Email code"
        case .totp: "Authenticator app"
        case .lookupSecret: "Backup code"
        case .profile: "Profile"
        default: method.rawValue
        }
    }

    private func actionTitle(for action: OryInputField) -> String {
        if flow.kind == .settings, action.name == .method {
            switch action.value {
            case "profile": return "Save profile"
            case "password": return "Change password"
            default: break
            }
        }
        return action.label ?? "Continue"
    }

    @ViewBuilder
    private func row(for node: OryNode) -> some View {
        switch node.content {
        case let .input(field):
            FlowInputRow(
                field: field,
                messages: node.messages,
                text: binding(for: field),
                isOn: boolBinding(for: field)
            )
        case let .text(text):
            Text(text)
        case .image where node.id == "totp_qr":
            // The authenticator app QR code arrives inline; `totpSetup` decodes it.
            if let png = flow.totpSetup?.qrCodePNG, let image = UIImage(data: png) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 220)
            }
        case let .image(url):
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
        case let .link(label, url):
            Link(label, destination: url)
        @unknown default:
            EmptyView()
        }
    }

    private func binding(for field: OryInputField) -> Binding<String> {
        Binding(get: { values[field] }, set: { values[field] = $0 })
    }

    private func boolBinding(for field: OryInputField) -> Binding<Bool> {
        Binding(get: { values[field] == "true" }, set: { values[field] = $0 ? "true" : "false" })
    }
}

/// Maps one ``OryInputField`` to a native control by its `kind` and `autocomplete`, so
/// any identity-schema trait (email, phone, custom) renders correctly.
private struct FlowInputRow: View {

    let field: OryInputField
    let messages: [OryUIMessage]
    @Binding var text: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch field.kind {
            case .password:
                SecureField(field.label ?? field.name.rawValue, text: $text)
                    .textContentType(.password)

            case .checkbox:
                Toggle(field.label ?? field.name.rawValue, isOn: $isOn)

            default:
                TextField(field.label ?? field.name.rawValue, text: $text)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            ForEach(messages, id: \.id) { message in
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(field.isDisabled)
    }

    private var keyboardType: UIKeyboardType {
        switch field.kind {
        case .email: return .emailAddress
        case .number: return .numberPad
        case .telephone: return .phonePad
        case .url: return .URL
        default: return field.autocomplete == .oneTimeCode ? .numberPad : .default
        }
    }

    private var textContentType: UITextContentType? {
        guard let autocomplete = field.autocomplete else { return nil }
        switch autocomplete {
        case .email: return .emailAddress
        case .telephone: return .telephoneNumber
        case .url: return .URL
        case .currentPassword: return .password
        case .newPassword: return .newPassword
        case .oneTimeCode: return .oneTimeCode
        case .username, .usernameWebAuthn: return .username
        default: return nil
        }
    }
}

#if DEBUG
#Preview("Form") {
    @Previewable @State var values = OryFormValues()
    FlowFormView(flow: PreviewData.loginFlow(), values: $values, isSubmitting: false, submitError: nil, onSubmit: { _ in })
}

#Preview("Submitting") {
    @Previewable @State var values = OryFormValues()
    FlowFormView(flow: PreviewData.loginFlow(), values: $values, isSubmitting: true, submitError: nil, onSubmit: { _ in })
}

#Preview("Error") {
    @Previewable @State var values = OryFormValues()
    FlowFormView(flow: PreviewData.loginFlow(), values: $values, isSubmitting: false, submitError: "The credentials are invalid.", onSubmit: { _ in })
}
#endif
