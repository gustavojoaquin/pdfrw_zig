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

const PdfDictPointerMapContext = struct {
    pub fn hash(_: PdfDictPointerMapContext, key: *PdfDict) u32 {
        const value_ptr = @intFromPtr(key);
        const bytes_ptr = std.mem.asBytes(&value_ptr);
        return @truncate(std.hash_map.hashString(bytes_ptr));
    }
    pub fn eql(_: PdfDictPointerMapContext, a: *PdfDict, b: *PdfDict) bool {
        return a == b;
    }
};

const PdfDictMapContextMap = struct {
    pub fn hash(_: PdfDictMapContextMap, key: *const PdfName) u32 {
        return key.hash();
    }
    pub fn eql(_: PdfDictMapContextMap, a: *const PdfName, b: *const PdfName) bool {
        return a.eql(b.*);
    }
    pub fn deinitKey(_: PdfDictMapContextMap, key: *const PdfName, allocator: Allocator) void {
        key.deinit(allocator);
        allocator.destroy(key);
    }
    pub fn deinitValue(_: PdfDictMapContextMap, value: *PdfObject, allocator: Allocator) void {
        value.*.deinit(allocator);
        allocator.destroy(value);
    }
};

// PdfElement might not be needed if PdfObject now contains IndirectRef.
// However, if you want to distinguish between a PdfObject that IS an indirect reference
// vs. a PdfObject that IS a dictionary (which might contain indirect references),
// PdfElement could still be useful. For now, let's assume PdfObject handles it.
// If PdfElement is removed, the map type and get/put signatures change.
// For minimal changes to THIS file, let's keep PdfElement for now,
// but its .Resolved branch would take a PdfObject.
// This part is a larger design choice. The error messages point to PdfObject directly
// having .indirect_ref characteristics.
//
// Decision: I will proceed assuming PdfObject has .IndirectRef, making PdfElement
// somewhat redundant or needing re-evaluation.
// The errors in `pdfdict.zig` were about `.integer`, not `PdfElement`.
// The line `if (std.meta.activeTag(value) == .indirect_ref)` in `PdfDict.get`
// strongly suggests `value` (which is `PdfObject`) has an `.indirect_ref` tag.

