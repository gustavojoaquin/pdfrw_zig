const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PdfStringError = error{
    InvalidPdfStringFormat,
    InvalidHexCharacter,
    InvalidOctalEscape,
    EncodingError,
    AllocationFailed,
    OutputTooSmall,
};

const BOM_UTF16_BE = [_]u8{ 0xFE, 0xFF };

var pdf_doc_encoding_to_unicode_map: [256]u21 = undefined;
var unicode_to_pdf_doc_encoding_map: std.HashMap(u21, u8, std.hash.IntegerContext(u21), std.hash_map.default_max_load_percentage) = undefined;
var pdf_doc_encoding_initialized: bool = false;

fn initPdfDocEncoding(allocator: Allocator) !void {
    if (pdf_doc_encoding_initialized) return;

    for (0..256) |i| {
        pdf_doc_encoding_to_unicode_map[i] = @intCast(i);
    }

    // Overrides from PDF 1.7 Spec, Appendix D.2
    // Standard Latin Character Set and Encodings
    // Differences from WinAnsiEncoding (which is close to ISO Latin-1)
    // Entries not in WinAnsiEncoding:
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
    pdf_doc_encoding_to_unicode_map[0x87] = 0x2044; // FRACTION SLASH (Solidus)
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
    // 0x9F is reserved in PDFDocEncoding according to table, maps to 0x009F in WinAnsi.
    // Python code keeps 0x9F as 0x009F (CONTROL). Let's make it undefined for strictness.
    // Or, follow Python's "Postel's Law" for decoding and map 0x9F to 0x009F for decoding,
    // but not for encoding. For simplicity, map to itself for now.
    // pdf_doc_encoding_to_unicode_map[0x9F] = 0x009F;

    // A0-FF except AD
    // 0xA0 space (normally NBSP 00A0, but is Euro 20AC in PDFDoc)
    pdf_doc_encoding_to_unicode_map[0xA0] = 0x20AC; // EURO SIGN

    // 0xAD (SOFT HYPHEN) is unassigned in PDFDocEncoding.
    // In ISO-8859-1 and WinAnsi, it's U+00AD.
    // For strictness, it should map to a replacement char or error.
    // Python's codecs.charmap_decode maps unassigned to U+FFFD (REPLACEMENT CHARACTER) if errors='replace'
    // or errors out if errors='strict'. For simplicity, map to replacement or just keep 0xAD (byte value)
    // as it's unlikely to be correctly used. Let's map to replacement for decode.
    pdf_doc_encoding_to_unicode_map[0xAD] = 0xFFFD; // REPLACEMENT CHARACTER

    // Initialize encoding_map (unicode_to_pdf_doc_encoding_map)
    // This requires an allocator for the HashMap.
    unicode_to_pdf_doc_encoding_map = std.HashMap(u21, u8, std.hash.IntegerContext(u21), std.hash_map.default_max_load_percentage).init(allocator);
    // Populate the reverse map
    for (pdf_doc_encoding_to_unicode_map, 0..) |unicode_char, byte_val_u64| {
        const byte_val: u8 = @intCast(byte_val_u64);
        // Handle collisions: PDFDocEncoding is not a perfect 1:1 back.
        // We want the "standard" or lowest byte value if multiple map to same Unicode.
        // For PDFDocEncoding, it's mostly unique for what it *does* define.
        // The issue is more about Unicode chars not in PDFDocEncoding.
        if (unicode_char != 0xFFFD) { // Don't map replacement char back if possible
            if (!unicode_to_pdf_doc_encoding_map.contains(unicode_char)) { // Prefer first encountered
                try unicode_to_pdf_doc_encoding_map.put(unicode_char, byte_val);
            } else {
                // Example: If 0x00 (byte) -> U+0000 (Unicode), and later some other_byte -> U+0000
                // We'd prefer the first mapping.
                // For PDFDoc this shouldn't be a major issue for the defined range.
            }
        }
    }
    // Add common ASCII control chars that PDF spec allows in strings (though often escaped)
    // but are not explicitly in PDFDocEncoding table for special Unicode mapping.
    // \n, \r, \t, \b, \f
    // These will be handled by literal string escaping if needed.
    // Their direct byte values are < 0x20.
    // Python's PDFDocEncoding maps 0x09, 0x0A, 0x0D to themselves.
    // The loop above already did this.

    pdf_doc_encoding_initialized = true;
}

