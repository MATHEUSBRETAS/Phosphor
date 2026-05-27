import Foundation

/// Maps iMessage handle identifiers (phone numbers, email addresses) back to a
/// contact display name. Built once from the backup's `AddressBook.sqlitedb`
/// and queried during chat / message rendering so participants no longer show
/// up as bare phone numbers.
///
/// Phone numbers are matched on the last 10 digits to gloss over country-code,
/// formatting, and leading-zero variations that differ between Contacts and
/// the SMS handle table.
struct ContactDirectory {

    static let empty = ContactDirectory(phones: [:], emails: [:])

    private let phones: [String: String]
    private let emails: [String: String]

    var isEmpty: Bool { phones.isEmpty && emails.isEmpty }

    private init(phones: [String: String], emails: [String: String]) {
        self.phones = phones
        self.emails = emails
    }

    /// Build a directory from the contacts pulled out of the backup.
    init(contacts: [ContactsExtractor.Contact]) {
        var phones: [String: String] = [:]
        var emails: [String: String] = [:]
        for contact in contacts {
            let name = contact.fullName
            guard !name.isEmpty else { continue }
            for raw in contact.phoneNumbers {
                let key = Self.normalizedPhone(raw)
                if !key.isEmpty { phones[key] = name }
            }
            for raw in contact.emails {
                emails[raw.lowercased()] = name
            }
        }
        self.phones = phones
        self.emails = emails
    }

    /// Try to resolve a single handle (phone or email) to a contact name.
    func name(forHandle handle: String) -> String? {
        if handle.isEmpty { return nil }
        if handle.contains("@") {
            return emails[handle.lowercased()]
        }
        let key = Self.normalizedPhone(handle)
        guard !key.isEmpty else { return nil }
        return phones[key]
    }

    /// Resolve the handle, falling back to the raw identifier when no contact
    /// matches. Callers use this for sender labels so the bubble never shows
    /// an empty string.
    func displayName(forHandle handle: String) -> String {
        name(forHandle: handle) ?? handle
    }

    /// Build a "Alice, Bob, Charlie" style title for a group chat from its
    /// participant handles. Returns an empty string if no participants resolve.
    func groupTitle(participants: [String], limit: Int = 4) -> String {
        let names = participants.map { displayName(forHandle: $0) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return "" }
        if names.count <= limit {
            return names.joined(separator: ", ")
        }
        let head = names.prefix(limit).joined(separator: ", ")
        return "\(head) +\(names.count - limit)"
    }

    /// Last-10-digit fingerprint used as the phone lookup key. Empty input or
    /// non-digit-only handles return an empty string so we don't accidentally
    /// fold every unrecognised handle to the same bucket.
    static func normalizedPhone(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        if digits.count >= 10 { return String(digits.suffix(10)) }
        return digits
    }
}
