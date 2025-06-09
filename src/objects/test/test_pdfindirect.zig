const std = @import("std");
const pdfindirect = @import("../pdfindirect.zig");
const pdfobject = @import("../pdfobject.zig");
const pdfstring = @import("../pdfstring.zig");
const errors = @import("../errors.zig");

const PdfString = pdfstring.PdfString;
const PdfObject = pdfobject.PdfObject;
const ObjectReference = pdfindirect.ObjectReference;
const PdfIndirect = pdfindirect.PdfIndirect;

var mock_loader_call_count: u32 = 0;
var mock_loader_should_fail: bool = false;

fn mockPdfLoader(
    _: *PdfIndirect,
    allocator: std.mem.Allocator,
) errors.PdfError!?*PdfObject {
    mock_loader_call_count += 1;
    if (mock_loader_should_fail) {
        return errors.PdfError.ObjectNotFound;
    }

    const mock_obj = try allocator.create(PdfObject);
    const pdf_string = try PdfString.fromUnicode(allocator, "mock_resolved_value", .auto, .auto);
    mock_obj.* = .{ .String = pdf_string };

    return mock_obj;
}

fn resetMockLoaderFlags() void {
    mock_loader_call_count = 0;
    mock_loader_should_fail = false;
}

test "PdfIndirect.init" {
    resetMockLoaderFlags();
    var indirect = PdfIndirect.init(10, 5, mockPdfLoader);
    defer indirect.deinit(std.testing.allocator);

    try std.testing.expectEqual(indirect.ref.obj_num, 10);
    try std.testing.expectEqual(indirect.ref.gen_num, 5);
    try std.testing.expect(indirect.value == null);
}

test "PdfIndirect.real_value - first call loads object" {
    const allocator = std.testing.allocator;
    resetMockLoaderFlags();

    var indirect = PdfIndirect.init(1, 0, mockPdfLoader);
    defer indirect.deinit(allocator);

    try std.testing.expect(indirect.value == null);

    const loaded_ptr: *PdfObject = (try indirect.real_value(allocator)).?;

    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expect(indirect.value != null);
    try std.testing.expect(loaded_ptr == indirect.value.?);

    try std.testing.expect(loaded_ptr.*.getTag() == .String);
    const unicode_val = try loaded_ptr.String.toUnicode(allocator);
    defer allocator.free(unicode_val);
    try std.testing.expectEqualStrings(unicode_val, "mock_resolved_value");
}

// test "PdfIndirect.real_value - subsequent calls don't reload" {
//     const allocator = std.testing.allocator;
//     resetMockLoaderFlags();
//
//     var indirect = PdfIndirect.init(2, 0, mockPdfLoader);
//     defer indirect.deinit(allocator);
//
//     const first_loaded_ptr = (try indirect.real_value(allocator)).?;
//     try std.testing.expectEqual(mock_loader_call_count, 1);
//     try std.testing.expect(indirect.value != null);
//     try std.testing.expect(first_loaded_ptr.*.tag() == .String);
//
//     const second_loaded_ptr = (try indirect.real_value(allocator)).?;
//
//     try std.testing.expectEqual(mock_loader_call_count, 1);
//     try std.testing.expect(second_loaded_ptr == first_loaded_ptr);
//     try std.testing.expect(second_loaded_ptr == indirect.value.?);
//
//     try std.testing.expect(second_loaded_ptr.*.tag() == .String);
//     const unicode_val = try second_loaded_ptr.String.toUnicode(allocator);
//     defer allocator.free(unicode_val);
//     try std.testing.expectEqualStrings(unicode_val, "mock_resolved_value");
// }
//
// test "PdfIndirect.real_value - loader error propagation" {
//     const allocator = std.testing.allocator;
//     resetMockLoaderFlags();
//     mock_loader_should_fail = true;
//     var indirect = PdfIndirect.init(3, 0, mockPdfLoader);
//     defer indirect.deinit(allocator);
//
//     const result = indirect.real_value(allocator);
//
//     try std.testing.expectEqual(mock_loader_call_count, 1);
//     // FIX 4: Expect the error we now return from the mock loader.
//     try std.testing.expectError(errors.PdfError.ObjectNotFound, result);
//     try std.testing.expect(indirect.value == null);
// }
//
// test "PdfIndirect.eql" {
//     const allocator = std.testing.allocator;
//     resetMockLoaderFlags();
//
//     // The init calls are now valid.
//     const indirect1_0_a = PdfIndirect.init(1, 0, mockPdfLoader);
//     const indirect1_0_b = PdfIndirect.init(1, 0, mockPdfLoader);
//     const indirect2_0 = PdfIndirect.init(2, 0, mockPdfLoader);
//     const indirect1_1 = PdfIndirect.init(1, 1, mockPdfLoader);
//
//     var indirect1_0_loaded_a = PdfIndirect.init(1, 0, mockPdfLoader);
//     defer indirect1_0_loaded_a.deinit(allocator);
//     _ = try indirect1_0_loaded_a.real_value(allocator);
//
//     var indirect1_0_loaded_b = PdfIndirect.init(1, 0, mockPdfLoader);
//     defer indirect1_0_loaded_b.deinit(allocator);
//     _ = try indirect1_0_loaded_b.real_value(allocator);
//
//     try std.testing.expect(indirect1_0_a.eql(indirect1_0_b));
//     try std.testing.expect(indirect1_0_a.eql(indirect1_0_loaded_a));
//     try std.testing.expect(indirect1_0_loaded_a.eql(indirect1_0_loaded_b));
//     try std.testing.expect(indirect1_0_a.eql(indirect1_0_a));
//
//     try std.testing.expect(!indirect1_0_a.eql(indirect2_0));
//     try std.testing.expect(!indirect1_0_a.eql(indirect1_1));
//     try std.testing.expect(!indirect2_0.eql(indirect1_1));
// }