pub fn deinitPdfDocEncoding() void {
    if (pdf_doc_encoding_initialized) {
        unicode_to_pdf_doc_encoding_map.deinit();
        pdf_doc_encoding_initialized = false;
    }
}

pub const PdfString = struct {
    /// The raw, encoded string as it would appear in a PDF file (e.g., "(Hello)", "<48656C6C6F>").
    /// This slice is owned by the PdfString instance.
    encoded_bytes: []const u8,
    allocator: Allocator,

    // indirect: bool = false, // This might belong to PdfObject or a wrapper

    // Factory methods for encoding
    pub fn fromBytes(allocator: Allocator, raw_bytes: []const u8, bytes_encoding_hint: enum { auto, literal, hex }) !PdfString {
        var encoded_buffer = std.ArrayList(u8).init(allocator);
        defer encoded_buffer.deinit();

        const use_hex = switch (bytes_encoding_hint) {
            .hex => true,
            .literal => false,
            .auto => blk: {
                // Heuristic: if literal encoding is much longer, use hex.
                // Python's heuristic: len(splitlist) // 2 >= len(raw)
                // splitlist is from splitting on '(', ')', '\'. Each escape adds 1 byte.
                // A simple heuristic: count chars that need escaping. If > 50% of len, or if very few non-ASCII.
                // For now, a simpler one: if raw_bytes contains many non-printable or chars needing escape.
                // Or just use hex if significantly shorter or roughly same as literal after escapes.
                // Raw hex is 2*N + 2. Literal is N + 2 + num_escapes.
                // Use hex if 2*N < N + num_escapes => N < num_escapes.
                // This means if more than N characters need escaping, hex is better. This is too aggressive.
                // Python: `len(splitlist) // 2 >= len(raw)`. `len(splitlist)` is roughly `raw.len + 2 * num_parentheses_or_backslashes`.
                // So, `(raw.len + 2*num_escapes_for_lit) / 2 >= raw.len`
                // `raw.len/2 + num_escapes_for_lit >= raw.len`
                // `num_escapes_for_lit >= raw.len / 2`. If half the chars need escaping, use hex.
                var escape_count: usize = 0;
                for (raw_bytes) |b| {
                    if (b == '(' or b == ')' or b == '\\') {
                        escape_count += 1;
                    }
                }
                break :blk escape_count * 2 >= raw_bytes.len; // If escapes make it double, use hex
            },
        };

        if (use_hex) {
            try encoded_buffer.append('<');
            try std.fmt.bytesToHex(encoded_buffer.writer(), raw_bytes, .upper);
            try encoded_buffer.append('>');
        } else {
            try encoded_buffer.append('(');
            for (raw_bytes) |b| {
                switch (b) {
                    '\\', '(', ')' => {
                        try encoded_buffer.append('\\');
                        try encoded_buffer.append(b);
                    },
                    // Note: Python code does not escape \n, \r, \t etc. here,
                    // it escapes them during *literal string decoding's re-encoding logic*.
                    // For from_bytes, it seems to only escape structural chars.
                    else => try encoded_buffer.append(b),
                }
            }
            try encoded_buffer.append(')');
        }

        return PdfString{
            .encoded_bytes = try encoded_buffer.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    pub fn fromUnicode(allocator: Allocator, unicode_source: []const u8, text_encoding_hint: enum { auto, pdfdocencoding, utf16be }, bytes_encoding_hint: enum { auto, literal, hex }) !PdfString {
        if (!pdf_doc_encoding_initialized) {
            try initPdfDocEncoding(allocator); // Use the passed allocator
        }

        var raw_bytes_to_encode = std.ArrayList(u8).init(allocator);
        defer raw_bytes_to_encode.deinit();

        var chose_utf16be = false;

        switch (text_encoding_hint) {
            .auto, .pdfdocencoding => {
                if (unicode_source.len >= 2 and unicode_source[0] == 0xFE and unicode_source[1] == 0xFF) {
                    if (text_encoding_hint == .pdfdocencoding) return PdfStringError.EncodingError;
                    chose_utf16be = true;
                } else {
                    var can_use_pdfdoc = true;
                    var iter = std.unicode.Utf8Iterator{ .bytes = unicode_source };
                    while (iter.nextCodepoint()) |codepoint| {
                        if (unicode_to_pdf_doc_encoding_map.get(codepoint)) |byte_val| {
                            try raw_bytes_to_encode.append(byte_val);
                        } else {
                            can_use_pdfdoc = false;
                            break;
                        }
                    } else |_| {
                        return PdfStringError.InvalidPdfStringFormat;
                    }

                    if (!can_use_pdfdoc) {
                        if (text_encoding_hint == .pdfdocencoding) return PdfStringError.EncodingError;
                        chose_utf16be = true;
                        raw_bytes_to_encode.clearRetainingCapacity();
                    }
                }
            },
            .utf16be => chose_utf16be = true,
        }

        if (chose_utf16be) {
            try raw_bytes_to_encode.appendSlice(BOM_UTF16_BE);
            var iter = std.unicode.Utf8Iterator{ .bytes = unicode_source };
            while (iter.nextCodepoint()) |codepoint| {
                if (codepoint > 0xFFFF) {
                    const high_surrogate = 0xD800 + ((codepoint - 0x10000) >> 10);
                    const low_surrogate = 0xDC00 + ((codepoint - 0x10000) & 0x3FF);
                    try raw_bytes_to_encode.append(@intCast((high_surrogate >> 8) & 0xFF));
                    try raw_bytes_to_encode.append(@intCast(high_surrogate & 0xFF));
                    try raw_bytes_to_encode.append(@intCast((low_surrogate >> 8) & 0xFF));
                    try raw_bytes_to_encode.append(@intCast(low_surrogate & 0xFF));
                } else {
                    try raw_bytes_to_encode.append(@intCast((codepoint >> 8) & 0xFF));
                    try raw_bytes_to_encode.append(@intCast(codepoint & 0xFF));
                }
            } else |_| {
                return PdfStringError.InvalidPdfStringFormat;
            }
        }

        const final_bytes_encoding = if (chose_utf16be and bytes_encoding_hint == .auto) .hex else bytes_encoding_hint;

        return PdfString.fromBytes(allocator, raw_bytes_to_encode.items, final_bytes_encoding);
    }

    pub fn deinit(self: *const PdfString) void {
        self.allocator.free(self.encoded_bytes);
    }

    fn decodeLiteral(self: PdfString, writer: anytype) !void {
        if (self.encoded_bytes.len < 2 or self.encoded_bytes[0] != '(' or self.encoded_bytes[self.encoded_bytes.len - 1] != ')') {
            return PdfStringError.InvalidPdfStringFormat;
        }
        const content = self.encoded_bytes[1 .. self.encoded_bytes.len - 1];
        var i: usize = 0;
        while (i < content.len) {
            if (content[i] == '\\') {
                i += 1;
                if (i >= content.len) return PdfStringError.InvalidPdfStringFormat;
                switch (content[i]) {
                    'n' => try writer.writeByte('\n'),
                    'r' => try writer.writeByte('\r'),
                    't' => try writer.writeByte('\t'),
                    'b' => try writer.writeByte('\x08'),
                    'f' => try writer.writeByte('\x0c'),
                    '(' => try writer.writeByte('('),
                    ')' => try writer.writeByte(')'),
                    '\\' => try writer.writeByte('\\'),
                    '\n' => {},
                    '\r' => {
                        if (i + 1 < content.len and content[i + 1] == '\n') {
                            i += 1;
                        }
                    },
                    '0'...'7' => {
                        var octal_len: usize = 0;
                        while (i + octal_len < content.len and octal_len < 3 and content[i + octal_len] >= '0' and content[i + octal_len] <= '7') {
                            octal_len += 1;
                        }
                        if (octal_len == 0) return PdfStringError.InvalidOctalEscape;
                        const octal_str = content[i .. i + octal_len];
                        const byte_val = std.fmt.parseUnsigned(u8, octal_str, 8) catch return PdfStringError.InvalidOctalEscape;
                        try writer.writeByte(byte_val);
                        i += octal_len - 1;
                    },
                    else => try writer.writeByte(content[i]),
                }
            } else {
                try writer.writeByte(content[i]);
            }
            i += 1;
        }
    }

    fn decodeHex(self: PdfString, writer: anytype) !void {
        if (self.encoded_bytes.len < 2 or self.encoded_bytes[0] != '<' or self.encoded_bytes[self.encoded_bytes.len - 1] != '>') {
            return PdfStringError.InvalidPdfStringFormat;
        }
        var content_cleaned = std.ArrayList(u8).init(self.allocator);
        defer content_cleaned.deinit();

        for (self.encoded_bytes[1 .. self.encoded_bytes.len - 1]) |char| {
            if (!std.ascii.isWhitespace(char)) {
                try content_cleaned.append(char);
            }
        }

        const hex_content = content_cleaned.items;
        if (hex_content.len % 2 != 0) {
            try content_cleaned.append('0');
        }
        try std.fmt.hexToBytes(writer, content_cleaned.items);
    }

    pub fn toBytes(self: PdfString, allocator: Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);

        if (self.encoded_bytes.len > 0) {
            if (self.encoded_bytes[0] == '(') {
                try self.decodeLiteral(buffer.writer());
            } else if (self.encoded_bytes[0] == '<') {
                try self.decodeHex(buffer.writer());
            } else {
                return PdfStringError.InvalidPdfStringFormat;
            }
        }
        return buffer.toOwnedSlice();
    }

    pub fn toUnicode(self: PdfString, allocator: Allocator) ![]const u8 {
        if (!pdf_doc_encoding_initialized) {
            const gpa = std.heap.page_allocator;
            try initPdfDocEncoding(gpa);
        }

        const raw_bytes = try self.toBytes(allocator);
        defer allocator.free(raw_bytes);

        var unicode_buffer = std.ArrayList(u8).init(allocator);

        if (raw_bytes.len >= 2 and std.mem.eql(u8, raw_bytes[0..2], BOM_UTF16_BE)) {
            const utf16_payload = raw_bytes[2..];
            if (utf16_payload.len % 2 != 0) return PdfStringError.InvalidPdfStringFormat;

            var i: usize = 0;
            while (i < utf16_payload.len) : (i += 2) {
                const c1 = utf16_payload[i];
                const c2 = utf16_payload[i + 1];
                var codepoint: u21 = (@as(u21, c1) << 8) | @as(u21, c2);

                // Handle surrogate pairs
                if (codepoint >= 0xD800 and codepoint <= 0xDBFF) {
                    if (i + 3 >= utf16_payload.len) return PdfStringError.InvalidPdfStringFormat;
                    const c3 = utf16_payload[i + 2];
                    const c4 = utf16_payload[i + 3];
                    const low_surrogate: u21 = (@as(u21, c3) << 8) | @as(u21, c4);
                    if (low_surrogate < 0xDC00 or low_surrogate > 0xDFFF) return PdfStringError.InvalidPdfStringFormat; // Invalid low surrogate

                    codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low_surrogate - 0xDC00);
                    i += 2; // Consumed an extra pair
                } else if (codepoint >= 0xDC00 and codepoint <= 0xDFFF) { // Low surrogate without high
                    return PdfStringError.InvalidPdfStringFormat;
                }

                var temp_buf: [4]u8 = undefined;
                const utf8_len = std.unicode.utf8Encode(codepoint, &temp_buf) catch return PdfStringError.EncodingError;
                try unicode_buffer.appendSlice(temp_buf[0..utf8_len]);
            }
        } else {
            for (raw_bytes) |byte_val| {
                const codepoint = pdf_doc_encoding_to_unicode_map[byte_val];
                if (codepoint == 0xFFFD and byte_val != 0xAD) {}
                var temp_buf: [4]u8 = undefined;
                const utf8_len = std.unicode.utf8Encode(codepoint, &temp_buf) catch return PdfStringError.EncodingError;
                try unicode_buffer.appendSlice(temp_buf[0..utf8_len]);
            }
        }
        return unicode_buffer.toOwnedSlice();
    }

    pub fn clone(self: PdfString, new_allocator: Allocator) !PdfString {
        const new_encoded_bytes = try new_allocator.dupe(u8, self.encoded_bytes);
        return PdfString{
            .encoded_bytes = new_encoded_bytes,
            .allocator = new_allocator,
        };
    }
};
