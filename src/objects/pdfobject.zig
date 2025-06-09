const std = @import("std");
const pdfname = @import("pdfname.zig");
const pdfarray = @import("pdfarray.zig");
const pdfdict = @import("pdfdict.zig");
const pdfindirect = @import("pdfindirect.zig");
const pdfstring = @import("pdfstring.zig");

const PdfString = pdfstring.PdfString;
const PdfIndirect = pdfindirect.PdfIndirect;
const PdfName = pdfname.PdfName;
const PdfArray = pdfarray.PdfArray;
const PdfDict = pdfdict.PdfDict;
const Allocator = std.mem.Allocator;

/// A PdfObject can be any of the fundamental PDF data types.
/// This is a direct, resolved value.
pub const PdfObject = union(enum) {
    Null: void,
    Boolean: bool,
    Integer: i64,
    Real: f64,
    String: PdfString,
    Name: PdfName,
    Array: *PdfArray,
    Dict: *PdfDict,
    IndirectRef: *PdfIndirect,

    pub fn deinit(self: *PdfObject, allocator: Allocator) void {
        switch (self.*) {
            .String => |*s| s.deinit(),
            .Name => |*n| n.deinit(allocator),
            .Array => |a_ptr| a_ptr.deinit(),
            .Dict => |d_val| {
                var mut_d_val = d_val;
                mut_d_val.deinit();
            },
            .IndirectRef => |iptr| {
                _ = iptr;
            },
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
            .Array => |a_ptr| PdfObject{ .Array = try a_ptr.clone(allocator) },
            .Dict => |d_val| PdfObject{ .Dict = try d_val.copy() },
            .IndirectRef => |iptr| PdfObject{ .IndirectRef = iptr },
        };
    }

    pub fn clone_to_ptr(self: PdfObject, allocator: Allocator) !*PdfObject {
        const ptr = try allocator.create(PdfObject);
        ptr.* = try self.clone(allocator);
        return ptr;
    }

    pub fn initNull() PdfObject {
        return PdfObject{ .Null = {} };
    }
    pub fn initBoolean(val: bool) PdfObject {
        return PdfObject{ .Boolean = val };
    }

    pub fn initInteger(val: i64) PdfObject {
        return PdfObject{ .Integer = val };
    }

    pub fn initReal(val: f64) PdfObject {
        return PdfObject{ .Real = val };
    }

    pub fn initString(val: []const u8, allocator: Allocator) !PdfObject {
        return PdfObject{ .String = try PdfString.fromBytes(allocator, val, .literal) };
    }

    pub fn initName(val: []const u8, allocator: Allocator) !PdfObject {
        return PdfObject{ .Name = try PdfName.init_from_raw(allocator, val) };
    }

    pub fn initArray(initial_indirect: bool, allocator: Allocator) !PdfObject {
        return PdfObject{ .Array = try PdfArray.init(allocator, initial_indirect) };
    }

    pub fn initDict(allocator: Allocator) !PdfObject {
        const dict_ptr = try allocator.create(PdfDict);
        dict_ptr.* = PdfDict.init(allocator);
        return PdfObject{ .Dict = dict_ptr };
    }

    pub fn initIndirectRef(ref: *PdfIndirect) PdfObject {
        return PdfObject{ .IndirectRef = ref };
    }

    pub fn eql(self: PdfObject, other: PdfObject, allocator: Allocator) !bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;

        return switch (self) {
            .Null => true,
            .Boolean => |b1| b1 == other.Boolean,
            .Integer => |int1| int1 == other.Integer,
            .Real => |r1| r1 == other.Real,
            .String => |s1| std.mem.eql(u8, try s1.toUnicode(allocator), try other.String.toUnicode(allocator)),
            .Name => |n1| n1.eql(other.Name),
            .Array => |a1_ptr| a1_ptr.eql(other.Array),
            .Dict => |d1_ptr| d1_ptr.eql(other.Dict),
            .IndirectRef => |ir1_ptr| ir1_ptr.eql(other.IndirectRef),
        };
    }
};
