import Contacts
import ContactsUI
import SwiftUI

/// Singapore mobile numbers, matching `contactMobile` in packages/paynow-form.
enum SGMobile {
    /// Strips spaces, dashes and brackets, then a leading +65, or 65 when 10 digits remain.
    /// Only 8 digits starting with 8 or 9 count.
    static func normalize(_ phone: String) -> String? {
        var digits = phone.filter { !$0.isWhitespace && !"-()".contains($0) }
        if digits.hasPrefix("+65") {
            digits.removeFirst(3)
        } else if digits.hasPrefix("65"), digits.count == 10 {
            digits.removeFirst(2)
        }
        guard digits.count == 8, let first = digits.first, first == "8" || first == "9",
              digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return digits
    }

    /// "91234567" → "+65 9123 4567"
    static func display(_ mobile: String) -> String {
        "+65 \(mobile.prefix(4)) \(mobile.suffix(4))"
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// One row: a contact's name and one of their Singapore mobiles.
struct ContactEntry: Identifiable, Hashable, Sendable {
    var name: String
    var mobile: String
    var id: String { "\(name)|\(mobile)" }

    var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "#" : letters
    }
}

/// The address book as the list shows it. Pure, so it is unit-tested.
enum ContactDirectory {
    struct Section: Identifiable, Equatable {
        var letter: String
        var entries: [ContactEntry]
        var id: String { letter }
    }

    /// One entry per distinct SG mobile, sorted by name then number. Contacts with none are left out.
    static func entries(_ contacts: [(name: String, phones: [String])]) -> [ContactEntry] {
        var seen = Set<String>()
        var result: [ContactEntry] = []
        for contact in contacts {
            let name = contact.name.trimmingCharacters(in: .whitespaces)
            for phone in contact.phones {
                guard let mobile = SGMobile.normalize(phone) else { continue }
                let entry = ContactEntry(name: name.isEmpty ? SGMobile.display(mobile) : name, mobile: mobile)
                if seen.insert(entry.id).inserted { result.append(entry) }
            }
        }
        return result.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.mobile < $1.mobile : order == .orderedAscending
        }
    }

    /// Groups sorted entries under their first letter. Names that don't start with a letter go under "#", last.
    static func sections(_ entries: [ContactEntry]) -> [Section] {
        var groups: [String: [ContactEntry]] = [:]
        for entry in entries { groups[letter(entry.name), default: []].append(entry) }
        return groups.keys.sorted { a, b in
            if a == "#" || b == "#" { return b == "#" && a != "#" }
            return a < b
        }.map { Section(letter: $0, entries: groups[$0] ?? []) }
    }

    /// Matches the name, or the digits of the number with or without 65.
    static func search(_ entries: [ContactEntry], _ query: String) -> [ContactEntry] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return entries }
        let digits = text.filter(\.isASCIIDigit)
        return entries.filter { entry in
            entry.name.localizedStandardContains(text)
                || (!digits.isEmpty && ("65" + entry.mobile).contains(digits))
        }
    }

    private static func letter(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let first = folded.first, first.isLetter, first.isASCII else { return "#" }
        return String(first).uppercased()
    }
}

/// Contacts access and the fetch. Runs the fetch off the main thread. Nothing leaves the phone.
@MainActor
@Observable
final class ContactsModel {
    enum State: Equatable { case loading, list, denied }

    private(set) var state: State = .loading
    private(set) var entries: [ContactEntry] = []
    private(set) var limited = false

    func load() async {
        let store = CNContactStore()
        var status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
            status = CNContactStore.authorizationStatus(for: .contacts)
        }
        switch status {
        case .authorized, .limited:
            limited = status == .limited
            entries = await Task.detached(priority: .userInitiated) { Self.fetch() }.value
            state = .list
        default:
            state = .denied
        }
    }

    private nonisolated static func fetch() -> [ContactEntry] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var contacts: [(name: String, phones: [String])] = []
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            guard !contact.phoneNumbers.isEmpty else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
            contacts.append((name, contact.phoneNumbers.map(\.value.stringValue)))
        }
        return ContactDirectory.entries(contacts)
    }
}

/// The contacts sheet: title, close, search, then initials rows grouped by letter with an index.
struct ContactsSheet: View {
    var onFinish: (ContactEntry?) -> Void

    @State private var model = ContactsModel()
    @State private var query = ""
    @State private var showAccessPicker = false

    var body: some View {
        VStack(spacing: 0) {
            header
            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .denied:
                denied
            case .list:
                searchField
                list
            }
        }
        .background(.white)
        .preferredColorScheme(.light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contacts.sheet")
        .task { await model.load() }
        .contactAccessPicker(isPresented: $showAccessPicker) { _ in
            Task { await model.load() }
        }
    }

    private var header: some View {
        ZStack {
            Text("Contacts").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.ink)
            HStack {
                Spacer()
                Button { onFinish(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("contacts.close")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 52)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.inkSecondary)
            TextField("Search name or number", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("contacts.search")
        }
        .font(.system(size: 16))
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color(hex: 0xF1F2F4), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var list: some View {
        let matches = ContactDirectory.search(model.entries, query)
        let index = Dictionary(uniqueKeysWithValues: matches.enumerated().map { ($1.id, $0) })
        return List {
            if model.limited {
                Button { showAccessPicker = true } label: {
                    Label("Share more contacts", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.brandBlue)
                }
                .accessibilityIdentifier("contacts.shareMore")
            }
            if matches.isEmpty {
                Text(query.isEmpty ? "No contacts with a Singapore mobile number" : "No matches")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.inkSecondary)
                    .listRowSeparator(.hidden)
            }
            ForEach(ContactDirectory.sections(matches)) { section in
                Section {
                    ForEach(section.entries) { entry in
                        row(entry).accessibilityIdentifier("contacts.row.\(index[entry.id] ?? 0)")
                    }
                } header: {
                    Text(section.letter).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.inkSecondary)
                }
                .sectionIndexLabel(section.letter)
            }
        }
        .listStyle(.plain)
        .listSectionIndexVisibility(.visible)
        .scrollDismissesKeyboard(.immediately)
    }

    private func row(_ entry: ContactEntry) -> some View {
        Button { onFinish(entry) } label: {
            HStack(spacing: 14) {
                Text(entry.initials)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: 0x3F454A))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0xE9EDF1), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.system(size: 16)).foregroundStyle(Color.ink).lineLimit(1)
                    Text(SGMobile.display(entry.mobile)).font(.system(size: 14)).foregroundStyle(Color.inkSecondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var denied: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.inkSecondary)
            Text("Allow Contacts access in Settings to pick someone")
                .font(.system(size: 16))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("contacts.openSettings")
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
