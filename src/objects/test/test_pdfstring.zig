const std = @import("std");

const testing = std.testing;
const allocator = std.testing.allocator;
const pdfstring = @import("../pdfstring.zig");

const PdfString = pdfstring.PdfString;
const PdfStringError = pdfstring.PdfStringError;

test "initialize and deinitialize pdf doc encoding" {
    const s = try PdfString.fromUnicode(allocator, "test", .auto, .auto);
    defer s.deinit();
    pdfstring.deinitPdfDocEncoding();
}

test "fromBytes literal encoding" {
    const raw = "Hello (world) with a \\ backslash";
    const s = try PdfString.fromBytes(allocator, raw, .literal);
    defer s.deinit();

    const expected = "(Hello \\(world\\) with a \\\\ backslash)";
    try testing.expectEqualStrings(expected, s.encoded_bytes);
}

test "fromBytes hex encoding" {
    const raw: []const u8 = &.{ 0x01, 0x02, 0xFE, 0xFF };
    const s = try PdfString.fromBytes(allocator, raw, .hex);
    defer s.deinit();

    const expected = "<0102FEFF>";
    try testing.expectEqualStrings(expected, s.encoded_bytes);
}

test "fromBytes auto encoding heuristic" {
    const literal_str = try PdfString.fromBytes(allocator, "abc()def", .auto);
    defer literal_str.deinit();
    try testing.expectEqualStrings("(abc\\(\\)def)", literal_str.encoded_bytes);

    const hex_str = try PdfString.fromBytes(allocator, "()()()", .auto);
    defer hex_str.deinit();
    try testing.expectEqualStrings("<282928292829>", hex_str.encoded_bytes);
}

test "fromBytes with control characters" {
    const raw_bytes = "Hello\nWorld\r\t\x08\x0c";
    const s = try PdfString.fromBytes(allocator, raw_bytes, .literal);
    defer s.deinit();

    const expected_encoded = "(Hello\\nWorld\\r\\t\\b\\f)";
    try testing.expectEqualStrings(expected_encoded, s.encoded_bytes);
}

test "toBytes from literal string" {
    const s = try PdfString.fromBytes(allocator, "Hello\nWorld\r\t\x08\x0c", .literal);
    defer s.deinit();

    const encoded_string_literal = "(Escapes: \\n \\r \\t \\b \\f \\( \\) \\\\, Octal: \\110\\145\\154\\154\\157, Ignored NL: \\\n)";
    var complex_s = PdfString{ .encoded_bytes = encoded_string_literal, .allocator = allocator };

    const decoded_bytes = try complex_s.toBytes(allocator);
    defer allocator.free(decoded_bytes);

    const expected_bytes = "Escapes: \n \r \t \x08 \x0c ( ) \\, Octal: Hello, Ignored NL: ";
    try testing.expectEqualStrings(expected_bytes, decoded_bytes);
}

test "toBytes from hex string" {
    const encoded_hex = "<48 65 6c 6c 6f 21 F>";
    var s = PdfString{ .encoded_bytes = encoded_hex, .allocator = allocator };

    const decoded_bytes = try s.toBytes(allocator);
    defer allocator.free(decoded_bytes);

    const expected_bytes: []const u8 = "Hello!\xF0";
    try testing.expectEqualSlices(u8, expected_bytes, decoded_bytes);
}

test "fromUnicode and toUnicode with PDFDocEncoding" {
    const unicode_source = "\u{fb01} \u{fb02} \u{2013} \u{2022}";
    const s = try PdfString.fromUnicode(allocator, unicode_source, .auto, .auto);
    defer s.deinit();

    try testing.expect(s.encoded_bytes[0] == '(');

    const decoded_unicode = try s.toUnicode(allocator);
    defer allocator.free(decoded_unicode);

    const expected_unicode = "\u{fb01} \u{fb02} \u{2013} \u{2022}";
    try testing.expectEqualStrings(expected_unicode, decoded_unicode);

    try testing.expectEqualStrings(unicode_source, decoded_unicode);
    pdfstring.deinitPdfDocEncoding();
}

test "fromUnicode and toUnicode with UTF16-BE fallback" {
    const unicode_source = "Test with Я";
    const s = try PdfString.fromUnicode(allocator, unicode_source, .auto, .auto);
    defer s.deinit();

    try testing.expect(s.encoded_bytes[0] == '<');
    try testing.expect(std.mem.startsWith(u8, s.encoded_bytes, "<FEFF"));

    const decoded_unicode = try s.toUnicode(allocator);
    defer allocator.free(decoded_unicode);

    try testing.expectEqualStrings(unicode_source, decoded_unicode);

    pdfstring.deinitPdfDocEncoding();
}

test "UTF-16BE with surrogate pairs" {
    const unicode_source = "𝄞";
    const s = try PdfString.fromUnicode(allocator, unicode_source, .utf16be, .hex);
    defer s.deinit();

    const expected_encoding = "<FEFFD834DD1E>";
    try testing.expectEqualStrings(expected_encoding, s.encoded_bytes);

    const decoded_unicode = try s.toUnicode(allocator);
    defer allocator.free(decoded_unicode);

    try testing.expectEqualStrings(unicode_source, decoded_unicode);

    pdfstring.deinitPdfDocEncoding();
}

test "string error handling" {
    var invalid_hex = PdfString{ .encoded_bytes = "<48656C6C6FGG>", .allocator = allocator };
    try testing.expectError(std.fmt.ParseIntError.InvalidCharacter, invalid_hex.toBytes(allocator));

    var invalid_format = PdfString{ .encoded_bytes = "Hello", .allocator = allocator };
    try testing.expectError(PdfStringError.InvalidPdfStringFormat, invalid_format.toBytes(allocator));

    const unsupported_char = "Я";
    try testing.expectError(PdfStringError.EncodingError, PdfString.fromUnicode(allocator, unsupported_char, .pdfdocencoding, .auto));
    pdfstring.deinitPdfDocEncoding();
}
