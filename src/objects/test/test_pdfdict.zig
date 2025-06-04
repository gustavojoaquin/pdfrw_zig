const std = @import("std");

const allocator = std.testing.allocator;
const activeTag = std.meta.activeTag;
const testing = std.testing;
const pdfdict = @import("../pdfdict.zig");
const pdfname = @import("../pdfname.zig");
const pdfobject = @import("../pdfobject.zig");
const pdfindirect = @import("../pdfindirect.zig");

const PdfDict = pdfdict.PdfDict;
const PdfName = pdfname.PdfName;
const PdfObject = pdfobject.PdfObject;
const PdfIndirect = pdfindirect.PdfIndirect;

test "PdfDict indirect set and get" {
    const indirect_obj_num: u32 = 1;
    const indirect_gen_num: u32 = 0;
    var indirect_ptr = try PdfIndirect.init(indirect_obj_num, indirect_gen_num, PdfObject{ .integer = 42 });
    defer indirect_ptr.deinit();

    var dict = PdfDict.init(allocator);
    defer dict.deinit();

    var name_key = try PdfName.init(allocator, "Name");
    defer name_key.deinit(allocator);

    try dict.put(name_key, PdfObject{ .indirect_ref = indirect_ptr });

    var iter = dict.iterator();
    const entry = (try iter.next()).?;
    try testing.expectEqualStrings("/Name", entry.key.value);
    try testing.expect(activeTag(entry.value) == .indirect_ref);
    try testing.expect(entry.value.indirect_ref.eql(indirect_ptr));

    const resolved_value = try dict.get(name_key);
    try testing.expect(resolved_value != null);
    try testing.expect(activeTag(resolved_value.?) == .integer);
    try testing.expectEqual(@as(i64, 42), resolved_value.?.integer);

    var iter2 = dict.iterator();
    const resolved_entry = (try iter2.next()).?;
    try testing.expectEqualStrings("/Name", resolved_entry.key.value);
    try testing.expect(activeTag(resolved_entry.value) == .integer);
    try testing.expectEqual(@as(i64, 42), resolved_entry.value.integer);
}

test "PdfDict private attributes" {
    var dict = PdfDict.init(allocator);
    defer dict.deinit();

    try dict.setPrivate("internal_id", PdfObject{ .integer = 12345 });

    const value = dict.getPrivate("internal_id");
    try testing.expect(value != null);
    try testing.expect(activeTag(value.?) == .integer);
    try testing.expectEqual(@as(i64, 12345), value.?.integer);
}

test "PdfDict inheritance lookup" {
    var parent = PdfDict.init(allocator);
    defer parent.deinit();

    var rotate_key = try PdfName.init(allocator, "Rotate");
    defer rotate_key.deinit(allocator);
    try parent.put(rotate_key, PdfObject{ .integer = 90 });

    var child = PdfDict.init(allocator);
    defer child.deinit();
    child.parent = &parent;

    const rotate = try child.getInheritable(rotate_key);
    try testing.expect(rotate != null);
    try testing.expect(activeTag(rotate.?) == .integer);
    try testing.expectEqual(@as(i64, 90), rotate.?.integer);
}

test "PdfDict stream handling" {
    var dict = PdfDict.init(allocator);
    defer dict.deinit();

    const data = "stream data";
    try dict.setStream(data);

    try testing.expectEqualStrings(data, dict.stream.?);

    var length_key = try PdfName.init(allocator, "Length");
    defer length_key.deinit(allocator);
    const length = try dict.get(length_key);
    try testing.expect(length != null);
    try testing.expect(activeTag(length.?) == .integer);
    try testing.expectEqual(@as(i64, data.len), length.?.integer);
}

test "PdfDict indirect dictionary" {
    var indirect_dict = pdfdict.createIndirectPdfDict(allocator);
    defer indirect_dict.deinit();
    try testing.expect(indirect_dict.indirect == true);
}
