const std = @import("std");
const pdfobject = @import("../pdfobject.zig");
const pdfindirect = @import("../pdfindirect.zig");
const pdfname = @import("../pdfname.zig");
const errors = @import("../errors.zig");

const PdfError = errors.PdfError;
const PdfName = pdfname.PdfName;
const PdfIndirect = pdfindirect.PdfIndirect;
const PdfObject = pdfobject.PdfObject;
const allocator = std.testing.allocator;

fn mockLoaderNull(
    _: *PdfIndirect,
    alloc: std.mem.Allocator,
) PdfError!?*PdfObject {
    return try PdfObject.initNull(alloc);
}

fn mockLoaderInt(
    _: *PdfIndirect,
    alloc: std.mem.Allocator,
) PdfError!?*pdfobject.PdfObject {
    const obj_ptr = try alloc.create(PdfObject);
    obj_ptr.* = PdfObject.initInteger(123);
    return obj_ptr;
}

test "PdfPbject initialization" {
    const null_obj = try PdfObject.initNull(allocator);
    defer null_obj.deinit(allocator);
    try std.testing.expect(null_obj.* == .Null);

    const true_obj = try PdfObject.initBoolean(true, allocator);
    defer true_obj.deinit(allocator);
    try std.testing.expect(true_obj.* == .Boolean and true_obj.Boolean == true);

    const false_obj = try PdfObject.initBoolean(false, allocator);
    defer false_obj.deinit(allocator);
    try std.testing.expect(false_obj.* == .Boolean and false_obj.Boolean == false);

    const int_obj = try PdfObject.initInteger(42, allocator);
    defer int_obj.deinit(allocator);
    try std.testing.expect(int_obj == .Integer and int_obj.Integer == 42);

    const real_obj = PdfObject.initReal(3.14);
    defer real_obj.deinit(allocator);
    try std.testing.expect(real_obj == .Real and real_obj.Real == 3.14);

    var string_obj = try PdfObject.initString("hello", allocator);
    defer string_obj.deinit(allocator);
    try std.testing.expect(string_obj.* == .String and std.mem.eql(u8, string_obj.String.encoded_bytes, "(hello)"));

    var name_obj = try PdfObject.initName("Name", allocator);
    defer name_obj.deinit(allocator);
    try std.testing.expect(name_obj == .Name and std.mem.eql(u8, name_obj.Name.to_pdf_string(), "/Name"));

    var array_obj = try PdfObject.initArray(false, allocator);
    defer array_obj.deinit(allocator);
    try std.testing.expect(array_obj == .Array);

    var dict_obj = try PdfObject.initDict(allocator);
    defer dict_obj.deinit(allocator);
    try std.testing.expect(dict_obj.* == .Dict);
}

test "PdfObject eql" {
    const pdfstring = @import("../pdfstring.zig");
    defer pdfstring.deinitPdfDocEncoding();

    var null1 = try PdfObject.initNull(allocator);
    var null2 = try PdfObject.initNull(allocator);
    defer {
        null1.deinit(allocator);
        null2.deinit(allocator);
    }
    try std.testing.expect(try null1.eql(null2, allocator));

    var true1 = try PdfObject.initBoolean(true, allocator);
    var true2 = try PdfObject.initBoolean(true, allocator);
    defer {
        true1.deinit(allocator);
        true2.deinit(allocator);
    }
    try std.testing.expect(try true1.eql(true2, allocator));

    var false1 = try PdfObject.initBoolean(false, allocator);
    var false2 = try PdfObject.initBoolean(false, allocator);
    defer {
        false1.deinit(allocator);
        false2.deinit(allocator);
    }
    try std.testing.expect(try false1.eql(false2, allocator));
    try std.testing.expect(!try false1.eql(true1, allocator));

    var int1 = try PdfObject.initInteger(100, allocator);
    var int2 = try PdfObject.initInteger(100, allocator);
    var int3 = try PdfObject.initInteger(200, allocator);
    defer {
        int1.deinit(allocator);
        int2.deinit(allocator);
        int3.deinit(allocator);
    }
    try std.testing.expect(try int1.eql(&int2, allocator));
    try std.testing.expect(!(try int1.eql(&int3, allocator)));

    var str1 = try PdfObject.initString("abc", allocator);
    var str2 = try PdfObject.initString("abc", allocator);
    var str3 = try PdfObject.initString("def", allocator);
    defer {
        str1.deinit(allocator);
        str2.deinit(allocator);
        str3.deinit(allocator);
    }
    try std.testing.expect(try str1.eql(str2, allocator));
    try std.testing.expect(!(try str1.eql(str3, allocator)));

    var name1 = try PdfObject.initName("Name", allocator);
    var name2 = try PdfObject.initName("Name", allocator);
    var name3 = try PdfObject.initName("Name2", allocator);
    defer {
        name1.deinit(allocator);
        name2.deinit(allocator);
        name3.deinit(allocator);
    }
    try std.testing.expect(try name1.eql(&name2, allocator));
    try std.testing.expect(!(try name1.eql(&name3, allocator)));

    var arr1 = try PdfObject.initArray(false, allocator);
    defer arr1.deinit(allocator);
    try arr1.Array.appendObject(PdfObject.initInteger(1));

    var arr2 = try PdfObject.initArray(false, allocator);
    defer arr2.deinit(allocator);
    try arr2.Array.appendObject(PdfObject.initInteger(1));

    var arr3 = try PdfObject.initArray(false, allocator);
    defer arr3.deinit(allocator);
    try arr3.Array.appendObject(PdfObject.initInteger(3));

    try std.testing.expect(try arr1.eql(&arr2, allocator));
    try std.testing.expect(!(try arr1.eql(&arr3, allocator)));

    const key = try PdfName.init_from_raw(allocator, "key");
    defer key.deinit(allocator);

    var dict1 = try PdfObject.initDict(allocator);
    defer dict1.deinit(allocator);

    try dict1.Dict.put(key, PdfObject.initInteger(1));

    var dict2 = try PdfObject.initDict(allocator);
    defer dict2.deinit(allocator);
    try dict2.Dict.put(key, PdfObject.initInteger(1));

    var dict3 = try PdfObject.initDict(allocator);
    defer dict3.deinit(allocator);
    try dict3.Dict.put(key, PdfObject.initInteger(3));

    try std.testing.expect(try dict1.eql(dict2, allocator));
    try std.testing.expect(!(try dict1.eql(dict3, allocator)));

    var indirect1 = PdfIndirect.init(1, 0, &mockLoaderNull);
    defer indirect1.deinit(allocator);

    var indirect2 = PdfIndirect.init(1, 0, &mockLoaderNull);
    defer indirect2.deinit(allocator);

    var indirect3 = PdfIndirect.init(2, 0, &mockLoaderNull);
    defer indirect3.deinit(allocator);

    var ref1 = PdfObject.initIndirectRef(&indirect1);
    var ref2 = PdfObject.initIndirectRef(&indirect2);
    var ref3 = PdfObject.initIndirectRef(&indirect3);

    try std.testing.expect(try ref1.eql(&ref2, allocator));
    try std.testing.expect(!(try ref1.eql(&ref3, allocator)));
}

