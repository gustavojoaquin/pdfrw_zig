const std = @import("std");
const pdfobject = @import("pdfobject.zig");
const errors = @import("errors.zig");

const PdfError = errors.PdfError;
const PdfObject = pdfobject.PdfObject;

/// A struct to represent the (object number, generation number) tuple.
/// This is what PdfIndirect *is* in Python's inheritance model.
pub const ObjectReference = struct {
    obj_num: u32,
    gen_num: u32,

    /// Initializes an ObjectReference.
    pub fn init(obj_num: u32, gen_num: u32) ObjectReference {
        return .{ .obj_num = obj_num, .gen_num = gen_num };
    }

    /// Formats the ObjectReference for printing (e.g., "(1, 0)").
    pub fn format(
        self: ObjectReference,
        _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("({d}, {d})", .{ self.obj_num, self.gen_num });
    }

    /// Checks if two ObjectReference instances are equal.
    pub fn eql(self: ObjectReference, other: ObjectReference) bool {
        return self.obj_num == other.obj_num and self.gen_num == other.gen_num;
    }
};

/// A placeholder for an object that hasn't been read in yet.
/// It contains the object reference (number, generation) and
/// a mechanism for lazy loading the actual object.
pub const PdfIndirect = struct {
    /// The object number and generation number.
    /// This uniquely identifies the indirect object within the PDF file.
    ref: ObjectReference,

    /// The actual PDF object value, if loaded.
    /// This is `null` if the object has not yet been loaded from the file.
    value: ?*PdfObject,

    /// A function pointer to load the actual object from its reference.
    /// This function takes a pointer to the `PdfIndirect` instance itself
    /// (to access its `ref` field) and an allocator.
    /// It should return a pointer to the loaded object, or an error.
    loader: *const fn (*PdfIndirect, allocator: std.mem.Allocator) PdfError!?*PdfObject,

    /// Initializes a PdfIndirect object.
    ///
    /// `obj_num` and `gen_num` identify the indirect object.
    /// `loader_fn` is the function that will be called to actually load the object
    /// when `real_value` is first accessed. This function will typically be part
    /// of your PDF file parsing context.
    ///
    /// Usage:
    /// `const indirect_ref = PdfIndirect.init(1, 0, my_pdf_loader_function);`
    pub fn init(
        obj_num: u32,
        gen_num: u32,
        loader_fn: *const fn (*PdfIndirect, allocator: std.mem.Allocator) PdfError!?*PdfObject,
    ) PdfIndirect {
        return .{
            .ref = ObjectReference.init(obj_num, gen_num),
            .value = null, // Initially not loaded
            .loader = loader_fn,
        };
    }

    /// Returns a pointer to the real value of the PDF object, loading it if necessary.
    /// The returned pointer points to the `PdfObject` stored within this `PdfIndirect` instance.
    /// The caller should typically clone this object if it needs to own it or modify it,
    /// as the `PdfIndirect` instance might be shared or its cached value could change.
    pub fn real_value(self: *PdfIndirect, allocator: std.mem.Allocator) PdfError!?*PdfObject { // Return type includes `?`
        if (self.value == null) {
            const loaded_obj_opt = try self.loader(self, allocator);
            if (loaded_obj_opt) |loaded_obj| {
                self.value = loaded_obj;
            } else {
                self.value = null;
                return null;
            }
        }

        if (self.value) |val_ptr| {
            return val_ptr;
        } else {
            return null;
        }
    }

    pub fn deinit(self: *PdfIndirect, allocator: std.mem.Allocator) void {
        if (self.value) |v| v.deinit(allocator);
    }

    /// Checks if two PdfIndirect instances are equal.
    /// Equality is based solely on their `ObjectReference`.
    pub fn eql(self: PdfIndirect, other: PdfIndirect) bool {
        return self.ref.eql(other.ref);
    }
};
