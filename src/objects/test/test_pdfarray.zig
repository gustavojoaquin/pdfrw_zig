const std = @import("std");
const allocator = std.testing.allocator;
const pdfarray = @import("../pdfarray.zig");
const pdfobject = @import("../pdfobject.zig");
const pdfindirect = @import("../pdfindirect.zig");
const pdfstring = @import("../pdfstring.zig");
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

    const obj_value = try PdfObject.initString(obj_val, allocator_l);
    return obj_value;
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
    defer pdfstring.deinitPdfDocEncoding();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader);
    defer indirect1.deinit(allocator);
    defer indirect2.deinit(allocator);

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
    const unicode0 = try item0_ptr.String.toUnicode(allocator);
    defer allocator.free(unicode0);
    try std.testing.expectEqualStrings(unicode0, "val0");

    const item1_ptr = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expect(item1_ptr.getTag() == .String);
    const unicode1 = try item1_ptr.String.toUnicode(allocator);
    defer allocator.free(unicode1);
    try std.testing.expectEqualStrings(unicode1, "val1");

    _ = try arr.get(0);
    _ = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 2);
}

test "PdfArray.appendObject and get" {
    resetMockLoaderFlags();
    defer pdfstring.deinitPdfDocEncoding();

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var obj1 = try PdfObject.initString("direct1", allocator);
    defer obj1.deinit(allocator);
    var obj2 = try PdfObject.initString("direct2", allocator);
    defer obj2.deinit(allocator);

    try arr.appendObject(obj1.*);
    try arr.appendObject(obj2.*);

    try std.testing.expectEqual(arr.len(), 2);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);

    const item0_ptr = try arr.get(0);
    try std.testing.expectEqual(mock_loader_call_count, 0);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, true);
    try std.testing.expect(try item0_ptr.eql(obj1, allocator));

    const item1_ptr = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 0);
    try std.testing.expect(try item1_ptr.eql(obj2, allocator));
}

test "PdfArray.extend" {
    resetMockLoaderFlags();
    defer pdfstring.deinitPdfDocEncoding();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    defer indirect1.deinit(allocator);

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var obj1 = try PdfObject.initString("extended_direct1", allocator);
    defer obj1.deinit(allocator);

    const items_to_extend: []const PdfArrayItem = &[_]PdfArrayItem{
        .{ .unresolved = &indirect1 },
        .{ .resolved = obj1.* },
    };

    try arr.extend(items_to_extend);

    try std.testing.expectEqual(arr.len(), 2);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);

    const item0_ptr = try arr.get(0);
    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, true);
    try std.testing.expect(item0_ptr.getTag() == .String);

    const unicode0 = try item0_ptr.String.toUnicode(allocator);
    defer allocator.free(unicode0);
    try std.testing.expectEqualStrings(unicode0, "val0");

    const item1_ptr = try arr.get(1);
    try std.testing.expectEqual(mock_loader_call_count, 1);
    try std.testing.expect(try item1_ptr.eql(obj1, allocator));
}

test "PdfArray.pop" {
    resetMockLoaderFlags();
    defer pdfstring.deinitPdfDocEncoding();

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader);
    defer indirect1.deinit(allocator);
    defer indirect2.deinit(allocator);

    var obj1 = try PdfObject.initString("pop_direct1", allocator);
    defer obj1.deinit(allocator);

    try arr.appendIndirect(&indirect1);
    try arr.appendObject(obj1.*);
    try arr.appendIndirect(&indirect2);

    try std.testing.expectEqual(arr.len(), 3);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);

    const popped_item = try arr.pop();
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, true);

    try std.testing.expect(popped_item != null);
    var popped_obj = popped_item.?;
    defer popped_obj.deinit(allocator);

    try std.testing.expect(popped_obj.getTag() == .String);
    const unicode1 = try popped_obj.String.toUnicode(allocator);
    defer allocator.free(unicode1);
    try std.testing.expectEqualStrings(unicode1, "val1");
    try std.testing.expectEqual(arr.len(), 2);

    const popped_item2 = try arr.pop();
    try std.testing.expect(popped_item2 != null);
    var popped_obj2 = popped_item2.?;
    defer popped_obj2.deinit(allocator);
    try std.testing.expect(try popped_obj2.eql(obj1, allocator));

    try std.testing.expectEqual(arr.len(), 1);

    const popped_item3 = try arr.pop();
    try std.testing.expect(popped_item3 != null);
    var popped_obj3 = popped_item3.?;
    defer popped_obj3.deinit(allocator);

    try std.testing.expect(popped_obj3.getTag() == .String);
    const unicode0 = try popped_obj3.String.toUnicode(allocator);
    defer allocator.free(unicode0);
    try std.testing.expectEqualStrings(unicode0, "val0");

    try std.testing.expectEqual(arr.len(), 0);

    const popped_item4 = try arr.pop();
    try std.testing.expect(popped_item4 == null);
    try std.testing.expectEqual(arr.len(), 0);
}

