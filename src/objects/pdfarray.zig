const std = @import("std");
const Allocator = std.mem.Allocator;
const pdfobject = @import("pdfobject.zig");
const pdfindirect = @import("pdfindirect.zig");

const PdfObject = pdfobject.PdfObject;
const PdfIndirect = pdfindirect.PdfIndirect;

pub const PdfArrayItem = union(enum) {
    unresolved: *PdfIndirect,
    resolved: *PdfObject,
};

pub const PdfArray = struct {
    allocator: Allocator,
    item: std.ArrayList(PdfArrayItem),
    indirect: bool,
    has_been_resolved: bool,

    pub fn init(allocator: Allocator, initial_indirect: bool) !*PdfArray {
        const self = try allocator.create(PdfArray);
        self.* = .{ .allocator = allocator, .indirect = initial_indirect, .item = std.ArrayList(PdfArrayItem).init(allocator), .has_been_resolved = false };
        return self;
    }

    pub fn deinit(self: *PdfArray) void {
        var i: usize = 0;
        while (i < self.item.items.len) : (i += 1) {
            const item_in_array_ptr = &self.item.items[i];
            switch (item_in_array_ptr.*) {
                .resolved => |resolved_object_ptr| {
                    resolved_object_ptr.deinit(self.allocator);
                },
                .unresolved => {},
            }
        }
        self.item.deinit();
        self.allocator.destroy(self);
    }

    fn ensureResolved(self: *PdfArray) !void {
        if (self.has_been_resolved) return;

        var i: usize = 0;
        while (i < self.item.items.len) : (i += 1) {
            const current_item_ptr = &self.item.items[i];
            switch (current_item_ptr.*) {
                .unresolved => |indirect| {
                    const resolved_result = indirect.real_value(self.allocator);
                    var loaded_obj_to_store: ?*PdfObject = null;

                    if (resolved_result) |loaded_obj_optional| {
                        loaded_obj_to_store = loaded_obj_optional;
                    } else |err| {
                        std.debug.print("Error resolving indirect {d} {d} R: {any}\n", .{ indirect.ref.obj_num, indirect.ref.gen_num, err });
                    }

                    current_item_ptr.* = if (loaded_obj_to_store) |obj|
                        .{ .resolved = obj }
                    else
                        .{ .resolved = try PdfObject.init(self.allocator, "null") };
                },
                .resolved => {},
            }
        }
        self.has_been_resolved = true;
    }
    /// Appends an unresolved PdfIndirect object.
    pub fn appendIndirect(self: *PdfArray, indirect_obj: *PdfIndirect) !void {
        try self.item.append(.{ .unresolved = indirect_obj });
    }

    /// Appends an already resolved PdfObject.
    /// Note: `obj` should be a pointer, and PdfArray will now own it.
    pub fn appendObject(self: *PdfArray, obj: *PdfObject) !void {
        try self.item.append(.{ .resolved = obj });
    }

    /// Extends the array with items from a slice.
    pub fn extend(self: *PdfArray, items: []const PdfArrayItem) !void {
        try self.item.appendSlice(items);
    }

    pub fn get(self: *PdfArray, index: usize) !*PdfObject {
        try self.ensureResolved();
        return switch (self.item.items[index]) {
            .resolved => |obj_ptr| obj_ptr,
            .unresolved => unreachable,
        };
    }

    pub fn len(self: *PdfArray) usize {
        return self.item.items.len;
    }

    pub fn pop(self: *PdfArray) !?*PdfObject {
        try self.ensureResolved();

        if (self.item.pop()) |item| {
            return switch (item) {
                .resolved => |obj_ptr| obj_ptr,
                .unresolved => unreachable,
            };
        }
        return null;
    }

    pub const Iterator = struct {
        array_ptr: *PdfArray,
        next_index: usize,

        pub fn next(self: *Iterator) !?*PdfObject {
            if (self.next_index >= self.array_ptr.item.items.len) {
                return null;
            }
            const item = self.array_ptr.item.items[self.next_index];
            self.next_index += 1;
            return switch (item) {
                .resolved => |obj_ptr| obj_ptr,
                .unresolved => unreachable,
            };
        }
    };

    pub fn iterator(self: *PdfArray) !Iterator {
        try self.ensureResolved();
        return .{ .array_ptr = self, .next_index = 0 };
    }

    pub fn count(self: *PdfArray, item_to_count: *PdfObject) !u32 {
        try self.ensureResolved();
        var c: u32 = 0;

        for (self.item.items) |array_item| {
            switch (array_item) {
                .resolved => |obj_ptr| {
                    if (obj_ptr.eql(item_to_count)) {
                        c += 1;
                    }
                },
                .unresolved => unreachable,
            }
        }
        return c;
    }
};

