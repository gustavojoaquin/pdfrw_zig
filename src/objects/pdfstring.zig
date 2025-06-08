//! This module provides a faithful Zig implementation of Python's `pdfrw.pdfstring` module.
//! It handles the encoding and decoding of PDF String objects as defined in the PDF 1.7 specification.
//!
//! A PDF string can be in one of two formats:
//! 1.  **Literal String:** Enclosed in parentheses `()`, with special characters escaped by a backslash.
//! 2.  **Hexadecimal String:** Enclosed in angle brackets `<>`, representing bytes as hex digits.
//!
//! Text within a PDF string can have two primary encodings:
//! 1.  **PDFDocEncoding:** A custom 8-bit encoding similar to Latin-1, with some Adobe-specific characters.
//! 2.  **UTF-16BE:** Standard UTF-16 Big Endian, identified by a Byte Order Mark (BOM).
//!
//! The main type is `PdfString`, which stores the string in its final, encoded format (e.g., `"(Hello)"`).
//! Use factory functions `fromBytes` or `fromUnicode` to create an encoded `PdfString`.
//! Use instance methods `toBytes` or `toUnicode` to decode a `PdfString` back to raw bytes or a UTF-8 string.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Errors that can occur during PDF string parsing, encoding, or decoding.
pub const PdfStringError = error{
    /// The input string is not a valid literal `()` or hex `<>` string.
    InvalidPdfStringFormat,
    /// An invalid non-hexadecimal character was found in a hex string.
    InvalidHexCharacter,
    /// An invalid or incomplete octal escape sequence (e.g., `\9` or `\`) was found.
    InvalidOctalEscape,
    /// A character could not be encoded or decoded with the specified text encoding.
    EncodingError,
};

const BOM_UTF16_BE = [_]u8{ 0xFE, 0xFF };

// --- Global State for PDFDocEncoding ---
// These are lazily initialized on first use to avoid startup cost.

var pdf_doc_encoding_to_unicode_map: [256]u21 = undefined;
var unicode_to_pdf_doc_encoding_map: std.AutoHashMap(u21, u8) = undefined;
var pdf_doc_encoding_initialized: bool = false;

