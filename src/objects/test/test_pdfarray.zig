const std = @import("std");
const allocator = std.testing.allocator;
const pdfarray = @import("../pdfarray.zig");
const pdfobject = @import("../pdfobject.zig");
const pdfindirect = @import("../pdfindirect.zig");

const PdfArray = pdfarray.PdfArray;
const PdfObject = pdfobject.PdfObject;
const PdfIndirect = pdfindirect.PdfIndirect;
const PdfArrayItem = pdfarray.PdfArrayItem;

var mock_loader_call_count: u32 = 0;
var mock_loader_should_fail: bool = false;
var mock_loader_return_null: bool = false;
var mock_loader_return_error = false;

var mock_obj_store: [3]?*PdfObject = undefined;
var mock_obj_idx: usize = 0;

fn mockIndirectLoader(
    _: *pdfindirect.PdfIndirect,
    allocator_l: std.mem.Allocator,
) anyerror!?*PdfObject {
    mock_loader_call_count += 1;

    if (mock_loader_should_fail) {
        return error.TestLoaderFailed;
    }
    if (mock_loader_return_error) {
        return error.TestLoaderFailed;
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
    return try PdfObject.init(allocator_l, obj_val);
}
fn resetMockLoaderFlags() void {
    mock_loader_call_count = 0;
    mock_loader_return_error = false;
    mock_loader_return_null = false;
    mock_obj_idx = 0;
}

test "PdfArray.init and deinit" {
    resetMockLoaderFlags();
    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    try std.testing.expectEqual(arr.len(), 0);
    try std.testing.expectEqual(arr.indirect, false);
    try std.testing.expectEqual(arr.has_been_resolved, false);
}

test "PdfArray.appendIndirect and get with resolution" {
    resetMockLoaderFlags();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader);

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    try arr.appendIndirect(&indirect1);
    try arr.appendIndirect(&indirect2);

    try std.testing.expectEqual(arr.len(), 2);
    try std.testing.expectEqual(mock_loader_call_count, 0);
    try std.testing.expectEqual(arr.has_been_resolved, false);

    const item0 = try arr.get(0);
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expectEqual(arr.has_been_resolved, true);

    try std.testing.expectEqualStrings(item0.value, "val0");

    const item1 = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expectEqualStrings(item1.value, "val1");

    _ = try arr.get(0);
    _ = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 2);
}

test "PdfArray.appendObject and get" {
    resetMockLoaderFlags();

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    const obj1 = try PdfObject.init(allocator, "direct1");
    const obj2 = try PdfObject.init(allocator, "direct2");

    try arr.appendObject(obj1);
    try arr.appendObject(obj2);

    try std.testing.expectEqual(arr.len(), 2);
    try std.testing.expectEqual(arr.has_been_resolved, false);

    const item0 = try arr.get(0);
    try std.testing.expectEqual(mock_loader_call_count, 0);
    try std.testing.expectEqual(arr.has_been_resolved, true);
    try std.testing.expect(item0.eql(obj1));

    const item1 = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 0);
    try std.testing.expect(item1.eql(obj2));
}

test "PdfArray.extend" {
    resetMockLoaderFlags();

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    const obj1 = try PdfObject.init(allocator, "extended_direct1");

    const items_to_extend: []const PdfArrayItem = &[_]PdfArrayItem{
        .{ .unresolved = &indirect1 },
        .{ .resolved = obj1 },
    };

    try arr.extend(items_to_extend);

    try std.testing.expectEqual(arr.len(), 2);
    try std.testing.expectEqual(arr.has_been_resolved, false);

    const item0 = try arr.get(0);
    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expectEqual(arr.has_been_resolved, true);
    try std.testing.expectEqualStrings(item0.value, "val0");

    const item1 = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expect(item1.eql(obj1));
}

test "PdfArray.pop" {
    resetMockLoaderFlags();

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader);
    const obj1 = try PdfObject.init(allocator, "pop_direct1");

    try arr.appendIndirect(&indirect1);
    try arr.appendObject(obj1);
    try arr.appendIndirect(&indirect2);

    try std.testing.expectEqual(arr.len(), 3);
    try std.testing.expectEqual(arr.has_been_resolved, false);

    const popped_item = try arr.pop();
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expectEqual(arr.has_been_resolved, true);

    try std.testing.expect(popped_item != null);
    const popped_obj = popped_item.?;
    try std.testing.expectEqualStrings(popped_obj.value, "val1");
    defer popped_obj.deinit(allocator);

    try std.testing.expectEqual(arr.len(), 2);

    const popped_item2 = try arr.pop();
    try std.testing.expect(popped_item2 != null);
    const popped_obj2 = popped_item2.?;
    try std.testing.expect(popped_obj2.eql(obj1));
    defer popped_obj2.deinit(allocator);

    try std.testing.expectEqual(arr.len(), 1);

    const popped_item3 = try arr.pop();
    try std.testing.expect(popped_item3 != null);
    const popped_obj3 = popped_item3.?;
    try std.testing.expectEqualStrings(popped_obj3.value, "val0");
    defer popped_obj3.deinit(allocator);

    try std.testing.expectEqual(arr.len(), 0);

    const popped_item4 = try arr.pop();
    try std.testing.expect(popped_item4 == null);
    try std.testing.expectEqual(arr.len(), 0);
}

