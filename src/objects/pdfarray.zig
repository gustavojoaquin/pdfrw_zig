const std = @import("std");
const Allocator = std.mem.Allocator;
const pdfobject = @import("pdfobject.zig");
const pdfindirect = @import("pdfindirect.zig");

const PdfObject = pdfobject.PdfObject;
const PdfIndirect = pdfindirect.PdfIndirect;

const PdfArrayItem = union(enum) {
    unresolved: *PdfIndirect,
    resolved: PdfObject,
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
                .resolved => |*resolved_object_ptr| {
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

        const pdf_null_obj_ptr_const = try PdfObject.init(self.allocator, "null");
        const pdf_null_obj_const = pdf_null_obj_ptr_const.*;

        var i: usize = 0;

        while (i < self.item.items.len) : (i += 1) {
            var current_item_ptr = &self.item.items[i];
            switch (current_item_ptr.*) {
                .unresolved => |indirect_obj| {
                    const resolved_obj_maybe = indirect_obj.real_value(self.allocator) catch |err| {
                        std.debug.print("PdfArray resolver: Error loading indirect object: {any}\n", .{err});
                        const new_item_ptr = try self.allocator.create(PdfArrayItem);
                        new_item_ptr.* = .{ .resolved = pdf_null_obj_const };
                        current_item_ptr = new_item_ptr;
                        continue;
                    };

                    if (resolved_obj_maybe) |resolved| {
                        current_item_ptr.* = .{ .resolved = resolved.* };
                    } else {
                        current_item_ptr = .{ .resolved = pdf_null_obj_const };
                    }
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
    pub fn appendObject(self: *PdfArray, obj: PdfObject) !void {
        try self.item.append(.{ .resolved = obj });
    }

    /// Extends the array with items from a slice.
    pub fn extend(self: *PdfArray, items: []PdfArrayItem) !void {
        try self.item.appendSlice(items);
    }

    pub fn get(self: *PdfArray, index: usize) !*PdfObject {
        try self.ensureResolved();

        return switch (self.item.items[index]) {
            .resolved => |obj| &obj,
            .unresolved => unreachable,
        };
    }

    pub fn len(self: *PdfArray) usize {
        return self.item.items.len;
    }

    pub fn pop(self: *PdfArray) !?PdfObject {
        try self.ensureResolved(self.allocator);
        if (self.item.pop()) |item| {
            return switch (item) {
                .resolved => |obj| obj,
                .unresolved => unreachable,
            };
        }
        return null;
    }

    pub const Iterator = struct {
        array_ptr: *PdfArray,
        next_index: usize,

        pub fn next(self: *Iterator) !?PdfObject {
            const item = self.array_ptr.item.items[self.next_index];
            self.next_index += 1;
            return switch (item) {
                .resolved => |obj| obj,
                .unresolved => unreachable,
            };
        }
    };

    pub fn iterator(self: *PdfArray) !Iterator {
        try self.ensureResolved();
        return .{ .array_ptr = self, .next_index = 0 };
    }

    pub fn count(self: *PdfArray, item_to_count: PdfObject) !u32 {
        try self.ensureResolved();
        var c: u32 = 0;

        for (self.item.items) |array_item| {
            switch (array_item) {
                .resolved => |obj| {
                    if (obj.eql(item_to_count)) {
                        c += 1;
                    }
                },
                .unresolved => unreachable,
            }
        }
        return c;
    }
};