pub const PdfDict = struct {
    allocator: Allocator,
    map: std.HashMap(*const PdfName, *PdfObject, PdfDictMapContextMap, std.hash_map.default_max_load_percentage),
    indirect: bool = false,
    stream: ?[]const u8 = null,
    parent: ?*PdfDict = null,
    private_attrs: std.StringHashMap(*PdfObject),

    pub fn init(allocator: Allocator) PdfDict {
        return .{
            .allocator = allocator,
            .map = std.HashMap(*const PdfName, *PdfObject, PdfDictMapContextMap, std.hash_map.default_max_load_percentage).init(allocator),
            .private_attrs = std.StringHashMap(*PdfObject).init(allocator),
        };
    }

    pub fn deinit(self: *PdfDict) void {
        var map_iter = self.map.iterator();
        while (map_iter.next()) |entry| {
            PdfDictMapContextMap.deinitKey(PdfDictMapContextMap{}, entry.key_ptr.*, self.allocator);
            PdfDictMapContextMap.deinitValue(PdfDictMapContextMap{}, entry.value_ptr.*, self.allocator);
        }
        self.map.deinit();

        var priv_attrs_iter = self.private_attrs.iterator();
        while (priv_attrs_iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr);
        }
        self.private_attrs.deinit();
    }

    pub fn put(self: *PdfDict, key: PdfName, value: ?PdfObject) !void {
        if (value) |v| {
            const new_key_ptr = try key.clone_to_ptr(self.allocator);
            errdefer {
                new_key_ptr.*.deinit(self.allocator);
                self.allocator.destroy(new_key_ptr);
            }

            const new_value_ptr = try v.clone_to_ptr(self.allocator);
            errdefer {
                new_value_ptr.*.deinit(self.allocator);
                self.allocator.destroy(new_value_ptr);
            }

            if (try self.map.fetchPut(new_key_ptr, new_value_ptr)) |old_entry| {
                PdfDictMapContextMap.deinitKey(.{}, old_entry.key, self.allocator);
                PdfDictMapContextMap.deinitValue(.{}, old_entry.value, self.allocator);
            }
        } else {
            if (self.map.fetchRemove(&key)) |removed_entry| {
                PdfDictMapContextMap.deinitKey(.{}, removed_entry.key, self.allocator);
                PdfDictMapContextMap.deinitValue(.{}, removed_entry.value, self.allocator);
            }
        }
    }

    pub fn get(self: *PdfDict, key: *const PdfName) !?PdfObject {
        if (self.map.getEntry(key)) |map_entry| {
            const current_value_ptr = map_entry.value_ptr.*;

            if (std.meta.activeTag(current_value_ptr.*) == .IndirectRef) {
                const indirect_ref_instance_ptr = current_value_ptr.*.IndirectRef;
                const resolved_obj_actual_ptr = try indirect_ref_instance_ptr.*.real_value(self.allocator);

                if (resolved_obj_actual_ptr) |resolved_obj| {
                    const owned_resolved_obj = try resolved_obj.*.clone(self.allocator);
                    errdefer owned_resolved_obj.deinit(self.allocator);

                    const removed_entry = self.map.fetchRemove(map_entry.key_ptr.*).?;

                    PdfDictMapContextMap.deinitKey(.{}, removed_entry.key, self.allocator);
                    PdfDictMapContextMap.deinitValue(.{}, removed_entry.value, self.allocator);

                    const new_key_for_reinsert_ptr = try (map_entry.key_ptr.*).clone_to_ptr(self.allocator);
                    const new_value_for_reinsert_ptr = try owned_resolved_obj.clone_to_ptr(self.allocator);

                    errdefer {
                        new_key_for_reinsert_ptr.*.deinit(self.allocator);
                        self.allocator.destroy(new_key_for_reinsert_ptr);
                        new_value_for_reinsert_ptr.*.deinit(self.allocator);
                        self.allocator.destroy(new_value_for_reinsert_ptr);
                    }

                    try self.map.put(new_key_for_reinsert_ptr, new_value_for_reinsert_ptr);
                    return owned_resolved_obj;
                } else {
                    const removed_obj = self.map.fetchRemove(map_entry.key_ptr.*).?;
                    PdfDictMapContextMap.deinitKey(.{}, removed_obj.key, self.allocator);
                    PdfDictMapContextMap.deinitValue(.{}, removed_obj.value, self.allocator);
                    return null;
                }
            }
            return try current_value_ptr.*.clone(self.allocator);
        }
        return null;
    }

    pub fn setStream(self: *PdfDict, data: ?[]const u8) !void {
        self.stream = data;
        const length_key = try PdfName.init_from_raw(self.allocator, "Length");

        if (data) |d| {
            const integer_obj = PdfObject{ .Integer = @intCast(d.len) };
            try self.put(length_key, integer_obj);
        } else {
            try self.put(length_key, null);
        }
    }

    // getResolved might need re-evaluation based on PdfObject now having IndirectRef.
    // The current `get` already resolves and replaces.

    pub const Entry = struct { key: PdfName, value: PdfObject };
    pub const Iterator = struct {
        inner: std.HashMap(*const PdfName, *PdfObject, PdfDictMapContextMap, std.hash_map.default_max_load_percentage).Iterator,
        dict: *PdfDict,
        pub fn next(self: *Iterator) !?Entry {
            while (self.inner.next()) |entry| {
                if (try self.dict.get((entry.key_ptr.*))) |resolved_value| {
                    return .{
                        .key = try entry.key_ptr.*.*.clone(self.dict.allocator),
                        .value = resolved_value,
                    };
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
        var visited = std.HashMap(*PdfDict, void, PdfDictPointerMapContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer visited.deinit();

        while (current) |dict| {
            if (visited.contains(dict)) return error.CircularParentReference;
            try visited.put(dict, {});

            if (try dict.get(&key)) |val| {
                return val;
            }
            current = dict.parent;
        }
        return null;
    }

    pub fn copy(self: *const PdfDict) error{OutOfMemory}!PdfDict {
        var new_dict = PdfDict.init(self.allocator);
        new_dict.indirect = self.indirect;

        new_dict.stream = if (self.stream) |s| try self.allocator.dupe(u8, s) else null;
        errdefer if (new_dict.stream) |s| self.allocator.free(s);

        new_dict.parent = self.parent;

        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            const new_key_ptr = try self.allocator.create(PdfName);
            errdefer self.allocator.destroy(new_key_ptr);
            new_key_ptr.* = try (entry.key_ptr.*).clone(self.allocator);
            errdefer new_key_ptr.*.deinit(self.allocator);

            const new_value_ptr = try self.allocator.create(PdfObject);
            errdefer self.allocator.destroy(new_value_ptr);
            new_value_ptr.* = try (entry.value_ptr.*).clone(self.allocator);
            errdefer new_value_ptr.*.deinit(self.allocator);

            try new_dict.map.put(new_key_ptr, new_value_ptr);
        }

        var priv_iter = self.private_attrs.iterator();
        while (priv_iter.next()) |entry| {
            const new_priv_value_ptr = try self.allocator.create(PdfObject);
            errdefer self.allocator.destroy(new_priv_value_ptr);
            new_priv_value_ptr.* = try entry.value_ptr.*.clone(self.allocator);
            errdefer new_priv_value_ptr.*.deinit(self.allocator);

            try new_dict.private_attrs.put(try self.allocator.dupe(u8, entry.key_ptr.*), new_priv_value_ptr);
        }
        return new_dict;
    }
    pub fn setPrivate(self: *PdfDict, key: []const u8, value: PdfObject) !void {
        const new_value_ptr = try self.allocator.create(PdfObject);
        errdefer self.allocator.destroy(new_value_ptr);
        new_value_ptr.* = try value.clone(self.allocator);
        errdefer new_value_ptr.*.deinit(self.allocator);

        const old_value_ptr_opt = self.private_attrs.fetchPut(key, new_value_ptr) catch |err| {
            if (err == error.OutOfMemory) {
                return err;
            }
            unreachable;
        };

        if (old_value_ptr_opt) |old_entry| {
            old_entry.value.*.deinit(self.allocator);
            self.allocator.destroy(old_entry.value);
        }
    }

    pub fn getPrivate(self: *PdfDict, key: []const u8) ?PdfObject {
        if (self.private_attrs.get(key)) |value_ptr| {
            return value_ptr.*;
        }
        return null;
    }
};

pub fn createIndirectPdfDict(allocator: Allocator) PdfDict {
    var dict = PdfDict.init(allocator);
    dict.indirect = true;
    return dict;
}
