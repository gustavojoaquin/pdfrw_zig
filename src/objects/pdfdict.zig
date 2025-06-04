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

pub const PdfElement = union(enum) {
    Indirect: *PdfIndirect,
    Resolved: pdfobject.PdfObject,

    pub fn deinit(self: PdfElement, allocator: Allocator) void {
        switch (self) {
            .Indirect => |indirect_ptr| {
                indirect_ptr.deinit(allocator);
            },
            .Resolved => |obj| obj.deinit(allocator),
        }
    }

    pub fn clone(self: PdfElement, allocator: Allocator) !PdfElement {
        return switch (self) {
            .Indirect => |iptr| PdfElement{ .Indirect = iptr },
            .Resolved => |obj| PdfElement{ .Resolved = try obj.clone(allocator) },
        };
    }
};

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

    /// Deinitializes the PdfDict, including all keys and values it owns.
    pub fn deinit(self: *PdfDict) void {
        var map_iter = self.map.iterator();
        while (map_iter.next()) |entry| {
            entry.key_ptr.deinit(self.allocator);
            entry.value_ptr.deinit(self.allocator);
        }
        self.map.deinit();

        var priv_attrs_iter = self.private_attrs.iterator();
        while (priv_attrs_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.private_attrs.deinit();
    }

    /// Puts a key-value pair into the dictionary.
    /// If an existing value is replaced, it is deinitialized.
    pub fn put(self: *PdfDict, key: PdfName, value: ?PdfObject) !void {
        // Deinitialize old value if key already exists
        if (self.map.get(key)) |old_value| {
            old_value.deinit(self.allocator);
        }

        if (value) |val| {
            try self.map.put(key, val);
        } else {
            if (self.map.remove(key)) |removed_value| {
                removed_value.deinit(self.allocator);
            }
        }
    }

    /// Retrieves a value from the dictionary.
    /// If the value is an indirect reference, it attempts to resolve it
    /// and replaces the indirect reference with the resolved value in the map.
    pub fn get(self: *PdfDict, key: PdfName) !?PdfObject {
        if (self.map.get(key)) |value| {
            // Use meta.activeTag instead of @tag
            if (std.meta.activeTag(value) == .indirect_ref) {
                const resolved = try value.indirect_ref.real_value(self.allocator);
                if (resolved) |resolved_value| {
                    value.deinit(self.allocator);
                    try self.map.put(key, resolved_value);
                    return resolved_value;
                } else {
                    value.deinit(self.allocator);
                    _ = self.map.remove(key);
                    return null;
                }
            }
            return value;
        }
        return null;
    }
    /// Sets the stream data for the dictionary, and automatically updates the /Length entry.
    pub fn setStream(self: *PdfDict, data: ?[]const u8) !void {
        self.stream = data;
        var length_key = try PdfName.init_from_raw(self.allocator, "Length");
        defer length_key.deinit(self.allocator);

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

    /// Looks up a key, checking the dictionary itself and its parent chain.
    /// Resolves indirect references in the process.
    pub fn getInheritable(self: *PdfDict, key: PdfName) !?PdfObject {
        var current: ?*PdfDict = self;
        var visited = std.AutoHashMap(*PdfDict, void).init(self.allocator);
        defer visited.deinit();

        while (current) |dict| {
            if (visited.contains(dict)) {
                return null;
            }
            try visited.put(dict, {});

            if (try dict.get(key)) |val| {
                return val;
            }
            current = dict.parent;
        }
        return null;
    }

    /// Creates a shallow copy of the dictionary (keys and values are copied by value).
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

    /// Sets a private (non-PDF-spec) attribute.
    /// If an existing value is replaced, it is deinitialized.
    pub fn setPrivate(self: *PdfDict, key: []const u8, value: PdfObject) !void {
        // Deinitialize old value if key already exists
        if (self.private_attrs.get(key)) |old_value| {
            old_value.deinit(self.allocator);
        }
        try self.private_attrs.put(key, value);
    }

    /// Retrieves a private attribute.
    pub fn getPrivate(self: *PdfDict, key: []const u8) ?PdfObject {
        return self.private_attrs.get(key);
    }
};

/// Creates a new PdfDict instance marked as indirect.
pub fn createIndirectPdfDict(allocator: Allocator) PdfDict {
    var dict = PdfDict.init(allocator);
    dict.indirect = true;
    return dict;
}
