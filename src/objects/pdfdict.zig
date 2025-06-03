const std = @import("std");
const pdfname = @import("pdfname.zig");
const pdfobject = @import("pdfobject.zig");
const pdfindirect = @import("pdfindirect.zig");
const errors = @import("../errors.zig");

const PdfName = pdfname.PdfName;
const PdfObject = pdfobject.PdfObject;
const PdfIndirect = pdfindirect.PdfIndirect;
const PdfError = errors.PdfError;
const Allocator = std.mem.Allocator;

pub const PdfDict = struct {
    allocator: Allocator,
    map: std.AutoHashMap(PdfName, PdfObject),
    indirect: bool = false,
    stream: ?[]const u8 = null,
    parent: ?*PdfDict = null,
    private_attrs: std.StringHashMap(PdfObject),

    pub fn init(allocator: Allocator) PdfDict {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(PdfName, PdfObject).init(allocator),
            .private_attrs = std.StringHashMap(PdfObject).init(allocator),
        };
    }

    pub fn deinit(self: *PdfDict) void {
        self.map.deinit();
        self.private_attrs.deinit();
    }

    pub fn put(self: *PdfDict, key: PdfName, value: ?PdfObject) !void {
        if (value) |val| {
            try self.map.put(key, val);
        } else {
            _ = self.map.remove(key);
        }
    }

    pub fn get(self: *PdfDict, key: PdfName) !?PdfObject {
        if (self.map.get(key)) |value| {
            if (value == .indirect_ref) {
                const resolved = try value.indirect_ref.resolve();
                if (resolved) |resolved_value| {
                    try self.map.put(key, resolved_value);
                    return resolved_value;
                } else {
                    _ = self.map.remove(key);
                    return null;
                }
            }
            return value;
        }
        return null;
    }

    pub fn setStream(self: *PdfDict, data: ?[]const u8) !void {
        self.stream = data;
        const length_key = PdfName.init("/Length");
        if (data) |d| {
            try self.put(length_key, PdfObject{ .integer = @intCast(d.len) });
        } else {
            try self.put(length_key, null);
        }
    }

    pub const Entry = struct { key: PdfName, value: PdfObject };
    pub const Iterator = struct {
        inner: std.AutoHashMap(PdfName, PdfObject).Iterator,
        dict: *PdfDict,
        index: usize = 0,

        pub fn next(self: *Iterator) !?Entry {
            while (self.inner.next()) |entry| {
                if (try self.dict.get(entry.key_ptr.*)) |value| {
                    return .{ .key = entry.key_ptr.*, .value = value };
                }
            }
            return null;
        }
    };

    pub fn iterator(self: *PdfDict) Iterator {
        return .{ .inner = self.map.iterator(), .dict = self };
    }

    pub fn getInheritable(self: *PdfDict, key: PdfName) !?PdfObject {
        var current: ?*PdfDict = self;
        var visited = std.AutoHashMap(*PdfDict, void).init(self.allocator);
        defer visited.deinit();

        while (current) |dict| {
            if (visited.contains(dict)) {
                return null; // Cycle detected
            }
            try visited.put(dict, {});

            if (try dict.get(key)) |val| {
                return val;
            }
            current = dict.parent;
        }
        return null;
    }

    pub fn copy(self: *PdfDict) !PdfDict {
        var new_dict = PdfDict.init(self.allocator);
        new_dict.indirect = self.indirect;
        new_dict.stream = self.stream;
        new_dict.parent = self.parent;

        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            try new_dict.map.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var priv_iter = self.private_attrs.iterator();
        while (priv_iter.next()) |entry| {
            try new_dict.private_attrs.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        return new_dict;
    }

    pub fn setPrivate(self: *PdfDict, key: []const u8, value: PdfObject) !void {
        try self.private_attrs.put(key, value);
    }

    pub fn getPrivate(self: *PdfDict, key: []const u8) ?PdfObject {
        return self.private_attrs.get(key);
    }
};

pub fn createIndirectPdfDict(allocator: Allocator) PdfDict {
    var dict = PdfDict.init(allocator);
    dict.indirect = true;
    return dict;
}
