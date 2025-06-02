const std = @import("std");
const pdfobject = @import("../pdfobject.zig");
const PdfObject = pdfobject.PdfObject;
const allocator = std.testing.allocator;

test "PdfPbject.init" {
    const text1 = "true";
    const obj1_ptr = try PdfObject.init(allocator, text1);
    defer obj1_ptr.deinit(allocator);
    const obj1 = obj1_ptr.*;

    try std.testing.expect(std.mem.eql(u8, obj1.value, "true"));
    try std.testing.expectEqual(obj1.indirect, false);

    const text2 = "/Name123";
    const obj2_ptr = try PdfObject.init(allocator, text2);
    defer obj2_ptr.deinit(allocator);
    const obj2 = obj2_ptr.*;

    try std.testing.expect(std.mem.eql(u8, obj2.value, "/Name123"));
    try std.testing.expectEqual(obj2.indirect, false);

    const text_empty = "";
    const obj_empty_ptr = try PdfObject.init(allocator, text_empty);
    defer obj_empty_ptr.deinit(allocator);
    const obj_empty = obj_empty_ptr.*;
    try std.testing.expect(std.mem.eql(u8, obj_empty.value, ""));
    try std.testing.expectEqual(obj_empty.indirect, false);
}

test "PdfObject.init_indirect" {
    const text1 = "null";
    const obj1 = try PdfObject.init_indirect(allocator, text1, true);
    defer obj1.deinit(allocator);

    try std.testing.expect(std.mem.eql(u8, obj1.value, "null"));
    try std.testing.expectEqual(obj1.indirect, true);

    const text2 = "123.45";
    const obj2 = try PdfObject.init_indirect(allocator, text2, false);
    defer obj2.deinit(allocator);

    try std.testing.expect(std.mem.eql(u8, obj2.value, "123.45"));
    try std.testing.expectEqual(obj2.indirect, false);

    const text_empty = "";
    const obj_empty = try PdfObject.init_indirect(allocator, text_empty, true);
    defer obj_empty.deinit(allocator);

    try std.testing.expect(std.mem.eql(u8, obj_empty.value, ""));
    try std.testing.expectEqual(obj_empty.indirect, true);
}

test "PdfObject.eql" {
    const obj1 = try PdfObject.init_indirect(allocator, "hello", false);
    const obj2 = try PdfObject.init_indirect(allocator, "hello", false);
    const obj3 = try PdfObject.init_indirect(allocator, "hello", true);
    const obj4 = try PdfObject.init_indirect(allocator, "world", false);
    const obj5 = try PdfObject.init_indirect(allocator, "world", true);

    defer obj1.deinit(allocator);
    defer obj2.deinit(allocator);
    defer obj3.deinit(allocator);
    defer obj4.deinit(allocator);
    defer obj5.deinit(allocator);

    try std.testing.expect(obj1.eql(obj2));
    try std.testing.expect(obj1.eql(obj1));
    try std.testing.expect(!obj1.eql(obj3));
    try std.testing.expect(!obj1.eql(obj4));
    try std.testing.expect(!obj1.eql(obj5));

    const obj_true = try PdfObject.init_indirect(allocator, "test", true);
    const obj_true_again = try PdfObject.init_indirect(allocator, "test", true);

    defer obj_true.deinit(allocator);
    defer obj_true_again.deinit(allocator);

    try std.testing.expect(obj_true.eql(obj_true_again));
}

test "PdfObject.eql_str" {
    const obj_false = try PdfObject.init_indirect(allocator, "compare_me", false);
    const obj_true = try PdfObject.init_indirect(allocator, "compare_me", true);

    defer obj_false.deinit(allocator);
    defer obj_true.deinit(allocator);

    try std.testing.expect(obj_false.eql_str("compare_me"));
    try std.testing.expect(!obj_false.eql_str("donotmatch"));
    try std.testing.expect(!obj_true.eql_str("compare_me"));
    try std.testing.expect(!obj_true.eql_str("donotmatch"));

    const obj_empty_false = try PdfObject.init_indirect(allocator, "", false);
    defer obj_empty_false.deinit(allocator);

    try std.testing.expect(obj_empty_false.eql_str(""));
    try std.testing.expect(!obj_empty_false.eql_str("a"));

    const obj_empty_true = try PdfObject.init_indirect(allocator, "", true);
    defer obj_empty_true.deinit(allocator);

    try std.testing.expect(!obj_empty_true.eql_str(""));
}
