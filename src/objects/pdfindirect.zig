const std = @import("std");

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
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt; // Unused for simple tuple formatting
        _ = options; // Unused for simple tuple formatting
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
    value: ?*anyopaque,

    /// A function pointer to load the actual object from its reference.
    /// This function takes a pointer to the `PdfIndirect` instance itself
    /// (to access its `ref` field) and an allocator.
    /// It should return a pointer to the loaded object, or an error.
    loader: fn (*PdfIndirect, allocator: std.mem.Allocator) anyerror!*anyopaque,

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
        loader_fn: fn (*PdfIndirect, allocator: std.mem.Allocator) anyerror!*anyopaque,
    ) PdfIndirect {
        return .{
            .ref = ObjectReference.init(obj_num, gen_num),
            .value = null, // Initially not loaded
            .loader = loader_fn,
        };
    }

    /// Returns the real value of the PDF object, loading it if necessary.
    ///
    /// This function returns a pointer to the loaded object. The caller
    /// is responsible for casting this `*anyopaque` pointer to the correct
    /// PDF object type (e.g., `*PdfDict`, `*PdfArray`, etc.) based on context.
    ///
    /// The `allocator` is passed to the internal `loader` function, in case
    /// the loaded object needs to be dynamically allocated.
    ///
    /// This function is fallible (`anyerror!`) because the `loader` might fail.
    ///
    /// Usage:
    /// `const loaded_dict = @ptrCast(*PdfDict, try indirect_ref.real_value(my_allocator));`
    pub fn real_value(self: *PdfIndirect, allocator: std.mem.Allocator) anyerror!*anyopaque {
        if (self.value == null) {
            // If the object hasn't been loaded yet, call the provided loader function.
            // The loader function performs the actual parsing/retrieval from the file.
            self.value = try self.loader(self, allocator);
        }
        return self.value.?; // We can safely unwrap now as it's guaranteed not null.
    }

    /// Checks if two PdfIndirect instances are equal.
    /// Equality is based solely on their `ObjectReference`.
    pub fn eql(self: PdfIndirect, other: PdfIndirect) bool {
        return self.ref.eql(other.ref);
    }
};
