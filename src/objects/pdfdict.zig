const std = @import("std");
const pdfname = @import("pdfname.zig");
const pdfobject = @import("pdfobject.zig");
const pdfindirect = @import("pdfindirect.zig");
const errors = @import("errors.zig");

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
    indirect_num: ?u32 = null,
    indirect_gen: ?u16 = null,

    pub fn init(allocator: Allocator) !*PdfDict {
        const self = try allocator.create(PdfDict);
        self.* = .{
            .allocator = allocator,
            .map = std.HashMap(*const PdfName, *PdfObject, PdfDictMapContextMap, std.hash_map.default_max_load_percentage).init(allocator),
            .private_attrs = std.StringHashMap(*PdfObject).init(allocator),
            .indirect_num = null,
            .indirect_gen = null,
        };
        return self;
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
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.private_attrs.deinit();
        self.allocator.destroy(self);
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
                    const new_value_for_map_ptr = try resolved_obj.clone_to_ptr(self.allocator);
                    errdefer {
                        new_value_for_map_ptr.*.deinit(self.allocator);
                        self.allocator.destroy(new_value_for_map_ptr);
                    }

                    const old_value_ptr = map_entry.value_ptr.*;

                    map_entry.value_ptr.* = new_value_for_map_ptr;

                    old_value_ptr.*.deinit(self.allocator);
                    self.allocator.destroy(old_value_ptr);

                    return try resolved_obj.clone(self.allocator);
                } else {
                    const removed_entry = self.map.fetchRemove(key).?;
                    PdfDictMapContextMap.deinitKey(.{}, removed_entry.key, self.allocator);
                    PdfDictMapContextMap.deinitValue(.{}, removed_entry.value, self.allocator);
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
        defer length_key.deinit(self.allocator);

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

    pub fn copy(self: *const PdfDict) PdfError!*PdfDict {
        const new_dict_ptr = try PdfDict.init(self.allocator);
        errdefer new_dict_ptr.deinit();

        new_dict_ptr.indirect = self.indirect;
        new_dict_ptr.indirect_num = self.indirect_num;
        new_dict_ptr.indirect_gen = self.indirect_gen;

        if (self.stream) |s| {
            new_dict_ptr.stream = try self.allocator.dupe(u8, s);
        } else {
            new_dict_ptr.stream = null;
        }

        new_dict_ptr.parent = self.parent;

        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            const original_key_name = entry.key_ptr.*;
            const original_value_obj = entry.value_ptr.*;

            const cloned_key_val = try original_key_name.clone(self.allocator);
            errdefer cloned_key_val.deinit(self.allocator);

            var cloned_value_val = try original_value_obj.clone(self.allocator);
            errdefer cloned_value_val.deinit(self.allocator);

            const new_key_ptr_in_map = try self.allocator.create(PdfName);
            new_key_ptr_in_map.* = cloned_key_val;
            errdefer self.allocator.destroy(new_key_ptr_in_map);

            const new_value_ptr_in_map = try self.allocator.create(PdfObject);
            new_value_ptr_in_map.* = cloned_value_val;
            errdefer self.allocator.destroy(new_value_ptr_in_map);

            try new_dict_ptr.map.put(new_key_ptr_in_map, new_value_ptr_in_map);
        }

        var priv_iter = self.private_attrs.iterator();
        while (priv_iter.next()) |entry| {
            var cloned_priv_value_val = try entry.value_ptr.*.clone(self.allocator);
            errdefer cloned_priv_value_val.deinit(self.allocator);

            const new_priv_value_ptr = try self.allocator.create(PdfObject);
            new_priv_value_ptr.* = cloned_priv_value_val;
            errdefer self.allocator.destroy(new_priv_value_ptr);

            const cloned_key_str = try self.allocator.dupe(u8, entry.key_ptr.*);
            errdefer self.allocator.free(cloned_key_str);

            try new_dict_ptr.private_attrs.put(cloned_key_str, new_priv_value_ptr);
        }
        return new_dict_ptr;
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

    /// Compares two PdfDict objects for equality.
    /// This method performs deep comparison of resolved values.
    /// It resolves indirect references within the dictionaries as part of the comparison.
    /// Returns true if both dictionaries contain the same resolved PdfObjects
    /// for the same PdfName keys, and if their stream data is identical.
    /// Inheritable values (`parent`) and internal `private_attrs` are NOT considered for equality.
    pub fn eql(self: *PdfDict, other: *PdfDict) PdfError!bool {
        if (self.stream) |s1| {
            if (other.stream) |s2| {
                if (std.mem.eql(u8, s1, s2)) return false;
            } else return false;
        } else {
            if (other.stream != null) return false;
        }

        if (self.map.count() != other.map.count()) return false;

        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            const self_key_ptr = entry.key_ptr.*;

            var self_resolved_obj_ptr = try self.get(self_key_ptr);
            defer if (self_resolved_obj_ptr != null) self_resolved_obj_ptr.?.deinit(self.allocator);

            var other_resolved_obj_ptr = try other.get(self_key_ptr);
            defer if (other_resolved_obj_ptr != null) other_resolved_obj_ptr.?.deinit(self.allocator);

            if (self_resolved_obj_ptr) |self_val| {
                if (other_resolved_obj_ptr != null)  {
                    if (!(try self_val.eql(&other_resolved_obj_ptr.?, self.allocator))) return false;
                } else return false;
            } else {
                if (other_resolved_obj_ptr != null) return false;
            }
        }

        return true;
    }
};

pub fn createIndirectPdfDict(allocator: Allocator) !*PdfDict {
    const dict = try PdfDict.init(allocator);
    dict.*.indirect = true;
    return dict;
}
