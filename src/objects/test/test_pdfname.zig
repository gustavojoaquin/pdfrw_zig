const std = @import("std");
const allocator = std.testing.allocator;
const pdfname = @import("../pdfname.zig");
const PdfName = pdfname.PdfName;
const PdfNameError = pdfname.pdfNameError;

test "PdfName.init_from_raw - simple name" {
    const name = try PdfName.init_from_raw(allocator, "Type");
    defer name.deinit(allocator);

    try std.testing.expectEqualStrings("/Type", name.value);
    try std.testing.expect(name.encoded == null);
    try std.testing.expectEqual(false, name.indirect);
    try std.testing.expectEqualStrings("/Type", name.to_pdf_string());
}

test "PdfName.init_from_raw - with space, requires encoding" {
    const name = try PdfName.init_from_raw(allocator, "Foo Bar");
    defer name.deinit(allocator);

    try std.testing.expectEqualStrings("/Foo Bar", name.value);
    try std.testing.expect(name.encoded != null);
    try std.testing.expectEqualStrings("/Foo#20Bar", name.encoded.?);
    try std.testing.expectEqualStrings("/Foo#20Bar", name.to_pdf_string());
}

test "PdfName.init_from_raw - with hash, requires encoding" {
    const name = try PdfName.init_from_raw(allocator, "My#Name");
    defer name.deinit(allocator);

    try std.testing.expectEqualStrings("/My#Name", name.value);
    try std.testing.expectEqualStrings("/My#23Name", name.encoded.?);
    try std.testing.expectEqualStrings("/My#23Name", name.to_pdf_string());
}

test "PdfName.init_from_encoded - already encoded" {
    const name = try PdfName.init_from_encoded(allocator, "/Another#20Name");
    defer name.deinit(allocator);

    try std.testing.expectEqualStrings("/Another Name", name.value);
    try std.testing.expectEqualStrings("/Another#20Name", name.encoded.?);
    try std.testing.expectEqualStrings("/Another#20Name", name.to_pdf_string());
}

test "PdfName.init_from_encoded - simple, no encoding needed" {
    const name = try PdfName.init_from_encoded(allocator, "/SimpleName");
    defer name.deinit(allocator);

    try std.testing.expectEqualStrings("/SimpleName", name.value);
    // Always set for init_from_encoded, even if no encoding needed
    try std.testing.expect(name.encoded != null);
    try std.testing.expectEqualStrings("/SimpleName", name.encoded.?);
    try std.testing.expectEqualStrings("/SimpleName", name.to_pdf_string());
}

test "PdfName.init_from_encoded - invalid hex sequence" {
    const name = try PdfName.init_from_encoded(allocator, "/Foo#ZZBar");
    defer name.deinit(allocator);

    // Should preserve original value
    try std.testing.expectEqualStrings("/Foo#ZZBar", name.value);
    // Always set for init_from_encoded
    try std.testing.expect(name.encoded != null);
    try std.testing.expectEqualStrings("/Foo#ZZBar", name.encoded.?);
}

test "PdfName.init_from_encoded - has # but decodes to itself (e.g. #23 for literal '#')" {
    const name = try PdfName.init_from_encoded(allocator, "/Path#23Hash");
    defer name.deinit(allocator);

    try std.testing.expectEqualStrings("/Path#Hash", name.value);
    try std.testing.expectEqualStrings("/Path#23Hash", name.encoded.?);
    try std.testing.expectEqualStrings("/Path#23Hash", name.to_pdf_string());
}

test "PdfName.init_from_encoded - invalid format (no leading slash)" {
    const result = PdfName.init_from_encoded(allocator, "NoSlash");
    if (result) |_| {
        try std.testing.expect(false);
    } else |err| {
        try std.testing.expect(err == PdfNameError.InvalidPdfNameFormat);
    }
}

test "PdfName equality" {
    const name1 = try PdfName.init_from_raw(allocator, "Foo Bar");
    defer name1.deinit(allocator);
    const name2 = try PdfName.init_from_encoded(allocator, "/Foo#20Bar");
    defer name2.deinit(allocator);
    const name3 = try PdfName.init_from_raw(allocator, "Foo Bar");
    defer name3.deinit(allocator); // Same as name1
    const name4 = try PdfName.init_from_raw(allocator, "OtherName");
    defer name4.deinit(allocator);

    try std.testing.expect(name1.eql(name2)); // Decoded values are equal
    try std.testing.expect(name1.eql(name3));
    try std.testing.expect(!name1.eql(name4));

    try std.testing.expect(name1.eql_str("/Foo Bar"));
    try std.testing.expect(name2.eql_str("/Foo Bar"));
    try std.testing.expect(!name1.eql_str("/Foo#20Bar")); // Compare decoded against canonical
}

test "PdfName formatting" {
    const name = try PdfName.init_from_raw(allocator, "Test Name");
    defer name.deinit(allocator);

    var buffer: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    try writer.print("{s}", .{name});
    try std.testing.expectEqualStrings("/Test Name", fbs.getWritten());
}

test "PdfName with various forbidden characters - round trip" {
    const raw_input_name: []const u8 = "()<>{}[]/%#\x00 \t\x0c\r\n\\Name";
    // Corrected expected_encoded: starts with '/' and uses uppercase hex
    const expected_encoded = "/#28#29#3C#3E#7B#7D#5B#5D#2F#25#23#00#20#09#0C#0D#0A#5CName";
    const expected_decoded = "/()<>{}[]/%#\x00 \t\x0c\r\n\\Name";

    const name_from_raw = try PdfName.init_from_raw(allocator, raw_input_name);
    defer name_from_raw.deinit(allocator);

    try std.testing.expectEqualStrings(expected_decoded, name_from_raw.value);
    try std.testing.expect(name_from_raw.encoded != null); // Ensure encoded is not null
    try std.testing.expectEqualStrings(expected_encoded, name_from_raw.encoded.?);
    try std.testing.expectEqualStrings(expected_encoded, name_from_raw.to_pdf_string());

    const name_from_encoded = try PdfName.init_from_encoded(allocator, expected_encoded);
    defer name_from_encoded.deinit(allocator);

    try std.testing.expectEqualStrings(expected_decoded, name_from_encoded.value);
    try std.testing.expect(name_from_encoded.encoded != null); // Ensure encoded is not null
    try std.testing.expectEqualStrings(expected_encoded, name_from_encoded.encoded.?);
    try std.testing.expectEqualStrings(expected_encoded, name_from_encoded.to_pdf_string());

    try std.testing.expect(name_from_raw.eql(name_from_encoded));
}
