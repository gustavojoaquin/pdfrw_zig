const std = @import("std");
const Allocator = std.mem.Allocator;

pub const pdfNameError = error{
    InvalidPdfNameFormat,
    AllocationFailed,
};

/// Represents a PDF name object, like `/Type` or `/Creator`.
/// Handles encoding/decoding of characters that are not allowed directly
/// in PDF names (e.g., spaces, delimiters, `#`).
pub const PdfName = struct {
    /// The decoded, canonical form of the PDF name (e.g., "/Foo Bar").
    /// This is used for comparison and internal logic.
    value: []const u8,
    /// The encoded form of the PDF name (e.g., "/Foo#20Bar"), if different from `value`.
    /// This is what should be written to the PDF file.
    encoded: ?[]const u8,
    /// PdfNames are always direct objects, not indirect references.
    indirect: bool = false,

    const whitespace_chars = "\x00\x09\x0A\x0C\x0D\x20";
    const delimiter_chars = "()<>{}[]/%";
    const forbidden_chars = whitespace_chars ++ delimiter_chars ++ "\\#";

    const forbidden_lookup_table: [256]bool = blk: {
        var table: [256]bool = .{false} ** 256;
        for (forbidden_chars) |c| table[c] = true;
        break :blk table;
    };

    fn needs_escape(c: u8) bool {
        return forbidden_lookup_table[c];
    }

    fn is_simple_unscaped_value_name(name_str: []const u8) bool {
        if (name_str.len == 0 or name_str[0] == '/') return false;

        for (name_str[1..]) |c| {
            if (needs_escape(c)) return false;
        }

        return true;
    }

    /// Encodes only the name portion (without slash)
    pub fn encode_name(allocator: Allocator, name_str: []const u8) ![]const u8 {
        var buff = std.ArrayList(u8).init(allocator);
        errdefer buff.deinit();

        for (name_str) |c| {
            if (needs_escape(c)) {
                try buff.writer().print("#{X:0>2}", .{c});
            } else {
                try buff.append(c);
            }
        }

        return buff.toOwnedSlice();
    }

    /// Decodes only the name portion (without slash)
    pub fn decode_name(allocator: Allocator, name_part_encoded: []const u8) ![]const u8 {
        var buff = std.ArrayList(u8).init(allocator);
        errdefer buff.deinit();

        var i: usize = 0;
        while (i < name_part_encoded.len) {
            if (name_part_encoded[i] == '#') {
                if (i + 2 < name_part_encoded.len) {
                    const hex_pair = name_part_encoded[i + 1 .. i + 3];
                    if (std.ascii.isHex(hex_pair[0]) and std.ascii.isHex(hex_pair[1])) {
                        const char_code = try std.fmt.parseUnsigned(u8, hex_pair, 16);
                        try buff.append(char_code);
                        i += 3;
                    } else {
                        try buff.append('#');
                        i += 1;
                    }
                } else {
                    try buff.append('#');
                    i += 1;
                }
            } else {
                try buff.append(name_part_encoded[i]);
                i += 1;
            }
        }
        return buff.toOwnedSlice();
    }

    /// Creates a new PdfName instance from a raw name string (e.g., "Type" for "/Type").
    /// This function will prepend '/' and encode the name if necessary.
    ///
    /// `name_without_slash`: The raw string (e.g., "Type", "Foo Bar").
    ///                      This method will prepend the `/` for you.
    /// `allocator`: An allocator for any internal memory allocations.
    ///
    /// This factory method mimics `PdfName('FooBar')` or `PdfName.FooBar` in Python.
    pub fn init_from_raw(allocator: Allocator, name_without_slash: []const u8) !PdfName {
        const potential_encode = try encode_name(allocator, name_without_slash);
        defer allocator.free(potential_encode);

        const needs_encoding = !std.mem.eql(u8, potential_encode, name_without_slash);

        const value = try std.fmt.allocPrint(allocator, "/{s}", .{name_without_slash});

        var full_encoded: ?[]const u8 = null;
        if (needs_encoding) {
            full_encoded = try std.fmt.allocPrint(allocator, "/{s}", .{potential_encode});
        }

        return PdfName{
            .value = value,
            .encoded = full_encoded,
        };
    }

    /// Creates a new PdfName instance from a string read directly from a PDF file.
    /// This string might already contain #XX escapes.
    ///
    /// `full_pdf_name_string`: The string read from the PDF file (e.g., "/Type", "/Foo#20Bar").
    /// `allocator`: An allocator for any internal memory allocations.
    ///
    /// This is for when you read `/Some#20Name` from a file and want the `value` to be `/Some Name`.
    pub fn init_from_encoded(allocator: Allocator, full_pdf_name: []const u8) !PdfName {
        if (full_pdf_name.len == 0 or full_pdf_name[0] != '/') {
            std.log.warn("PdfName.init_from_encoded recieved invalid name format: {s}\n", .{full_pdf_name});
            return pdfNameError.InvalidPdfNameFormat;
        }

        const name_part_encoded = full_pdf_name[1..];
        const decoded_name_part = try decode_name(allocator, name_part_encoded);
        defer allocator.free(decoded_name_part);

        const final_value = try std.fmt.allocPrint(allocator, "/{s}", .{decoded_name_part});
        errdefer allocator.free(final_value);

        const encoded_copy = try allocator.dupe(u8, full_pdf_name);

        return .{
            .value = final_value,
            .encoded = encoded_copy,
        };
    }

    pub fn deinit(self: *const PdfName, allocator: Allocator) void {
        allocator.free(self.value);
        if (self.encoded) |e| allocator.free(e);
    }

    /// Returns the string representation that should be written to a PDF file.
    /// This is `encoded` if present, otherwise the canonical `value`.
    pub fn to_pdf_string(self: PdfName) []const u8 {
        if (self.encoded) |e| return e;
        return self.value;
    }

    /// Formats the PdfName for printing (e.g., for `std.debug.print` or `std.fmt.format`).
    /// By default, it prints the canonical `value`.
    pub fn format(self: PdfName, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll(self.value);
    }

    /// Checks if two PdfName instances are equal based on their canonical `value`.
    pub fn eql(self: PdfName, other: PdfName) bool {
        return std.mem.eql(u8, self.value, other.value);
    }

    /// Checks if a PdfName instance is equal to a plain string slice.
    /// This compares against the canonical `value`.
    pub fn eql_str(self: PdfName, other_str: []const u8) bool {
        return std.mem.eql(u8, self.value, other_str);
    }

    pub fn hash(self: PdfName) u32 {
        return std.hash.Crc32.hash(self.value);
    }

    pub fn clone(self: PdfName, allocator: Allocator) !PdfName {
        const new_value = try allocator.dupe(u8, self.value);
        errdefer allocator.free(new_value);

        var new_encoded: ?[]const u8 = null;
        if (self.encoded) |e| {
            new_encoded = try allocator.dupe(u8, e);
            errdefer allocator.free(new_encoded);
        }

        return PdfName{
            .value = new_value,
            .encoded = new_encoded,
            .indirect = self.indirect,
        };
    }

    pub fn clone_to_ptr(self: PdfName, allocator: Allocator) !*PdfName {
        const ptr = try allocator.create(PdfName);
        ptr.* = self.clone(allocator);
        return ptr;
    }
};
