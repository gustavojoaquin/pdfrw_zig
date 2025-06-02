const std = @import("std");
const allocator = std.testing.allocator;
const pdfarray = @import("../pdfarray.zig");
const pdfobject = @import("../pdfobject.zig");
const pdfindirect = @import("../pdfindirect.zig");

const PdfArray = pdfarray.PdfArray;
const PdfObject = pdfobject.PdfObject;
const PdfIndirect = pdfindirect.PdfIndirect;

var mock_loader_call_count: u32 = 0;
var mock_loader_should_fail: bool = false;
var mock_loader_return_null: bool = false;
var mock_obj_store: [3]*PdfObject = undefined;
var mock_obj_idx: usize = 0;

fn mockIndirectLoader(
    _: *pdfindirect.PdfIndirect, // Assuming PdfIndirect is from pdfindirect.zig
    _: std.mem.Allocator,
) anyerror!?*anyopaque { // MODIFIED: from !*anyopaque to !?*anyopaque
    mock_loader_call_count += 1;

    if (mock_loader_should_fail) {
        return error.TestLoaderFailed;
    }
    if (mock_loader_return_null) {
        mock_loader_return_null = false;
        return null; // This is now valid with !?*anyopaque
    }
    const current_mock_obj_ptr = mock_obj_store[mock_obj_idx];
    mock_obj_idx = (mock_obj_idx + 1) % mock_obj_store.len;
    const current_mock_obj_cast: *anyopaque = @ptrCast(current_mock_obj_ptr);
    return current_mock_obj_cast;
}
fn resetMockLoader() !void {
    mock_loader_call_count = 0;
    mock_loader_should_fail = false;
    mock_loader_return_null = false;
    mock_obj_store[0] = try PdfObject.init(allocator, "val0");
    mock_obj_store[1] = try PdfObject.init(allocator, "val1");
    mock_obj_store[2] = try PdfObject.init(allocator, "val2");
    mock_obj_idx = 0;
}

test "PdfArray.init and deinit" {
    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    try std.testing.expectEqual(arr.len(), 0);
    try std.testing.expectEqual(arr.indirect, false);
    try std.testing.expectEqual(arr.has_been_resolved, false);
}

test "PdfArray.append and get basic" {
    try resetMockLoader();

    // MODIFIED: Removed 'try'
    var p_indirect1_store = PdfIndirect.init(1, 0, mockIndirectLoader);
    var p_indirect2_store = PdfIndirect.init(2, 0, mockIndirectLoader);

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    try arr.appendIndirect(&p_indirect1_store);
    const expected_direct = try PdfObject.init(allocator, "direct");
    try arr.appendObject(expected_direct.*);
    try arr.appendIndirect(&p_indirect2_store);

    try std.testing.expectEqual(arr.len(), 3);
    try std.testing.expectEqual(mock_loader_call_count, 0);

    const item0 = try arr.get(0);
    // It seems mock_obj_store[0] and mock_obj_store[1] are used here.
    // For arr.get(0) to resolve, it might resolve all unresolved items up to that point or all items.
    // The mock_loader_call_count check later (2) suggests two items were resolved by the first get().
    // This would happen if ensureResolved resolves the whole array.
    try std.testing.expect(item0.eql((try PdfObject.init(allocator, "val0")).*)); // Assuming PdfObject.init can error
    try std.testing.expectEqual(mock_loader_call_count, 2); // Check your logic here, if ensureResolved resolves all, it might be more.
    // If ensureResolved in PdfArray.zig resolves items one-by-one on demand, this might be right.
    // Your PdfArray.ensureResolved resolves all items in a loop.
    // So if p_indirect1_store and p_indirect2_store were unresolved, this would be 2 calls.
    try std.testing.expect(arr.has_been_resolved);

    const item1 = try arr.get(1);
    try std.testing.expect(item1.eql((try PdfObject.init(allocator, "direct")).*));
    try std.testing.expectEqual(mock_loader_call_count, 2); // No new calls if already resolved

    const item2 = try arr.get(2);
    try std.testing.expect(item2.eql((try PdfObject.init(allocator, "val1")).*));
    try std.testing.expectEqual(mock_loader_call_count, 2); // No new calls
}