test "PdfArray.iterator" {
    resetMockLoaderFlags();

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    const obj1 = try PdfObject.init(allocator, "iter_direct1");
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader);

    try arr.appendIndirect(&indirect1);
    try arr.appendObject(obj1);
    try arr.appendIndirect(&indirect2);

    try std.testing.expectEqual(arr.has_been_resolved, false);

    var iter = try arr.iterator();
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expectEqual(arr.has_been_resolved, true);

    var count: usize = 0;
    while (try iter.next()) |item_ptr| {
        switch (count) {
            0 => try std.testing.expectEqualStrings(item_ptr.value, "val0"),
            1 => try std.testing.expect(item_ptr.eql(obj1)), // direct object
            2 => try std.testing.expectEqualStrings(item_ptr.value, "val1"),
            else => unreachable,
        }
        count += 1;
    }
    try std.testing.expectEqual(count, 3);
    try std.testing.expectEqual(mock_loader_call_count, 2);
}

test "PdfArray.count" {
    resetMockLoaderFlags();

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader); // Resolves to val0
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader); // Resolves to val1
    var indirect3 = PdfIndirect.init(3, 0, mockIndirectLoader); // Resolves to val2
    var indirect4 = PdfIndirect.init(4, 0, mockIndirectLoader); // Resolves to val0 again (due to index cycle)

    const obj0 = try PdfObject.init(allocator, "val0");
    const obj_other = try PdfObject.init(allocator, "other");

    try arr.appendIndirect(&indirect1);
    try arr.appendObject(obj_other);
    try arr.appendIndirect(&indirect2);
    try arr.appendObject(obj0);
    try arr.appendIndirect(&indirect3);
    try arr.appendIndirect(&indirect4);

    try std.testing.expectEqual(arr.len(), 6);
    try std.testing.expectEqual(arr.has_been_resolved, false);

    const count_val0 = try arr.count(obj0);
    try std.testing.expectEqual(mock_loader_call_count, 4);
    try std.testing.expectEqual(arr.has_been_resolved, true);
    try std.testing.expectEqual(count_val0, 3);

    const count_other = try arr.count(obj_other);
    try std.testing.expectEqual(mock_loader_call_count, 4);
    try std.testing.expectEqual(count_other, 1);

    const obj1_for_count = try PdfObject.init(allocator, "val1");
    defer obj1_for_count.deinit(allocator);
    const count_val1 = try arr.count(obj1_for_count);
    try std.testing.expectEqual(mock_loader_call_count, 4);
    try std.testing.expectEqual(count_val1, 1);

    const obj_missing = try PdfObject.init(allocator, "missing");
    defer obj_missing.deinit(allocator);
    const count_missing = try arr.count(obj_missing);
    try std.testing.expectEqual(mock_loader_call_count, 4);
    try std.testing.expectEqual(count_missing, 0);
}

test "PdfArray.ensureResolved with loader error" {
    resetMockLoaderFlags();
    mock_loader_return_error = true;

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    try arr.appendIndirect(&indirect1);

    try std.testing.expectEqual(arr.has_been_resolved, false);

    const item0 = try arr.get(0);

    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expectEqual(arr.has_been_resolved, true);
    try std.testing.expectEqualStrings(item0.value, "null");
    try std.testing.expectEqual(item0.indirect, false);
}
test "PdfArray.ensureResolved with loader returning null" {
    resetMockLoaderFlags();
    mock_loader_return_null = true;

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader);

    try arr.appendIndirect(&indirect1);
    try arr.appendIndirect(&indirect2);

    try std.testing.expectEqual(arr.has_been_resolved, false);

    const item0 = try arr.get(0);
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expectEqual(arr.has_been_resolved, true);

    try std.testing.expectEqualStrings(item0.value, "null");
    try std.testing.expectEqual(item0.indirect, false);

    const item1 = try arr.get(1);
    try std.testing.expectEqualStrings(item1.value, "null");
}
