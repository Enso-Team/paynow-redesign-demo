import Testing
@testable import digibank

struct SGMobileTests {
    @Test(arguments: [
        ("+65 9123 4567", "91234567"),
        ("6591234567", "91234567"),
        ("9123-4567", "91234567"),
        ("(+65) 91234567", "91234567"),
        ("+65\u{00A0}8765\u{00A0}4321", "87654321"),
    ])
    func readsSingaporeMobiles(phone: String, mobile: String) {
        #expect(SGMobile.normalize(phone) == mobile)
    }

    @Test(arguments: ["+44 7700 900123", "+60 12-345 6789", "6123 4567", "+65 6123 4567", "912345", "9123456a"])
    func rejectsEverythingElse(phone: String) {
        #expect(SGMobile.normalize(phone) == nil)
    }

    @Test func displaysWithCountryCode() {
        #expect(SGMobile.display("91234567") == "+65 9123 4567")
    }
}

struct ContactDirectoryTests {
    let book: [(name: String, phones: [String])] = [
        ("Wei Ling Tan", ["+65 9123 4567", "6123 4567"]),
        ("Ahmad Rahman", ["8765 4321", "+65 9876 5432", "87654321"]),
        ("Office", ["6222 3333"]),
        ("Émile Durand", ["+44 7700 900123", "9000 0003"]),
        ("123 Movers", ["8111 2222"]),
        ("", ["9555 6666"]),
    ]

    @Test func keepsOneRowPerSingaporeMobile() {
        let entries = ContactDirectory.entries(book)
        #expect(entries.map(\.mobile).sorted() == ["81112222", "87654321", "90000003", "91234567", "95556666", "98765432"])
        #expect(!entries.contains { $0.name == "Office" })
        #expect(entries.filter { $0.name == "Ahmad Rahman" }.map(\.mobile) == ["87654321", "98765432"])
    }

    @Test func sortsByName() {
        let names = ContactDirectory.entries(book).map(\.name)
        #expect(names == ["+65 9555 6666", "123 Movers", "Ahmad Rahman", "Ahmad Rahman", "Émile Durand", "Wei Ling Tan"])
    }

    @Test func groupsByFirstLetterWithHashLast() {
        let sections = ContactDirectory.sections(ContactDirectory.entries(book))
        #expect(sections.map(\.letter) == ["A", "E", "W", "#"])
        #expect(sections[0].entries.count == 2)
        #expect(sections[3].entries.map(\.name) == ["+65 9555 6666", "123 Movers"])
    }

    @Test func searchesNameAndDigits() {
        let entries = ContactDirectory.entries(book)
        #expect(ContactDirectory.search(entries, "wei").map(\.name) == ["Wei Ling Tan"])
        #expect(ContactDirectory.search(entries, "emile").map(\.name) == ["Émile Durand"])
        #expect(ContactDirectory.search(entries, "9123 45").map(\.mobile) == ["91234567"])
        #expect(ContactDirectory.search(entries, "+65 9876").map(\.mobile) == ["98765432"])
        #expect(ContactDirectory.search(entries, "  ").count == entries.count)
        #expect(ContactDirectory.search(entries, "zzz").isEmpty)
    }

    @Test func initials() {
        #expect(ContactEntry(name: "Wei Ling Tan", mobile: "91234567").initials == "WL")
        #expect(ContactEntry(name: "ahmad", mobile: "91234567").initials == "A")
    }
}
