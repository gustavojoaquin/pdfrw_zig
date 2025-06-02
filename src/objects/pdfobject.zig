const std = @import("std");

/// A PdfObject is a textual representation of any PDF file object
/// other than an array, dict or string.
/// It has an 'indirect' attribute which defaults to false.
pub const PdfObject = struct {
    value: []const u8,
    indirect: bool,

    pub fn init(allocator: std.mem.Allocator, text: []const u8) !*PdfObject {
        const self = try allocator.create(PdfObject);
        self.* = .{
            .value = text,
            .indirect = false,
        };
        return self;
    }

    pub fn init_indirect(allocator: std.mem.Allocator, text: []const u8, indirect: bool) !*PdfObject {
        const self = try allocator.create(PdfObject);
        self.* = .{ .value = text, .indirect = indirect };
        return self;
    }

    pub fn deinit(self: *PdfObject, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    /// Checks if two PdfObject instances are equal.
    /// Equality is based on both their 'value' string and their 'indirect' flag.
    pub fn eql(self: *PdfObject, other: *PdfObject) bool {
        return std.mem.eql(u8, self.value, other.value) and self.indirect == other.indirect;
    }

    /// Checks if a PdfObject is equal to a plain string slice.
    /// For this comparison to be true, the PdfObject's 'indirect' flag *must* be false.
    pub fn eql_str(self: *PdfObject, other_str: []const u8) bool {
        return !self.indirect and std.mem.eql(u8, self.value, other_str);
    }
};