/// Initializes the global mapping tables for PDFDocEncoding.
/// This function is called automatically when needed.
fn initPdfDocEncoding(allocator: Allocator) !void {
    if (pdf_doc_encoding_initialized) return;

    // Default to 1:1 mapping for the first 256 characters.
    for (0..256) |i| {
        pdf_doc_encoding_to_unicode_map[i] = @intCast(i);
    }

    // Override with mappings from PDF 1.7 Spec, Appendix D.2.
    pdf_doc_encoding_to_unicode_map[0x18] = 0x02D8; // BREVE
    pdf_doc_encoding_to_unicode_map[0x19] = 0x02C7; // CARON
    pdf_doc_encoding_to_unicode_map[0x1A] = 0x02C6; // MODIFIER LETTER CIRCUMFLEX ACCENT
    pdf_doc_encoding_to_unicode_map[0x1B] = 0x02D9; // DOT ABOVE
    pdf_doc_encoding_to_unicode_map[0x1C] = 0x02DD; // DOUBLE ACUTE ACCENT
    pdf_doc_encoding_to_unicode_map[0x1D] = 0x02DB; // OGONEK
    pdf_doc_encoding_to_unicode_map[0x1E] = 0x02DA; // RING ABOVE
    pdf_doc_encoding_to_unicode_map[0x1F] = 0x02DC; // SMALL TILDE
    pdf_doc_encoding_to_unicode_map[0x80] = 0x2022; // BULLET
    pdf_doc_encoding_to_unicode_map[0x81] = 0x2020; // DAGGER
    pdf_doc_encoding_to_unicode_map[0x82] = 0x2021; // DOUBLE DAGGER
    pdf_doc_encoding_to_unicode_map[0x83] = 0x2026; // HORIZONTAL ELLIPSIS
    pdf_doc_encoding_to_unicode_map[0x84] = 0x2014; // EM DASH
    pdf_doc_encoding_to_unicode_map[0x85] = 0x2013; // EN DASH
    pdf_doc_encoding_to_unicode_map[0x86] = 0x0192; // LATIN SMALL LETTER F WITH HOOK
    pdf_doc_encoding_to_unicode_map[0x87] = 0x2044; // FRACTION SLASH
    pdf_doc_encoding_to_unicode_map[0x88] = 0x2039; // SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    pdf_doc_encoding_to_unicode_map[0x89] = 0x203A; // SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    pdf_doc_encoding_to_unicode_map[0x8A] = 0x2212; // MINUS SIGN
    pdf_doc_encoding_to_unicode_map[0x8B] = 0x2030; // PER MILLE SIGN
    pdf_doc_encoding_to_unicode_map[0x8C] = 0x201E; // DOUBLE LOW-9 QUOTATION MARK
    pdf_doc_encoding_to_unicode_map[0x8D] = 0x201C; // LEFT DOUBLE QUOTATION MARK
    pdf_doc_encoding_to_unicode_map[0x8E] = 0x201D; // RIGHT DOUBLE QUOTATION MARK
    pdf_doc_encoding_to_unicode_map[0x8F] = 0x2018; // LEFT SINGLE QUOTATION MARK
    pdf_doc_encoding_to_unicode_map[0x90] = 0x2019; // RIGHT SINGLE QUOTATION MARK
    pdf_doc_encoding_to_unicode_map[0x91] = 0x201A; // SINGLE LOW-9 QUOTATION MARK
    pdf_doc_encoding_to_unicode_map[0x92] = 0x2122; // TRADE MARK SIGN
    pdf_doc_encoding_to_unicode_map[0x93] = 0xFB01; // LATIN SMALL LIGATURE FI
    pdf_doc_encoding_to_unicode_map[0x94] = 0xFB02; // LATIN SMALL LIGATURE FL
    pdf_doc_encoding_to_unicode_map[0x95] = 0x0141; // LATIN CAPITAL LETTER L WITH STROKE
    pdf_doc_encoding_to_unicode_map[0x96] = 0x0152; // LATIN CAPITAL LIGATURE OE
    pdf_doc_encoding_to_unicode_map[0x97] = 0x0160; // LATIN CAPITAL LETTER S WITH CARON
    pdf_doc_encoding_to_unicode_map[0x98] = 0x0178; // LATIN CAPITAL LETTER Y WITH DIAERESIS
    pdf_doc_encoding_to_unicode_map[0x99] = 0x017D; // LATIN CAPITAL LETTER Z WITH CARON
    pdf_doc_encoding_to_unicode_map[0x9A] = 0x0131; // LATIN SMALL LETTER DOTLESS I
    pdf_doc_encoding_to_unicode_map[0x9B] = 0x0142; // LATIN SMALL LETTER L WITH STROKE
    pdf_doc_encoding_to_unicode_map[0x9C] = 0x0153; // LATIN SMALL LIGATURE OE
    pdf_doc_encoding_to_unicode_map[0x9D] = 0x0161; // LATIN SMALL LETTER S WITH CARON
    pdf_doc_encoding_to_unicode_map[0x9E] = 0x017E; // LATIN SMALL LETTER Z WITH CARON
    pdf_doc_encoding_to_unicode_map[0xA0] = 0x20AC; // EURO SIGN
    pdf_doc_encoding_to_unicode_map[0xAD] = 0xFFFD; // SOFT HYPHEN is unassigned, map to REPLACEMENT CHARACTER.

    // Initialize the reverse map (Unicode -> PDFDocEncoding byte).
    unicode_to_pdf_doc_encoding_map = std.AutoHashMap(u21, u8).init(allocator);
    errdefer unicode_to_pdf_doc_encoding_map.deinit();

    for (pdf_doc_encoding_to_unicode_map, 0..) |unicode_char, byte_val_u64| {
        // Prefer the first (and lowest) byte value if multiple map to the same Unicode codepoint.
        if (unicode_char != 0xFFFD and !unicode_to_pdf_doc_encoding_map.contains(unicode_char)) {
            try unicode_to_pdf_doc_encoding_map.put(unicode_char, @intCast(byte_val_u64));
        }
    }
    pdf_doc_encoding_initialized = true;
}

/// Frees the global resources used for PDFDocEncoding.
/// Call this on application shutdown if encoding/decoding was used to prevent memory leaks.
pub fn deinitPdfDocEncoding() void {
    if (pdf_doc_encoding_initialized) {
        unicode_to_pdf_doc_encoding_map.deinit();
        pdf_doc_encoding_initialized = false;
    }
}

