const std = @import("std");
const pdfindirect = @import("../pdfindirect.zig");
const ObjectReference = pdfindirect.ObjectReference;
const PdfIndirect = pdfindirect.PdfIndirect;

pub const MyTestError = error{
    LoaderFailed,
};

// Global state for our mock loader function
var mock_loader_call_count: u32 = 0;
var mock_loader_should_fail: bool = false;
var mock_loaded_dummy_obj: u8 = 0xDE;
fn mockPdfLoader(
    _: *PdfIndirect,
    _: std.mem.Allocator,
) anyerror!*anyopaque {
    mock_loader_call_count += 1;
    if (mock_loader_should_fail) {
        return MyTestError.LoaderFailed;
    }
    const result: *anyopaque = @ptrCast(&mock_loaded_dummy_obj);
    return result;
}

test "ObjectReference.init" {
    const ref1 = ObjectReference.init(1, 0);
    try std.testing.expectEqual(ref1.obj_num, 1);
    try std.testing.expectEqual(ref1.gen_num, 0);

    const ref2 = ObjectReference.init(12345, 6789);
    try std.testing.expectEqual(ref2.obj_num, 12345);
    try std.testing.expectEqual(ref2.gen_num, 6789);
}

test "ObjectReference.format" {
    var buffer: [32]u8 = undefined;
    const ref1 = ObjectReference.init(1, 0);
    const s1 = try std.fmt.bufPrint(&buffer, "{}", .{ref1});
    try std.testing.expectEqualStrings(s1, "(1, 0)");

    const ref2 = ObjectReference.init(999, 123);
    const s2 = try std.fmt.bufPrint(&buffer, "{}", .{ref2});
    try std.testing.expectEqualStrings(s2, "(999, 123)");
}

test "ObjectReference.eql" {
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
    mock_loader_call_count = 0;
    mock_loader_should_fail = false;

    const indirect = PdfIndirect.init(10, 5, mockPdfLoader);

    try std.testing.expectEqual(indirect.ref.obj_num, 10);
    try std.testing.expectEqual(indirect.ref.gen_num, 5);
    try std.testing.expect(indirect.value == null); // Should be initially null
}

test "PdfIndirect.real_value - first call loads object" {
    const allocator = std.testing.allocator;
    mock_loader_call_count = 0;
    mock_loader_should_fail = false;

    var indirect = PdfIndirect.init(1, 0, mockPdfLoader);

    try std.testing.expect(indirect.value == null);

    const loaded_ptr = try indirect.real_value(allocator);

    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expect(indirect.value != null);
    const expected_ptr: *anyopaque = @ptrCast(&mock_loaded_dummy_obj);
    try std.testing.expect(loaded_ptr == expected_ptr);
    const expected_u8: *u8 = @ptrCast(loaded_ptr);
    try std.testing.expectEqual(expected_u8.*, mock_loaded_dummy_obj);
}

test "PdfIndirect.real_value - subsequent calls don't reload" {
    const allocator = std.testing.allocator;
    mock_loader_call_count = 0;
    mock_loader_should_fail = false;

    var indirect = PdfIndirect.init(2, 0, mockPdfLoader);

    const first_loaded_ptr = try indirect.real_value(allocator);
    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expect(indirect.value != null);

    const second_loaded_ptr = try indirect.real_value(allocator);

    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expect(second_loaded_ptr == first_loaded_ptr);
    try std.testing.expect(second_loaded_ptr == indirect.value.?);
}

test "PdfIndirect.real_value - loader error propagation" {
    const allocator = std.testing.allocator;
    mock_loader_call_count = 0;
    mock_loader_should_fail = true;
    var indirect = PdfIndirect.init(3, 0, mockPdfLoader);

    const result = indirect.real_value(allocator);

    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expectError(MyTestError.LoaderFailed, result);
    try std.testing.expect(indirect.value == null);
}

test "PdfIndirect.eql" {
    const allocator = std.testing.allocator;
    mock_loader_call_count = 0;
    mock_loader_should_fail = false;

    // Create instances with varying loader/value states to ensure they don't affect equality
    const indirect1_0_a = PdfIndirect.init(1, 0, mockPdfLoader);
    const indirect1_0_b = PdfIndirect.init(1, 0, mockPdfLoader);
    const indirect2_0 = PdfIndirect.init(2, 0, mockPdfLoader);
    const indirect1_1 = PdfIndirect.init(1, 1, mockPdfLoader);
    var indirect1_0_loaded_a = PdfIndirect.init(1, 0, mockPdfLoader);
    _ = try indirect1_0_loaded_a.real_value(allocator);

    var indirect1_0_loaded_b = PdfIndirect.init(1, 0, mockPdfLoader);
    _ = try indirect1_0_loaded_b.real_value(allocator);

    // Test equality based on reference
    try std.testing.expect(indirect1_0_a.eql(indirect1_0_b));
    try std.testing.expect(indirect1_0_a.eql(indirect1_0_loaded_a));
    try std.testing.expect(indirect1_0_loaded_a.eql(indirect1_0_loaded_b));
    try std.testing.expect(indirect1_0_a.eql(indirect1_0_a));

    try std.testing.expect(!indirect1_0_a.eql(indirect2_0));

    try std.testing.expect(!indirect1_0_a.eql(indirect1_1));

    try std.testing.expect(!indirect2_0.eql(indirect1_1));
}
