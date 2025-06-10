const std = @import("std");
const allocator = std.testing.allocator;
const pdfarray = @import("../pdfarray.zig");
const pdfobject = @import("../pdfobject.zig");
const pdfindirect = @import("../pdfindirect.zig");
const errors = @import("../errors.zig");

const PdfArray = pdfarray.PdfArray;
const PdfObject = pdfobject.PdfObject;
const PdfIndirect = pdfindirect.PdfIndirect;
const PdfArrayItem = pdfarray.PdfArrayItem;
const PdfError = errors.PdfError;

var mock_loader_call_count: u32 = 0;
var mock_loader_should_fail: bool = false;
var mock_loader_return_null: bool = false;

var mock_obj_idx: usize = 0;

var mock_obj_store_list: std.ArrayList(*PdfObject) = undefined;

fn setupMockLoader() !void {
    mock_obj_store_list = std.ArrayList(*PdfObject).init(allocator);
}

fn teardownMockLoader() void {
    if (mock_obj_store_list.items.len > 0) {
        for (mock_obj_store_list.items) |obj_ptr| {
            obj_ptr.deinit(allocator);
        }
        mock_obj_store_list.deinit();
    }
}

fn mockIndirectLoader(
    _: *pdfindirect.PdfIndirect,
    allocator_l: std.mem.Allocator,
) PdfError!?*PdfObject {
    mock_loader_call_count += 1;

    if (mock_loader_should_fail) {
        return error.ObjectNotFound;
    }
    if (mock_loader_return_null) {
        return null;
    }

    const obj_val = switch (mock_obj_idx) {
        0 => "val0",
        1 => "val1",
        2 => "val2",
        else => unreachable,
    };
    mock_obj_idx = (mock_obj_idx + 1) % 3;

    var obj = try PdfObject.initString(obj_val, allocator_l);
    errdefer obj.deinit(allocator_l);

    try mock_obj_store_list.append(&obj);
    return &obj;
}

fn resetMockLoaderFlags() void {
    mock_loader_call_count = 0;
    mock_loader_should_fail = false;
    mock_loader_return_null = false;
    mock_obj_idx = 0;
}

test "PdfArray.init and deinit" {
    resetMockLoaderFlags();
    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    try std.testing.expectEqual(arr.len(), 0);
    try std.testing.expectEqual(arr.is_indirect_object, false);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);
}

test "PdfArray.appendIndirect and get with resolution" {
    resetMockLoaderFlags();
    try setupMockLoader();
    defer teardownMockLoader();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader);

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    try arr.appendIndirect(&indirect1);
    try arr.appendIndirect(&indirect2);

    try std.testing.expectEqual(arr.len(), 2);
    try std.testing.expectEqual(mock_loader_call_count, 0);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);

    const item0_ptr = try arr.get(0);
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, true);

    try std.testing.expect(item0_ptr.getTag() == .String);
    try std.testing.expectEqualStrings(try item0_ptr.String.toUnicode(allocator), "val0");
    const item1_ptr = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expect(item1_ptr.getTag() == .String);
    try std.testing.expectEqualStrings(try item1_ptr.String.toUnicode(allocator), "val1");

    _ = try arr.get(0);
    _ = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 2);
}