/// Represents a PDF String object, holding the raw, encoded bytes as they would appear in a PDF file.
pub const PdfString = struct {
    /// The owned slice containing the encoded string, e.g., `(Hello World)` or `<48656C6C6F>`.
    encoded_bytes: []const u8,
    allocator: Allocator,

    /// Creates a `PdfString` by encoding a slice of raw bytes.
    /// - `allocator`: Allocator for the new `PdfString`'s memory.
    /// - `raw_bytes`: The unencoded byte sequence to be wrapped in a PDF string.
    /// - `bytes_encoding_hint`: Determines whether to use literal `()` or hex `<>` encoding.
    ///   `.auto` will choose hex if more than half the characters would require escaping in a literal string.
    pub fn fromBytes(allocator: Allocator, raw_bytes: []const u8, bytes_encoding_hint: enum { auto, literal, hex }) !PdfString {
        var encoded_buffer = std.ArrayList(u8).init(allocator);
        errdefer encoded_buffer.deinit();

        const use_hex = switch (bytes_encoding_hint) {
            .hex => true,
            .literal => false,
            .auto => blk: {
                // Heuristic from pdfrw: use hex if escaping makes the literal string significantly longer.
                // The threshold is when at least half the characters need escaping (`\`, `(`, or `)`).
                var escape_count: usize = 0;
                for (raw_bytes) |b| {
                    if (b == '(' or b == ')' or b == '\\') escape_count += 1;
                }
                break :blk escape_count * 2 >= raw_bytes.len;
            },
        };

        if (use_hex) {
            try encoded_buffer.append('<');
            try std.fmt.format(encoded_buffer.writer(), "{X}", .{raw_bytes});
            try encoded_buffer.append('>');
        } else {
            try encoded_buffer.append('(');
            for (raw_bytes) |b| {
                switch (b) {
                    '\\', '(', ')' => {
                        try encoded_buffer.append('\\');
                        try encoded_buffer.append(b);
                    },
                    else => try encoded_buffer.append(b),
                }
            }
            try encoded_buffer.append(')');
        }

        return PdfString{ .encoded_bytes = try encoded_buffer.toOwnedSlice(), .allocator = allocator };
    }

    /// Creates a `PdfString` by encoding a UTF-8 string.
    /// - `text_encoding_hint`: Determines whether to use `PDFDocEncoding` or `UTF-16BE`.
    ///   `.auto` will try `PDFDocEncoding` first and fall back to `UTF-16BE` if any character is unsupported.
    /// - `bytes_encoding_hint`: See `fromBytes`. When `UTF-16BE` is chosen, this defaults to `hex`.
    pub fn fromUnicode(allocator: Allocator, unicode_source: []const u8, text_encoding_hint: enum { auto, pdfdocencoding, utf16be }, bytes_encoding_hint: enum { auto, literal, hex }) !PdfString {
        try initPdfDocEncoding(allocator);

        var raw_bytes_to_encode = std.ArrayList(u8).init(allocator);
        defer raw_bytes_to_encode.deinit();

        var use_utf16be = false;
        if (text_encoding_hint == .utf16be) {
            use_utf16be = true;
        } else {
            // Attempt to encode with PDFDocEncoding.
            var can_use_pdfdoc = true;
            var iter = std.unicode.Utf8Iterator{ .bytes = unicode_source };
            while (try iter.nextCodepoint()) |codepoint| {
                if (unicode_to_pdf_doc_encoding_map.get(codepoint)) |byte_val| {
                    try raw_bytes_to_encode.append(byte_val);
                } else {
                    can_use_pdfdoc = false;
                    break;
                }
            }
            if (!can_use_pdfdoc) {
                if (text_encoding_hint == .pdfdocencoding) return error.EncodingError;
                use_utf16be = true;
            }
        }

        if (use_utf16be) {
            raw_bytes_to_encode.clearRetainingCapacity();
            try raw_bytes_to_encode.appendSlice(BOM_UTF16_BE);

            var iter = std.unicode.Utf8Iterator{ .bytes = unicode_source };
            while (try iter.nextCodepoint()) |codepoint| {
                const utf16_be_bytes = std.unicode.utf16EncodeBe(codepoint) catch return error.EncodingError;
                try raw_bytes_to_encode.appendSlice(&utf16_be_bytes);
            }
        }

        const final_bytes_encoding = if (use_utf16be and bytes_encoding_hint == .auto) .hex else bytes_encoding_hint;
        return PdfString.fromBytes(allocator, raw_bytes_to_encode.items, final_bytes_encoding);
    }

    /// Frees the memory owned by the `PdfString`.
    pub fn deinit(self: *const PdfString) void {
        self.allocator.free(self.encoded_bytes);
    }

    /// Decodes the PDF string into its raw byte sequence.
    /// The caller is responsible for freeing the returned slice.
    pub fn toBytes(self: PdfString, allocator: Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);

        if (self.encoded_bytes.len > 0) {
            switch (self.encoded_bytes[0]) {
                '(' => try self.decodeLiteral(buffer.writer()),
                '<' => try self.decodeHex(buffer.writer()),
                else => return error.InvalidPdfStringFormat,
            }
        }
        return buffer.toOwnedSlice();
    }

    /// Decodes the PDF string into a UTF-8 encoded string.
    /// It first decodes to raw bytes, then interprets them as UTF-16BE (if a BOM is present)
    /// or PDFDocEncoding otherwise. The caller must free the returned slice.
    pub fn toUnicode(self: PdfString, allocator: Allocator) ![]const u8 {
        try initPdfDocEncoding(allocator);

        const raw_bytes = try self.toBytes(allocator);
        defer allocator.free(raw_bytes);

        var unicode_buffer = std.ArrayList(u8).init(allocator);
        errdefer unicode_buffer.deinit();

        if (std.mem.startsWith(u8, raw_bytes, BOM_UTF16_BE)) {
            // Decode as UTF-16BE
            const utf16_payload = raw_bytes[BOM_UTF16_BE.len..];
            if (utf16_payload.len % 2 != 0) return error.InvalidPdfStringFormat;
            try std.unicode.utf16LeToUtf8(unicode_buffer.writer(), std.unicode.utf16DecodeBe(utf16_payload));
        } else {
            // Decode as PDFDocEncoding
            for (raw_bytes) |byte_val| {
                const codepoint = pdf_doc_encoding_to_unicode_map[byte_val];
                var temp_buf: [4]u8 = undefined;
                const utf8_len = try std.unicode.utf8Encode(codepoint, &temp_buf);
                try unicode_buffer.appendSlice(temp_buf[0..utf8_len]);
            }
        }
        return unicode_buffer.toOwnedSlice();
    }

    /// Creates a deep copy of the `PdfString` using the provided allocator.
    pub fn clone(self: PdfString, new_allocator: Allocator) !PdfString {
        return PdfString{
            .encoded_bytes = try new_allocator.dupe(u8, self.encoded_bytes),
            .allocator = new_allocator,
        };
    }

    // --- Private Helper Methods ---

    fn decodeLiteral(self: PdfString, writer: anytype) !void {
        if (self.encoded_bytes.len < 2 or self.encoded_bytes[0] != '(' or self.encoded_bytes[self.encoded_bytes.len - 1] != ')') {
            return error.InvalidPdfStringFormat;
        }
        const content = self.encoded_bytes[1 .. self.encoded_bytes.len - 1];
        var i: usize = 0;
        while (i < content.len) : (i += 1) {
            if (content[i] == '\\') {
                i += 1;
                if (i >= content.len) return error.InvalidPdfStringFormat;
                switch (content[i]) {
                    'n' => try writer.writeByte('\n'),
                    'r' => try writer.writeByte('\r'),
                    't' => try writer.writeByte('\t'),
                    'b' => try writer.writeByte(0x08),
                    'f' => try writer.writeByte(0x0C),
                    '(', ')', '\\' => try writer.writeByte(content[i]),
                    '\n' => {}, // Ignore escaped newline
                    '\r' => { // Ignore escaped CRLF or CR
                        if (i + 1 < content.len and content[i + 1] == '\n') i += 1;
                    },
                    '0'...'7' => { // Octal escape
                        var octal_len: usize = 0;
                        while (i + octal_len < content.len and octal_len < 3) : (octal_len += 1) {
                            const char = content[i + octal_len];
                            if (char < '0' or char > '7') {
                                break;
                            }
                        }

                        if (octal_len == 0)
                            return PdfStringError.InvalidOctalEscape;

                        const octal_ptr = content[i .. i + octal_len];
                        const byte_val = std.fmt.parseUnsigned(u8, octal_ptr, 8) catch return error.InvalidOctalEscape;
                        try writer.writeByte(byte_val);
                        i += octal_len - 1;
                    },
                    else => try writer.writeByte(content[i]), // Per spec, unknown escapes are just the character itself
                }
            } else {
                try writer.writeByte(content[i]);
            }
        }
    }

    fn decodeHex(self: PdfString, writer: anytype) !void {
        if (self.encoded_bytes.len < 2 or self.encoded_bytes[0] != '<' or self.encoded_bytes[self.encoded_bytes.len - 1] != '>') {
            return error.InvalidPdfStringFormat;
        }
        var hex_content = std.ArrayList(u8).init(self.allocator);
        defer hex_content.deinit();

        for (self.encoded_bytes[1 .. self.encoded_bytes.len - 1]) |char| {
            if (!std.ascii.isWhitespace(char)) {
                try hex_content.append(char);
            }
        }
        // Per spec, a final odd hex digit is treated as if it were followed by a '0'.
        if (hex_content.items.len % 2 != 0) {
            try hex_content.append('0');
        }
        try std.fmt.hexToBytes(writer, hex_content.items);
    }
};
