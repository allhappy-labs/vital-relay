import HealthSyncCore
import SwiftUI

struct PairingEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(AppModel.self) private var model

  private let pairingID: UUID
  @State private var entityID: String
  @State private var destination: HealthObjectTypeID
  @State private var sourceUnit: UnitSymbol
  @State private var transformationKind: TransformationKind
  @State private var primaryConstant: String
  @State private var offsetConstant: String
  @State private var isEnabled: Bool
  @State private var localError: String?

  init(pairing: Pairing?) {
    let initialDestination = pairing?.destination ?? .bodyMass
    let nativeUnit = WritableHealthRegistry[initialDestination]?.nativeUnit ?? .kilograms
    pairingID = pairing?.id ?? UUID()
    _entityID = State(initialValue: pairing?.entityID ?? "")
    _destination = State(initialValue: initialDestination)
    _sourceUnit = State(initialValue: pairing?.sourceUnit ?? nativeUnit)
    _transformationKind = State(initialValue: .init(pairing?.transformation ?? .identity))
    _primaryConstant = State(
      initialValue: Self.primaryConstant(for: pairing?.transformation ?? .identity)
    )
    _offsetConstant = State(
      initialValue: Self.offsetConstant(for: pairing?.transformation ?? .identity)
    )
    _isEnabled = State(initialValue: pairing?.isEnabled ?? true)
  }

  var body: some View {
    Form {
      Section {
        TextField("Entity ID", text: $entityID)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("pairing-entity-id")
      } header: {
        Text("Home Assistant")
      } footer: {
        Text("Use a numeric entity such as sensor.body_mass.")
      }

      Section {
        WritableDestinationPicker(selection: $destination)
        Picker("Source unit", selection: $sourceUnit) {
          ForEach(compatibleSourceUnits, id: \.self) { unit in
            Text(unit.rawValue).tag(unit)
          }
        }
        .accessibilityIdentifier("pairing-source-unit")
        LabeledContent("HealthKit unit", value: destinationDefinition.nativeUnit.rawValue)
          .accessibilityIdentifier("pairing-destination-unit")
        Toggle("Enabled", isOn: $isEnabled)
          .accessibilityIdentifier("pairing-enabled")
      } header: {
        Text("Apple Health")
      } footer: {
        Text("The destination unit is fixed to HealthKit's native unit.")
      }

      Section {
        Picker("Transformation", selection: $transformationKind) {
          ForEach(TransformationKind.allCases) { kind in
            Text(kind.title).tag(kind)
          }
        }
        .accessibilityIdentifier("pairing-transformation")

        if transformationKind.needsPrimaryConstant {
          TextField(transformationKind.primaryLabel, text: $primaryConstant)
            .keyboardType(.numbersAndPunctuation)
            .accessibilityIdentifier("pairing-primary-constant")
        }
        if transformationKind == .affine {
          TextField("Offset", text: $offsetConstant)
            .keyboardType(.numbersAndPunctuation)
            .accessibilityIdentifier("pairing-offset-constant")
        }
      } header: {
        Text("Optional transformation")
      } footer: {
        Text("Transforms are applied before unit conversion and plausible-bounds validation.")
      }

      Section("Permission") {
        Button("Request Health Write Access") {
          Task { await model.requestHealthWriteAuthorization(for: [destination]) }
        }
        .accessibilityIdentifier("request-health-write-access")
        Text("Saving a pairing does not automatically request or broaden Health permissions.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if let errorMessage {
        Section("Cannot save") {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .accessibilityIdentifier("pairing-validation-error")
        }
      }
    }
    .navigationTitle(entityID.isEmpty ? "New Pairing" : "Edit Pairing")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          Task { await save() }
        }
        .accessibilityIdentifier("save-pairing")
      }
    }
    .onChange(of: destination) { _, newDestination in
      guard let definition = WritableHealthRegistry[newDestination] else { return }
      if !isCompatible(sourceUnit, with: definition.nativeUnit) {
        sourceUnit = definition.nativeUnit
      }
      localError = nil
    }
  }

  private var destinationDefinition: WritableHealthType {
    WritableHealthRegistry[destination] ?? WritableHealthRegistry.all[0]
  }

  private var compatibleSourceUnits: [UnitSymbol] {
    UnitSymbol.allCases.filter { isCompatible($0, with: destinationDefinition.nativeUnit) }
  }

  private var errorMessage: String? {
    localError ?? model.pairingValidationError.map(Self.message(for:))
  }

  private func save() async {
    guard let transformation = selectedTransformation else {
      localError = "Enter finite numeric transformation values."
      return
    }
    let pairing = Pairing(
      id: pairingID,
      entityID: entityID,
      destination: destination,
      sourceUnit: sourceUnit,
      destinationUnit: destinationDefinition.nativeUnit,
      transformation: transformation,
      isEnabled: isEnabled
    )
    if await model.savePairing(pairing) {
      dismiss()
    }
  }

  private var selectedTransformation: PairingTransformation? {
    switch transformationKind {
    case .identity:
      return .identity
    case .multiply:
      guard let value = Double(primaryConstant), value.isFinite else { return nil }
      return .multiply(value)
    case .add:
      guard let value = Double(primaryConstant), value.isFinite else { return nil }
      return .add(value)
    case .affine:
      guard let scale = Double(primaryConstant), scale.isFinite,
        let offset = Double(offsetConstant), offset.isFinite
      else { return nil }
      return .affine(scale: scale, offset: offset)
    }
  }

  private func isCompatible(_ source: UnitSymbol, with destination: UnitSymbol) -> Bool {
    (try? UnitConverter.convert(1, from: source, to: destination)) != nil
  }

  private static func primaryConstant(for transformation: PairingTransformation) -> String {
    switch transformation {
    case .identity: ""
    case .multiply(let value), .add(let value): String(value)
    case .affine(let scale, _): String(scale)
    }
  }

  private static func offsetConstant(for transformation: PairingTransformation) -> String {
    guard case .affine(_, let offset) = transformation else { return "" }
    return String(offset)
  }

  private static func message(for error: PairingValidationError) -> String {
    switch error {
    case .invalidEntityID:
      "Enter a lowercase Home Assistant entity ID, such as sensor.body_mass."
    case .destinationNotWritable:
      "That HealthKit destination cannot be written by this app."
    case .incompatibleUnits:
      "The source unit cannot be converted to the HealthKit unit."
    case .invalidDestinationUnit:
      "The destination must use HealthKit's native unit."
    case .nonFiniteTransformation:
      "Transformation values must be finite numbers."
    case .duplicateEnabledPairing:
      "An enabled pairing already uses this entity and destination."
    }
  }
}

private enum TransformationKind: String, CaseIterable, Identifiable {
  case identity
  case multiply
  case add
  case affine

  init(_ transformation: PairingTransformation) {
    switch transformation {
    case .identity: self = .identity
    case .multiply: self = .multiply
    case .add: self = .add
    case .affine: self = .affine
    }
  }

  var id: Self { self }

  var title: String {
    switch self {
    case .identity: "None"
    case .multiply: "Multiply"
    case .add: "Add"
    case .affine: "Multiply and add"
    }
  }

  var needsPrimaryConstant: Bool { self != .identity }

  var primaryLabel: String {
    switch self {
    case .identity: ""
    case .multiply, .affine: "Multiplier"
    case .add: "Amount"
    }
  }
}
