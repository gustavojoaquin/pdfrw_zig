const std = @import("std");
const pdfindirect = @import("../pdfindirect.zig");
const pdfobject = @import("../pdfobject.zig");

const PdfObject = pdfobject.PdfObject;
const ObjectReference = pdfindirect.ObjectReference;
const PdfIndirect = pdfindirect.PdfIndirect;

pub const MyTestError = error{
    LoaderFailed,
};

var mock_loader_call_count: u32 = 0;
var mock_loader_should_fail: bool = false;

fn mockPdfLoader(
    _: *PdfIndirect,
    allocator: std.mem.Allocator,
) anyerror!?*PdfObject {
    mock_loader_call_count += 1;
    if (mock_loader_should_fail) {
        return MyTestError.LoaderFailed;
    }
    const mock_obj = try PdfObject.init(allocator, "mock_resolved_value");
    return mock_obj;
}

fn resetMockLoaderFlags() void {
    mock_loader_call_count = 0;
    mock_loader_should_fail = false;
}

test "ObjectReference.init" {
    resetMockLoaderFlags();
    const ref1 = ObjectReference.init(1, 0);
    try std.testing.expectEqual(ref1.obj_num, 1);
    try std.testing.expectEqual(ref1.gen_num, 0);

    const ref2 = ObjectReference.init(12345, 6789);
    try std.testing.expectEqual(ref2.obj_num, 12345);
    try std.testing.expectEqual(ref2.gen_num, 6789);
}

test "ObjectReference.format" {
    resetMockLoaderFlags();
    var buffer: [32]u8 = undefined;
    const ref1 = ObjectReference.init(1, 0);
    const s1 = try std.fmt.bufPrint(&buffer, "{}", .{ref1});
    try std.testing.expectEqualStrings(s1, "(1, 0)");

    const ref2 = ObjectReference.init(999, 123);
    const s2 = try std.fmt.bufPrint(&buffer, "{}", .{ref2});
    try std.testing.expectEqualStrings(s2, "(999, 123)");
}

test "ObjectReference.eql" {
    resetMockLoaderFlags();
    const ref1_0_a = ObjectReference.init(1, 0);
    const ref1_0_b = ObjectReference.init(1, 0);
    const ref2_0 = ObjectReference.init(2, 0);
    const ref1_1 = ObjectReference.init(1, 1);

    try std.testing.expect(ref1_0_a.eql(ref1_0_b));
    try std.testing.expect(ref1_0_a.eql(ref1_0_a));
    try std.testing.expect(!ref1_0_a.eql(ref2_0));

    try std.testing.expect(!ref1_0_a.eql(ref1_1));

    try std.testing.expect(!ref2_0.eql(ref1_1));
}

test "PdfIndirect.init" {
    resetMockLoaderFlags();
    const indirect = PdfIndirect.init(10, 5, mockPdfLoader);
    // No PdfObject is allocated by the loader during `init`, so no defer needed.

    try std.testing.expectEqual(indirect.ref.obj_num, 10);
    try std.testing.expectEqual(indirect.ref.gen_num, 5);
    try std.testing.expect(indirect.value == null); // Should be initially null
}

test "PdfIndirect.real_value - first call loads object" {
    const allocator = std.testing.allocator;
    resetMockLoaderFlags();

    var indirect = PdfIndirect.init(1, 0, mockPdfLoader);
    defer {
        if (indirect.value) |obj_ptr| {
            obj_ptr.deinit(allocator);
        }
    }

    try std.testing.expect(indirect.value == null);

    const loaded_ptr: *PdfObject = (try indirect.real_value(allocator)).?;

    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expect(indirect.value != null);
    try std.testing.expect(loaded_ptr == indirect.value.?);
    try std.testing.expectEqualStrings(loaded_ptr.value, "mock_resolved_value");
}

test "PdfIndirect.real_value - subsequent calls don't reload" {
    const allocator = std.testing.allocator;
    resetMockLoaderFlags();

    var indirect = PdfIndirect.init(2, 0, mockPdfLoader);
    defer {
        if (indirect.value) |obj_ptr| {
            obj_ptr.deinit(allocator);
        }
    }

    const first_loaded_ptr = (try indirect.real_value(allocator)).?;
    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expect(indirect.value != null);
    try std.testing.expectEqualStrings(first_loaded_ptr.value, "mock_resolved_value");

    const second_loaded_ptr = (try indirect.real_value(allocator)).?;

    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expect(second_loaded_ptr == first_loaded_ptr);
    try std.testing.expect(second_loaded_ptr == indirect.value.?);
    try std.testing.expectEqualStrings(second_loaded_ptr.value, "mock_resolved_value");
}

test "PdfIndirect.real_value - loader error propagation" {
    const allocator = std.testing.allocator;
    resetMockLoaderFlags();
    mock_loader_should_fail = true;
    var indirect = PdfIndirect.init(3, 0, mockPdfLoader);

    const result = indirect.real_value(allocator);

    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expectError(MyTestError.LoaderFailed, result);
    try std.testing.expect(indirect.value == null);
}

test "PdfIndirect.eql" {
    const allocator = std.testing.allocator;
    resetMockLoaderFlags();

    const indirect1_0_a = PdfIndirect.init(1, 0, mockPdfLoader);
    const indirect1_0_b = PdfIndirect.init(1, 0, mockPdfLoader);
    const indirect2_0 = PdfIndirect.init(2, 0, mockPdfLoader);
    const indirect1_1 = PdfIndirect.init(1, 1, mockPdfLoader);

    var indirect1_0_loaded_a = PdfIndirect.init(1, 0, mockPdfLoader);
    defer {
        if (indirect1_0_loaded_a.value) |obj_ptr| {
            obj_ptr.deinit(allocator);
        }
    }
    _ = try indirect1_0_loaded_a.real_value(allocator);
    var indirect1_0_loaded_b = PdfIndirect.init(1, 0, mockPdfLoader);
    defer {
        if (indirect1_0_loaded_b.value) |obj_ptr| {
            obj_ptr.deinit(allocator);
        }
    }
    _ = try indirect1_0_loaded_b.real_value(allocator);

    try std.testing.expect(indirect1_0_a.eql(indirect1_0_b));
    try std.testing.expect(indirect1_0_a.eql(indirect1_0_loaded_a));
    try std.testing.expect(indirect1_0_loaded_a.eql(indirect1_0_loaded_b));
    try std.testing.expect(indirect1_0_a.eql(indirect1_0_a));

    try std.testing.expect(!indirect1_0_a.eql(indirect2_0));
    try std.testing.expect(!indirect1_0_a.eql(indirect1_1));
    try std.testing.expect(!indirect2_0.eql(indirect1_1));
}

