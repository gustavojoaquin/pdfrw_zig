const std = @import("std");
const pdfname = @import("pdfname.zig");
const pdfarray = @import("pdfarray.zig");
const pdfdict = @import("pdfdict.zig");

const PdfName = pdfname.PdfName;
const PdfArray = pdfarray.PdfArray;
const PdfDict = pdfdict.PdfDict;
const Allocator = std.mem.Allocator;

// const PdfDict: type = undefined;
// const PdfArray: type = undefined;

// pub fn setPdfType(pd: type, pa: type) void {
//     PdfDict = pd;
//     PdfArray = pa;
// }

pub const PdfString = struct {
    value: []const u8,

    pub fn init_From_litaral(allocator: Allocator, literal: []const u8) !PdfString {
        const owned_val = allocator.dupe(u8, literal);
        return PdfString{ .value = owned_val };
    }

    pub fn init_from_hex(allocator: Allocator, hex_string_brackets: []const u8) !PdfString {
        if (hex_string_brackets.len < 2 or hex_string_brackets[0] != '<' or hex_string_brackets[hex_string_brackets.len - 1] != '>') return error.InvalidHexStringFormat;

        const hex_content = hex_string_brackets[1 .. hex_string_brackets.len - 1];
        var bytes = std.ArrayList(u8).init(allocator);
        errdefer bytes.deinit();
        try std.fmt.hexToBytes(bytes.writer(), hex_content);
        return PdfString{ .value = bytes.toOwnedSlice() };
    }

    pub fn deinit(self: *const PdfString, allocator: Allocator) void {
        allocator.free(self.value);
    }

    pub fn eql(self: *PdfString, other: *PdfString) bool {
        return std.mem.eql(u8, self.value, other.value);
    }

    pub fn clone(self: *PdfString, allocator: Allocator) !PdfString {
        const new_value = allocator.dupe(u8, self.value);
        return PdfString{ .value = new_value };
    }
};

/// A PdfObject can be any of the fundamental PDF data types.
/// This is a direct, resolved value.
pub const PdfObject = union(enum) {
    Null: void,
    Boolean: bool,
    Integer: i64,
    Real: f64,
    String: PdfString,
    Name: PdfName,
    Array: PdfArray,
    Dict: PdfDict,

    pub fn deinit(self: PdfObject, allocator: Allocator) void {
        switch (self) {
            .String => |s| s.deinit(allocator),
            .Name => |n| n.deinit(allocator),
            .Array => |a| a.deinit(allocator),
            .Dict => |d| d.deinit(allocator),
            else => {},
        }
    }

    pub fn clone(self: PdfObject, allocator: Allocator) !PdfObject {
        return switch (self) {
            .Null => PdfObject.Null,
            .Boolean => |b| PdfObject{ .Boolean = b },
            .Integer => |i| PdfObject{ .Integer = i },
            .Real => |r| PdfObject{ .Real = r },
            .String => |s| PdfObject{ .String = try s.clone(allocator) },
            .Name => |n| PdfObject{ .Name = try n.clone(allocator) },
            .Array => |a| PdfObject{ .Array = try a.clone(allocator) },
            .Dict => |d| PdfObject{ .Dict = try d.clone(allocator) },
        };
    }

    pub fn initNull() PdfObject {
        return PdfObject{ .Null = void };
    }
    pub fn initBoolean(val: bool) PdfObject {
        return PdfObject{ .Boolean = val };
    }

    pub fn initInteger(val: u64) PdfObject {
        return PdfObject{ .Integer = val };
    }

    pub fn initReal(val: f64) PdfObject {
        return PdfObject{ .Real = val };
    }

    pub fn initString(val: []const u8, allocator: Allocator) !PdfObject {
        return PdfObject{ .String = try PdfString.init_From_litaral(allocator, val) };
    }

    pub fn initName(val: []const u8, allocator: Allocator) !PdfObject {
        return PdfObject{ .Name = try PdfName.init_from_raw(allocator, val) };
    }

    pub fn initArray(initial_indirect: bool, allocator: Allocator) !PdfObject {
        return PdfObject{ .Array = try PdfArray.init(allocator, initial_indirect) };
    }

    pub fn initDict(allocator: Allocator) !PdfObject {
        return PdfObject{ .Dict = try PdfDict.init(allocator) };
    }

    /// Checks if two PdfObject instances are equal.
    /// Equality is based on both their 'value' string and their 'indirect' flag.
    /// TODO: Implement eql functions for PdfArray and PdfDict
    pub fn eql(self: *PdfObject, other: *PdfObject) bool {
        switch (self.*) {
            .Name => |name| {
                if (other.* != .Name) return false;
                return name.eql(other.Name);
            },
            .Array => |_| {
                if (other.* != .Array) return false;
                return false;
            },
            .Dict => |_| {
                if (other.* != .Dict) return false;
                return false;
            },
        }
    }
};