test "PdfObject clone" {
    // Integer (simple value)
    var int_orig = PdfObject.initInteger(123);
    var int_clone = try int_orig.clone(allocator);
    defer int_clone.deinit(allocator);
    try std.testing.expect(try int_orig.eql(&int_clone, allocator));
    int_orig.Integer = 456;
    try std.testing.expect(int_clone.Integer == 123);

    // Name (owns memory)
    var name_orig = try PdfObject.initName("MyName", allocator);
    defer name_orig.deinit(allocator);
    var name_clone = try name_orig.clone(allocator);
    defer name_clone.deinit(allocator);
    try std.testing.expect(try name_orig.eql(&name_clone, allocator));
    try std.testing.expect(name_orig.Name.value.ptr != name_clone.Name.value.ptr);

    // Array (owns a pointer)
    var arr_orig = try PdfObject.initArray(false, allocator);
    defer arr_orig.deinit(allocator);
    try arr_orig.Array.appendObject(PdfObject.initInteger(1));
    var arr_clone = try arr_orig.clone(allocator);
    defer arr_clone.deinit(allocator);
    try std.testing.expect(try arr_orig.eql(&arr_clone, allocator));

    try arr_orig.Array.appendObject(PdfObject.initInteger(2));
    try std.testing.expect(arr_orig.Array.len() == 2);
    try std.testing.expect(arr_clone.Array.len() == 1);

    // Dictionary (owns a pointer)
    var dict_orig = try PdfObject.initDict(allocator);
    defer dict_orig.deinit(allocator);
    const key = try PdfName.init_from_raw(allocator, "key");
    defer key.deinit(allocator);
    try dict_orig.Dict.put(key, PdfObject.initInteger(10));

    var dict_clone = try dict_orig.clone(allocator);
    defer dict_clone.deinit(allocator);
    try std.testing.expect(try dict_orig.eql(&dict_clone, allocator));

    // Modify original dict, clone should be unaffected
    const key2 = try PdfName.init_from_raw(allocator, "key2");
    defer key2.deinit(allocator);
    try dict_orig.Dict.put(key2, PdfObject.initInteger(20));
    try std.testing.expect(dict_orig.Dict.map.count() == 2);
    try std.testing.expect(dict_clone.Dict.map.count() == 1);

    // Indirect Reference (should copy the pointer, not the referenced object)
    const indirect_ptr = try allocator.create(PdfIndirect);
    indirect_ptr.* = PdfIndirect.init(10, 5, &mockLoaderInt);
    defer {
        indirect_ptr.deinit(allocator);
        allocator.destroy(indirect_ptr);
    }
    var indirect_orig = PdfObject.initIndirectRef(indirect_ptr);
    var indirect_clone = try indirect_orig.clone(allocator);
    defer indirect_clone.deinit(allocator);

    try std.testing.expect(try indirect_orig.eql(&indirect_clone, allocator));
    try std.testing.expect(indirect_orig.IndirectRef == indirect_clone.IndirectRef);
}

test "PdfObject deinit frees all memory" {
    var dict = try PdfObject.initDict(allocator);
    defer dict.deinit(allocator);

    var array_to_be_cloned = try PdfObject.initArray(false, allocator);
    defer array_to_be_cloned.deinit(allocator);

    var nested_name_to_be_cloned = try PdfObject.initName("NestedName", allocator);
    defer nested_name_to_be_cloned.deinit(allocator);

    try array_to_be_cloned.Array.appendObject(nested_name_to_be_cloned);
    try array_to_be_cloned.Array.appendObject(PdfObject.initInteger(99));

    const key = try PdfName.init_from_raw(allocator, "MyArray");
    defer key.deinit(allocator);

    try dict.Dict.put(key, array_to_be_cloned);
}
