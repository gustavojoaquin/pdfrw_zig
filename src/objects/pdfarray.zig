const std = @import("std");
const Allocator = std.mem.Allocator;
const pdfobject = @import("pdfobject.zig");
const pdfindirect = @import("pdfindirect.zig");

const PdfObject = pdfobject.PdfObject;
const PdfIndirect = pdfindirect.PdfIndirect;

/// Represents an item within a PdfArray.
/// It can either be an unresolved indirect reference or a fully resolved PdfObject.
pub const PdfArrayItem = union(enum) {
    unresolved: *PdfIndirect,
    resolved: PdfObject,
};

pub const PdfArray = struct {
    allocator: Allocator,
    items: std.ArrayList(PdfArrayItem),

    /// Indicates if this PdfArray itself is an indirect object in the PDF.
    /// This is distinct from its items being resolved.
    is_indirect_object: bool,

    /// Flag to track if an attempt has been made to resolve all items.
    /// If ensureResolved fails partway, this might be true but items still unresolved.
    /// More robust would be to iterate and check each time if not fully resolved.
    /// For simplicity, we'll keep it, but ensure ensureResolved is thorough.
    all_items_resolved_attempted: bool,

    pub fn init(allocator: Allocator, initial_is_indirect: bool) !*PdfArray {
        const self = try allocator.create(PdfArray);
        self.* = .{
            .allocator = allocator,
            .items = std.ArrayList(PdfArrayItem).init(allocator),
            .is_indirect_object = initial_is_indirect,
            .all_items_resolved_attempted = false,
        };
        return self;
    }

    pub fn deinit(self: *PdfArray) void {
        for (self.items.items) |*item_in_array_ptr| {
            switch (item_in_array_ptr.*) {
                .resolved => |*resolved_object_value| {
                    resolved_object_value.deinit(self.allocator);
                },
                .unresolved => |indirect_ptr| {
                    _ = indirect_ptr;
                },
            }
        }
        self.items.deinit();
        self.allocator.destroy(self);
    }

    /// Ensures all items in the array are resolved.
    /// If an indirect object cannot be resolved (loader returns null), it's replaced with PdfObject.Null.
    /// If the loader itself errors, this function will propagate that error.
    fn ensureAllItemsResolved(self: *PdfArray) !void {
        if (self.all_items_resolved_attempted) {
            var still_unresolved = false;
            for (self.items.items) |item_val| {
                if (item_val == .unresolved) {
                    still_unresolved = true;
                    break;
                }
            }
            if (!still_unresolved) return;
            self.all_items_resolved_attempted = false;
        }

        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            const current_item_storage_ptr = &self.items.items[i];

            switch (current_item_storage_ptr.*) {
                .unresolved => |indirect_obj_ptr| {
                    const resolved_obj_from_indirect_cache = indirect_obj_ptr.real_value(self.allocator) catch |err| {
                        std.log.err("PdfArray: Error resolving indirect object {{obj_num={}, gen_num={}}}: {any}", .{
                            indirect_obj_ptr.ref.obj_num, indirect_obj_ptr.ref.gen_num, err,
                        });
                        return err;
                    };

                    if (resolved_obj_from_indirect_cache) |cached_obj_ptr| {
                        const owned_resolved_obj = try cached_obj_ptr.*.clone(self.allocator);
                        errdefer owned_resolved_obj.deinit(self.allocator);
                        current_item_storage_ptr.* = .{ .resolved = owned_resolved_obj };
                    } else {
                        current_item_storage_ptr.* = .{ .resolved = PdfObject.Null };
                    }
                },
                .resolved => {},
            }
        }
        self.all_items_resolved_attempted = true;
    }

    /// Appends an unresolved PdfIndirect object.
    /// The PdfArray does NOT take ownership of the `indirect_obj` pointer itself,
    /// assuming it's managed externally (e.g., by a cache or the caller).
    pub fn appendIndirect(self: *PdfArray, indirect_obj: *PdfIndirect) !void {
        if (self.all_items_resolved_attempted) self.all_items_resolved_attempted = false;
        try self.items.append(.{ .unresolved = indirect_obj });
    }

    /// Appends an already resolved PdfObject.
    /// The `PdfArray` takes ownership of the provided `obj` (it's moved).
    pub fn appendObject(self: *PdfArray, obj: PdfObject) !void {
        try self.items.append(.{ .resolved = obj });
    }

    /// Extends the array with items from a slice.
    /// Ownership of items in the slice is handled based on their type:
    /// - .unresolved: pointer is copied, external ownership assumed.
    /// - .resolved: PdfObject is MOVED from the slice item into the array.
    ///              If the slice items need to persist, they should be cloned before calling extend.
    pub fn extend(self: *PdfArray, new_items: []const PdfArrayItem) !void {
        if (self.all_items_resolved_attempted) {
            for (new_items) |item| {
                if (item == .unresolved) {
                    self.all_items_resolved_attempted = false;
                    break;
                }
            }
        }
        try self.items.appendSlice(new_items);
    }

    /// Gets a pointer to the PdfObject at the given index.
    /// The returned pointer is to memory managed by the PdfArray. Do not deinit.
    /// Returns error if index is out of bounds.
    pub fn get(self: *PdfArray, index: usize) !*PdfObject {
        try self.ensureAllItemsResolved();
        if (index >= self.items.items.len) return error.IndexOutOfBounds;
        const item_ptr = &self.items.items[index];
        return switch (item_ptr.*) {
            .resolved => |*resolved_obj_ptr_in_item| resolved_obj_ptr_in_item,
            .unresolved => unreachable,
        };
    }

    pub fn len(self: *PdfArray) usize {
        return self.items.items.len;
    }

    /// Pops and returns the last PdfObject from the array.
    /// The caller takes ownership of the returned PdfObject and must deinit it.
    /// Returns `null` if the array is empty.
    pub fn pop(self: *PdfArray) !?PdfObject {
        try self.ensureAllItemsResolved();

        if (self.items.popOrNull()) |item_value| {
            return switch (item_value) {
                .resolved => |obj_value| obj_value,
                .unresolved => unreachable,
            };
        }
        return null;
    }

    pub const Iterator = struct {
        array_ptr: *PdfArray,
        next_index: usize,

        /// Returns a pointer to the next PdfObject.
        /// The pointer is to memory managed by the PdfArray. Do not deinit.
        /// Returns `null` if no more items. Errors can occur during resolution.
        pub fn next(it: *Iterator) !?*const PdfObject {
            if (it.next_index >= it.array_ptr.items.items.len) {
                return null;
            }
            const item_in_list_ptr = &it.array_ptr.items.items[it.next_index];
            it.next_index += 1;

            return switch (item_in_list_ptr.*) {
                .resolved => |*obj_val_ptr| obj_val_ptr,
                .unresolved => unreachable,
            };
        }
    };

    /// Returns an iterator over the resolved PdfObjects in the array.
    pub fn iterator(self: *PdfArray) !Iterator {
        try self.ensureAllItemsResolved();
        return .{ .array_ptr = self, .next_index = 0 };
    }

    /// Counts occurrences of a given PdfObject in the array.
    /// `item_to_count` is compared by value using `PdfObject.eql`.
    pub fn count(self: *PdfArray, item_to_count: PdfObject) !u32 {
        try self.ensureAllItemsResolved();
        var c: u32 = 0;

        for (self.items.items) |array_item_value| {
            switch (array_item_value) {
                .resolved => |resolved_obj_value| {
                    if (resolved_obj_value.eql(item_to_count)) {
                        c += 1;
                    }
                },
                .unresolved => unreachable,
            }
        }
        return c;
    }

    /// Clones the PdfArray. Resolved items are cloned. Unresolved items (PdfIndirect pointers) are copied.
    pub fn clone(self: *const PdfArray, new_allocator: Allocator) error{OutOfMemory}!*PdfArray {
        const new_array_ptr = try PdfArray.init(new_allocator, self.is_indirect_object);
        errdefer new_array_ptr.deinit();

        try new_array_ptr.items.ensureTotalCapacity(self.items.items.len);

        for (self.items.items) |original_item| {
            switch (original_item) {
                .unresolved => |indirect_ptr| {
                    try new_array_ptr.items.append(.{ .unresolved = indirect_ptr });
                },
                .resolved => |resolved_obj| {
                    try new_array_ptr.items.append(.{ .resolved = try resolved_obj.clone(new_allocator) });
                },
            }
        }
        new_array_ptr.all_items_resolved_attempted = self.all_items_resolved_attempted;
        return new_array_ptr;
    }

    /// Compares two PdfArray objects for equality.
    /// This method resolves all items in both arrays before comparison.
    /// Returns true if both arrays contain the same resolved PdfObjects in the same order.
    pub fn eql(self: *PdfArray, other: *PdfArray) !bool {
        try self.*.ensureAllItemsResolved();
        try other.*.ensureAllItemsResolved();

        if (self.items.items.len != other.items.items.len) return false;

        for (self.items.items, 0..) |self_item_val, i| {
            const other_item_val = other.items.items[i];

            const self_obj = switch (self_item_val) {
                .resolved => |resolved_obj| resolved_obj,
                .unresolved => unreachable,
            };

            const other_obj = switch (other_item_val) {
                .resolved => |resolved_obj| resolved_obj,
                .unresolved => unreachable,
            };

            if (!(try self_obj.eql(other_obj, self.allocator))) return false;
        }

        return true;
    }
};
