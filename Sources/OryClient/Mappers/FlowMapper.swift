import Foundation
import OrySDK

/// Maps a generated SDK flow DTO and its `UiContainer` into a domain ``OryFlow``.
///
/// This is where the server-driven UI is interpreted: nodes become renderable
/// ``OryNode`` values, submit buttons become ``OryFlow/actions``, and hidden and
/// default field values are collected into the flow's submission so the integrator
/// never handles them.
enum FlowMapper {

    static func login(_ flow: OrySDKAPI.LoginFlow) -> OryFlow {
        let requestedAAL = flow.requestedAal.flatMap { OryAuthenticatorAssuranceLevel(rawValue: $0.rawValue) }
        let isRefresh = flow.refresh == true
        return make(
            id: flow.id,
            expiresAt: flow.expiresAt,
            ui: flow.ui,
            kind: .login,
            requestedAAL: requestedAAL,
            isRefresh: isRefresh,
            sendsSessionToken: isRefresh || (requestedAAL ?? .aal1) >= .aal2
        )
    }

    static func registration(_ flow: OrySDKAPI.RegistrationFlow) -> OryFlow {
        make(id: flow.id, expiresAt: flow.expiresAt, ui: flow.ui, kind: .registration)
    }

    static func verification(_ flow: OrySDKAPI.VerificationFlow) -> OryFlow {
        make(id: flow.id, expiresAt: flow.expiresAt, ui: flow.ui, kind: .verification)
    }

    static func recovery(_ flow: OrySDKAPI.RecoveryFlow) -> OryFlow {
        make(id: flow.id, expiresAt: flow.expiresAt, ui: flow.ui, kind: .recovery)
    }

    static func settings(_ flow: OrySDKAPI.SettingsFlow) -> OryFlow {
        make(id: flow.id, expiresAt: flow.expiresAt, ui: flow.ui, kind: .settings)
    }

    /// Builds an ``OryFlow`` from any flow's identity, expiry, and UI container. The
    /// UI parsing is identical across flow kinds — only the `kind` differs.
    private static func make(
        id: String,
        expiresAt: Date?,
        ui: OrySDKAPI.UiContainer,
        kind: OryFlowKind,
        requestedAAL: OryAuthenticatorAssuranceLevel? = nil,
        isRefresh: Bool = false,
        sendsSessionToken: Bool = false
    ) -> OryFlow {
        let parsed = parse(ui)
        return OryFlow(
            id: id,
            kind: kind,
            expiresAt: expiresAt,
            messages: (ui.messages ?? []).map(MessageMapper.flatMap),
            nodes: parsed.nodes,
            actions: parsed.actions,
            requestedAAL: requestedAAL,
            isRefresh: isRefresh,
            submission: OrySubmission(
                action: URL(string: ui.action) ?? OrySubmission.placeholder.action,
                method: ui.method,
                values: parsed.values,
                sendsSessionToken: sendsSessionToken
            )
        )
    }

    // MARK: - UI container parsing

    private struct ParsedUI {
        var nodes: [OryNode] = []
        var actions: [OryInputField] = []
        var values: [String: String] = [:]
    }

    private static func parse(_ ui: OrySDKAPI.UiContainer) -> ParsedUI {
        var result = ParsedUI()
        let group = { (node: OrySDKAPI.UiNode) in OryNodeGroup(rawValue: node.group) }

        for node in ui.nodes {
            let messages = node.messages.map(MessageMapper.flatMap)

            switch node.attributes {
            case let .typeUiNodeInputAttributes(input):
                let field = inputField(input, meta: node.meta, group: group(node))

                if field.kind.isSubmit {
                    // Buttons are offered as actions; their value is submitted only
                    // when pressed.
                    result.actions.append(field)
                } else if field.kind == .hidden {
                    // Hidden fields are carried for submission but never rendered.
                    result.values[field.name.rawValue] = field.value ?? ""
                } else {
                    result.values[field.name.rawValue] = field.value ?? ""
                    result.nodes.append(
                        OryNode(id: field.name.rawValue, group: group(node), messages: messages, content: .input(field))
                    )
                }

            case let .typeUiNodeTextAttributes(text):
                result.nodes.append(
                    OryNode(id: text.id, group: group(node), messages: messages, content: .text(text.text.text))
                )

            case let .typeUiNodeImageAttributes(image):
                if let url = URL(string: image.src) {
                    result.nodes.append(
                        OryNode(id: image.id, group: group(node), messages: messages, content: .image(url: url))
                    )
                }

            case let .typeUiNodeAnchorAttributes(anchor):
                if let url = URL(string: anchor.href) {
                    result.nodes.append(
                        OryNode(
                            id: anchor.id,
                            group: group(node),
                            messages: messages,
                            content: .link(label: anchor.title.text, url: url)
                        )
                    )
                }

            case .typeUiNodeScriptAttributes, .typeUiNodeDivisionAttributes, .unknownDefaultOpenApi:
                // Not meaningful for native UI, or a node type newer than this build. Skipping
                // it keeps the rest of the flow renderable.
                continue
            }
        }

        return result
    }

    // MARK: - Input mapping

    private static func inputField(
        _ input: OrySDKAPI.UiNodeInputAttributes,
        meta: OrySDKAPI.UiNodeMeta,
        group: OryNodeGroup
    ) -> OryInputField {
        OryInputField(
            name: OryFieldName(rawValue: input.name),
            kind: OryInputField.Kind(rawValue: input.type),
            label: input.label?.text ?? meta.label?.text,
            value: stringValue(input.value),
            isRequired: input._required ?? false,
            isDisabled: input.disabled,
            autocomplete: input.autocomplete.map(OryInputField.Autocomplete.init(rawValue:)),
            options: (input.options ?? []).map { OryInputField.Option(value: stringValue($0.value) ?? "") },
            group: group
        )
    }

    /// Renders an input's value as a string for submission. Login fields are strings;
    /// non-string JSON values are coerced best-effort.
    private static func stringValue(_ value: JSONValue?) -> String? {
        switch value {
        case .none, .some(.null):
            return nil
        case let .some(.string(string)):
            return string
        case let .some(.int(int)):
            return String(int)
        case let .some(.double(double)):
            return String(double)
        case let .some(.bool(bool)):
            return String(bool)
        case .some(.array), .some(.dictionary):
            return nil
        }
    }
}