test "PdfArray.iterator" {
    resetMockLoaderFlags();
    defer pdfstring.deinitPdfDocEncoding();

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader);
    defer indirect1.deinit(allocator);
    defer indirect2.deinit(allocator);

    var obj1 = try PdfObject.initString("iter_direct1", allocator);
    defer obj1.deinit(allocator);

    try arr.appendIndirect(&indirect1);
    try arr.appendObject(obj1.*);
    try arr.appendIndirect(&indirect2);

    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);

    var iter = try arr.iterator();
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, true);

    var count: usize = 0;
    while (try iter.next()) |item_ptr| {
        switch (count) {
            0 => {
                try std.testing.expect(item_ptr.getTag() == .String);
                // FIX 2: Free the temporary string created by toUnicode.
                const unicode0 = try item_ptr.String.toUnicode(allocator);
                defer allocator.free(unicode0);
                try std.testing.expectEqualStrings(unicode0, "val0");
            },
            1 => {
                try std.testing.expect(try item_ptr.eql(obj1, allocator));
            },
            2 => {
                try std.testing.expect(item_ptr.getTag() == .String);
                const unicode1 = try item_ptr.String.toUnicode(allocator);
                defer allocator.free(unicode1);
                try std.testing.expectEqualStrings(unicode1, "val1");
            },
            else => unreachable,
        }
        count += 1;
    }
    try std.testing.expectEqual(count, 3);
    try std.testing.expectEqual(mock_loader_call_count, 2);
}

test "PdfArray.count" {
    resetMockLoaderFlags();
    defer pdfstring.deinitPdfDocEncoding();

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    var indirect2 = PdfIndirect.init(2, 0, mockIndirectLoader);
    var indirect3 = PdfIndirect.init(3, 0, mockIndirectLoader);
    var indirect4 = PdfIndirect.init(4, 0, mockIndirectLoader);

    defer indirect1.deinit(allocator);
    defer indirect2.deinit(allocator);
    defer indirect3.deinit(allocator);
    defer indirect4.deinit(allocator);

    // This part is correct: you create objects and correctly defer their deinit.
    var obj0 = try PdfObject.initString("val0", allocator);
    defer obj0.deinit(allocator);
    var obj_other = try PdfObject.initString("other", allocator);
    defer obj_other.deinit(allocator);

    try arr.appendIndirect(&indirect1);
    try arr.appendObject(obj_other.*);
    try arr.appendIndirect(&indirect2);
    try arr.appendObject(obj0.*);
    try arr.appendIndirect(&indirect3);
    try arr.appendIndirect(&indirect4);

    try std.testing.expectEqual(arr.len(), 6);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);

    const count_val0 = try arr.count(obj0);
    try std.testing.expectEqual(mock_loader_call_count, 4);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, true);
    try std.testing.expectEqual(count_val0, 3);

    const count_other = try arr.count(obj_other);
    try std.testing.expectEqual(mock_loader_call_count, 4);
    try std.testing.expectEqual(count_other, 1);

    var obj1_for_count = try PdfObject.initString("val1", allocator);
    defer obj1_for_count.deinit(allocator);
    const count_val1 = try arr.count(obj1_for_count);
    try std.testing.expectEqual(mock_loader_call_count, 4);
    try std.testing.expectEqual(count_val1, 1);

    var obj_missing = try PdfObject.initString("missing", allocator);
    defer obj_missing.deinit(allocator);
    const count_missing = try arr.count(obj_missing);
    try std.testing.expectEqual(mock_loader_call_count, 4);
    try std.testing.expectEqual(count_missing, 0);
}

test "PdfArray.ensureResolved with loader error" {
    resetMockLoaderFlags();
    mock_loader_should_fail = true;

    var arr = try PdfArray.init(allocator, false);
    defer arr.deinit();

    var indirect1 = PdfIndirect.init(1, 0, mockIndirectLoader);
    try arr.appendIndirect(&indirect1);

    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);

    try std.testing.expectError(error.ObjectNotFound, arr.get(0));

    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);
    try std.testing.expectEqual(mock_loader_call_count, 1);
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

    try std.testing.expectEqual(arr.all_items_resolved_attempted, false);

    const item0_ptr = try arr.get(0);
    try std.testing.expectEqual(mock_loader_call_count, 2);
    try std.testing.expectEqual(arr.all_items_resolved_attempted, true);

    try std.testing.expect(item0_ptr.getTag() == .Null);

    const item1_ptr = try arr.get(1);
    try std.testing.expect(item1_ptr.getTag() == .Null);
}
