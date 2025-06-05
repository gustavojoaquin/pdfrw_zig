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

fn test_loader_returns_int_42(_: *PdfIndirect, passed_allocator: std.mem.Allocator) !?*PdfObject {
    const obj = try passed_allocator.create(PdfObject);
    obj.* = PdfObject{ .Integer = 42 };
    return obj;
}

test "PdfDict indirect set and get" {
    const indirect_obj_num: u32 = 1;
    const indirect_gen_num: u32 = 0;

    var indirect_obj_instance = PdfIndirect.init(indirect_obj_num, indirect_gen_num, test_loader_returns_int_42);
    defer indirect_obj_instance.deinit(allocator);

    var dict = PdfDict.init(allocator);
    defer dict.deinit();

    var name_key = try PdfName.init_from_raw(allocator, "Name");
    defer name_key.deinit(allocator);

    try dict.put(name_key, PdfObject{ .IndirectRef = &indirect_obj_instance });

    var iter = dict.iterator();
    const entry = (try iter.next()).?;
    try testing.expectEqualStrings("/Name", entry.key.value);
    try testing.expect(activeTag(entry.value) == .IndirectRef);
    try testing.expect(entry.value.IndirectRef == &indirect_obj_instance);

    const resolved_value_opt = try dict.get(name_key);
    try testing.expect(resolved_value_opt != null);
    const resolved_value = resolved_value_opt.?;
    try testing.expect(activeTag(resolved_value) == .Integer);
    try testing.expectEqual(@as(i64, 42), resolved_value.Integer);

    var iter2 = dict.iterator();
    const resolved_entry = (try iter2.next()).?;
    try testing.expectEqualStrings("/Name", resolved_entry.key.value);
    try testing.expect(activeTag(resolved_entry.value) == .Integer);
    try testing.expectEqual(@as(i64, 42), resolved_entry.value.Integer);
}

test "PdfDict private attributes" {
    var dict = PdfDict.init(allocator);
    defer dict.deinit();

    try dict.setPrivate("internal_id", PdfObject{ .Integer = 12345 });

    const value_opt = dict.getPrivate("internal_id");
    try testing.expect(value_opt != null);
    const value = value_opt.?;
    try testing.expect(activeTag(value) == .Integer);
    try testing.expectEqual(@as(i64, 12345), value.Integer);
}

test "PdfDict inheritance lookup" {
    var parent = PdfDict.init(allocator);
    defer parent.deinit();

    var rotate_key = try PdfName.init_from_raw(allocator, "Rotate");
    defer rotate_key.deinit(allocator);
    try parent.put(rotate_key, PdfObject{ .Integer = 90 });

    var child = PdfDict.init(allocator);
    defer child.deinit();
    child.parent = &parent;

    const rotate_opt = try child.getInheritable(rotate_key);
    try testing.expect(rotate_opt != null);
    const rotate = rotate_opt.?;
    try testing.expect(activeTag(rotate) == .Integer);
    try testing.expectEqual(@as(i64, 90), rotate.Integer);
}

test "PdfDict stream handling" {
    var dict = PdfDict.init(allocator);
    defer dict.deinit();

    const data = "stream data";
    try dict.setStream(data);

    try testing.expectEqualStrings(data, dict.stream.?);

    var length_key = try PdfName.init_from_raw(allocator, "Length");
    defer length_key.deinit(allocator);
    const length_opt = try dict.get(length_key);
    try testing.expect(length_opt != null);
    const length = length_opt.?;
    try testing.expect(activeTag(length) == .Integer);
    try testing.expectEqual(@as(i64, data.len), length.Integer);
}

test "PdfDict indirect dictionary" {
    var indirect_dict = pdfdict.createIndirectPdfDict(allocator);
    defer indirect_dict.deinit();
    try testing.expect(indirect_dict.indirect == true);
}
