//! PDF stream encryption and decryption routines.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Md5 = std.crypto.hash.Md5;
const rc4_mod = @import("rc4");
const Rc4 = rc4_mod.RC4;

const objects_mod = @import("object");
const PdfName = objects_mod.pdfname.PdfName;
const PdfDict = objects_mod.pdfdict.PdfDict;
const PdfObject = objects_mod.pdfobject.PdfObject;
const PdfArray = objects_mod.pdfarray.PdfArray;
const PdfArrayItem = objects_mod.pdfarray.PdfArrayItem;
const aes = std.crypto.core.aes;

/// Password padding string from the PDF 1.7 Specification, Algorithm 3.2.
const PASSWORD_PAD = "(\xbfN^Nu\x8aAd\x00NV\xff\xfa\x01\x08..\x00\xb6\xd0h>\x80/\x0c\xa9\xfedSiz";

pub fn encryptCbcAes128(
    input: []const u8,
    output: []u8,
    key: [16]u8,
    iv: [16]u8,
) void {
    std.debug.assert(input.len % 16 == 0);
    std.debug.assert(output.len == input.len);
    var block: [16]u8 = undefined;
    var prev = iv;
    var i: usize = 0;
    var cipher = aes.Aes128.initEnc(key);
    while (i < input.len) : (i += 16) {
        const block_in = input[i..][0..16];
        for (block, 0..) |_, j| {
            block[j] = block_in[j] ^ prev[j];
        }
        cipher.encrypt(&block, block_in);
        @memcpy(output[i..][0..16], &block);
        prev = block;
    }
}

pub fn decryptCbcAes128(
    input: []const u8,
    output: []u8,
    key: [16]u8,
    iv: [16]u8,
) void {
    std.debug.assert(input.len % 16 == 0);
    std.debug.assert(output.len == input.len);
    var block: [16]u8 = undefined;
    var prev = iv;
    var i: usize = 0;
    var cipher = aes.Aes128.init(key);
    while (i < input.len) : (i += 16) {
        const block_in = input[i..][0..16];
        cipher.decryptBlock(&block, block_in);
        for (output[i..][0..16], 0..) |*out_byte, j| {
            out_byte.* = block[j] ^ prev[j];
        }
        prev = block_in;
    }
}

/// Errors that can occur during PDF decryption operations.
pub const CryptError = error{
    MissingEncryptDict,
    EncryptEntryNotADict,
    MissingRequiredDictKey,
    DictKeyHasWrongType,
    InvalidID,
    InvalidPadding,
    AESDecryptionFailed,
    UnsupportedFilter,
    InvalidArrayItemType,
};

/// Iterator for objects that have a stream to be processed.
pub const StreamIterator = struct {
    list: []PdfDict,
    index: usize = 0,

    pub fn next(it: *StreamIterator) ?*PdfDict {
        while (it.index < it.list.len) {
            const i = it.index;
            it.index += 1;
            const obj = &it.list[i];
            if (obj.stream != null) {
                return obj;
            }
        }
        return null;
    }
};

pub fn streamObjects(list: []PdfDict) StreamIterator {
    return .{ .list = list };
}

/// Creates an encryption key based on the user password.
/// Implements Algorithm 3.2 from the PDF 1.7 Specification.
pub fn createKey(password: []const u8, doc: *PdfDict, allocator: Allocator) ![]u8 {
    const encrypt_name = try PdfName.init_from_raw(allocator, "Encrypt");
    defer encrypt_name.deinit(allocator);
    var encrypt_obj = (try doc.get(&encrypt_name)) orelse return CryptError.MissingEncryptDict;
    defer encrypt_obj.deinit(allocator);
    var encrypt = encrypt_obj.asDict() orelse return CryptError.EncryptEntryNotADict;

    const length_name = try PdfName.init_from_raw(allocator, "Length");
    defer length_name.deinit(allocator);
    var length_obj = try encrypt.get(&length_name);
    if (length_obj != null) {
        defer length_obj.?.deinit(allocator);
    }
    const key_size_bits = if (length_obj) |obj| obj.asInt() orelse 40 else 40;
    const key_size: usize = @intCast(@divTrunc(key_size_bits, 8));

    var pass_buf: [32]u8 = undefined;
    const padded_pass_slice: []const u8 = if (password.len >= 32)
        password[0..32]
    else blk: {
        @memcpy(pass_buf[0..password.len], password);
        @memcpy(pass_buf[password.len..32], PASSWORD_PAD[0 .. 32 - password.len]);
        break :blk &pass_buf;
    };

    var md5 = Md5.init(.{});
    md5.update(padded_pass_slice);

    const o_name = try PdfName.init_from_raw(allocator, "O");
    defer o_name.deinit(allocator);
    var o_val = (try encrypt.get(&o_name)) orelse return CryptError.MissingRequiredDictKey;
    defer o_val.deinit(allocator);
    const o_string = o_val.asString() orelse return CryptError.DictKeyHasWrongType;
    md5.update(o_string.rawBytes());

    const p_name = try PdfName.init_from_raw(allocator, "P");
    defer p_name.deinit(allocator);
    var p_obj = try encrypt.get(&p_name);
    if (p_obj != null) {
        defer p_obj.?.deinit(allocator);
    }
    const p_val: i32 = if (p_obj) |obj| @intCast(obj.asInt() orelse 0) else 0;
    var p_buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &p_buf, p_val, .little);
    md5.update(&p_buf);

    const id_name = try PdfName.init_from_raw(allocator, "ID");
    defer id_name.deinit(allocator);
    var id_obj = (try doc.get(&id_name)) orelse return CryptError.InvalidID;
    defer id_obj.deinit(allocator);

    const id_array = id_obj.asArray() orelse return CryptError.DictKeyHasWrongType;
    if (id_array.items.items.len == 0) return CryptError.InvalidID;
    const first_item_obj = &id_array.items.items[0].resolved;
    const first_id_string = first_item_obj.asString() orelse return CryptError.DictKeyHasWrongType;
    md5.update(first_id_string.rawBytes());

    var encrypt_meta_name = try PdfName.init_from_raw(allocator, "EncryptMetadata");
    defer encrypt_meta_name.deinit(allocator);
    if (try encrypt.get(&encrypt_meta_name)) |meta_obj| {
        if (meta_obj.asBoolean()) |is_encrypted| {
            if (!is_encrypted) {
                const ff_bytes = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
                md5.update(&ff_bytes);
            }
        }
    }

    var temp_hash: [16]u8 = undefined;
    md5.final(&temp_hash);

    const r_name = try PdfName.init_from_raw(allocator, "R");
    defer r_name.deinit(allocator);
    var r_obj = try encrypt.get(&r_name);
    if (r_obj != null) {
        defer r_obj.?.deinit(allocator);
    }
    const revision = if (r_obj) |obj| obj.asInt() orelse 0 else 0;

    if (revision >= 3) {
        var round_hash = temp_hash;
        for (0..50) |_| {
            var round_md5 = Md5.init(.{});
            round_md5.update(&round_hash);
            round_md5.final(&round_hash);
        }
        return allocator.dupe(u8, round_hash[0..key_size]);
    }

    return allocator.dupe(u8, temp_hash[0..key_size]);
}

pub fn createUserHash(key: []const u8, doc: *PdfDict, allocator: Allocator) ![]u8 {
    const encrypt_name = try PdfName.init_from_raw(allocator, "Encrypt");
    defer encrypt_name.deinit(allocator);
    const encrypt_obj = (try doc.get(&encrypt_name)) orelse return CryptError.MissingEncryptDict;
    defer encrypt_obj.deinit(allocator);
    const encrypt = encrypt_obj.asDict() orelse return CryptError.EncryptEntryNotADict;

    const r_name = try PdfName.init_from_raw(allocator, "R");
    defer r_name.deinit(allocator);
    const r_obj = try encrypt.get(&r_name);
    if (r_obj) |obj| {
        defer obj.deinit(allocator);
    }
    const revision = if (r_obj) |obj| obj.asInt() orelse 0 else 0;

    if (revision < 3) {
        var rc4 = Rc4.init(key);
        const result = try allocator.alloc(u8, PASSWORD_PAD.len);
        rc4.process(result, PASSWORD_PAD);
        return result;
    } else {
        var md5 = Md5.init(.{});
        md5.update(PASSWORD_PAD);

        const id_name = try PdfName.init_from_raw(allocator, "ID");
        defer id_name.deinit(allocator);
        const id_obj = (try doc.get(&id_name)) orelse return CryptError.InvalidID;

        const id_array = id_obj.asArray() orelse return CryptError.DictKeyHasWrongType;
        if (id_array.len() == 0) return CryptError.InvalidID;
        const first_id_obj = try id_array.get(0);
        const first_id_bytes = (try first_id_obj.asBytes()) orelse return CryptError.DictKeyHasWrongType;
        md5.update(first_id_bytes);

        var temp_hash: [16]u8 = undefined;
        md5.final(&temp_hash);

        std.debug.assert(key.len <= 32);
        var temp_key_buf: [32]u8 = undefined;
        const temp_key_slice = temp_key_buf[0..key.len];

        for (0..20) |i| {
            for (key, 0..) |byte, j| {
                temp_key_slice[j] = byte ^ @as(u8, @intCast(i));
            }
            var rc4 = Rc4.init(temp_key_slice);
            rc4.process(&temp_hash, &temp_hash);
        }
        return try allocator.dupe(u8, &temp_hash);
    }
}

/// Check if the user password is correct. Implements Algorithm 3.6 from the PDF Spec.
pub fn checkUserPassword(key: []const u8, doc: *PdfDict, allocator: Allocator) !bool {
    const user_hash = try createUserHash(key, doc, allocator);
    defer allocator.free(user_hash);

    const encrypt_name = try PdfName.init_from_raw(allocator, "Encrypt");
    defer encrypt_name.deinit(allocator);
    const encrypt_obj = (try doc.get(&encrypt_name)) orelse return CryptError.MissingEncryptDict;
    defer encrypt_obj.deinit(allocator);
    const encrypt = encrypt_obj.asDict() orelse return CryptError.EncryptEntryNotADict;

    const u_name = try PdfName.init_from_raw(allocator, "U");
    defer u_name.deinit(allocator);
    const stored_hash_obj = (try encrypt.get(&u_name)) orelse return CryptError.MissingRequiredDictKey;
    defer stored_hash_obj.deinit(allocator);
    const stored_hash = (try stored_hash_obj.asBytes()) orelse return CryptError.DictKeyHasWrongType;
    defer allocator.free(stored_hash);

    const r_name = try PdfName.init_from_raw(allocator, "R");
    defer r_name.deinit(allocator);
    const r_obj = try encrypt.get(&r_name);
    if (r_obj) |obj| {
        obj.deinit(allocator);
    }
    const revision = if (r_obj) |obj| obj.asInt() orelse 0 else 0;

    return if (revision < 3)
        std.mem.eql(u8, stored_hash, user_hash)
    else
        std.mem.eql(u8, stored_hash[0..16], user_hash[0..16]);
}

/// Crypt filter for AESV2/AESV3 security handlers.
pub const AESCryptFilter = struct {
    key: []const u8,

    pub fn decryptData(self: @This(), num: u24, gen: u16, data: []const u8, allocator: Allocator) ![]u8 {
        var key_ext_buf: [5]u8 = undefined;
        std.mem.writeInt(u24, key_ext_buf[0..3], num, .little);
        std.mem.writeInt(u16, key_ext_buf[3..5], gen, .little);

        var md5 = Md5.init(.{});
        md5.update(self.key);
        md5.update(&key_ext_buf);
        if (self.key.len == 32) {
            md5.update("sAlT");
        }
        var hash: [16]u8 = undefined;
        md5.final(&hash);

        const iv = data[0..16];
        const ciphertext = data[16..];
        const decrypted_padded = try allocator.alloc(u8, ciphertext.len);
        errdefer allocator.free(decrypted_padded);

        var cipher = aes.Aes128.initDec(hash[0..16].*);

        var block: [16]u8 = undefined;
        var prev_block_in: [16]u8 = undefined;
        var i: usize = 0;
        while (i < ciphertext.len) : (i += 16) {
            const block_in = ciphertext[i..][0..16];
            cipher.decrypt(&block, block_in);
            for (decrypted_padded[i..][0..16], 0..) |*out_byte, j| {
                const prev_xor_byte = if (i == 0) iv[j] else prev_block_in[j];
                out_byte.* = block[j] ^ prev_xor_byte;
            }
            @memcpy(&prev_block_in, block_in);
        }

        const pad_size = decrypted_padded[decrypted_padded.len - 1];
        if (pad_size == 0 or pad_size > 16 or decrypted_padded.len < pad_size) {
            return CryptError.InvalidPadding;
        }
        const final_len = decrypted_padded.len - pad_size;

        for (decrypted_padded[final_len..]) |byte| {
            if (byte != pad_size) return CryptError.InvalidPadding;
        }

        return allocator.realloc(decrypted_padded, final_len);
    }
};

/// Crypt filter for V1/V2 security handlers (RC4).
pub const RC4CryptFilter = struct {
    key: []const u8,

    pub fn decryptData(self: @This(), num: u24, gen: u16, data: []const u8, allocator: Allocator) ![]u8 {
        var key_ext_buf: [5]u8 = undefined;
        std.mem.writeInt(u24, key_ext_buf[0..3], num, .little);
        std.mem.writeInt(u16, key_ext_buf[3..5], gen, .little);

        var md5 = Md5.init(.{});
        md5.update(self.key);
        md5.update(&key_ext_buf);

        var hash: [16]u8 = undefined;
        md5.final(&hash);

        const new_key_size = @min(self.key.len + 5, 16);
        var rc4 = Rc4.init(hash[0..new_key_size]);
        const result = try allocator.alloc(u8, data.len);
        rc4.process(result, data);
        return result;
    }
};

/// Identity crypt filter (no encryption).
pub const IdentityCryptFilter = struct {
    pub fn decryptData(_: @This(), _: u32, _: u16, data: []const u8, allocator: Allocator) ![]u8 {
        return allocator.dupe(u8, data);
    }
};

/// A polymorphic crypt filter that can be one of several concrete implementations.
pub const CryptFilter = union(enum) {
    AES: AESCryptFilter,
    RC4: RC4CryptFilter,
    Identity: IdentityCryptFilter,

    /// Dispatches the decryptData call to the active filter implementation.
    pub fn decryptData(self: @This(), num: u32, gen: u16, data: []const u8, allocator: Allocator) ![]u8 {
        return switch (self) {
            // Note: AES/RC4 decryptData expect u24 for num
            .AES => |filter_instance| filter_instance.decryptData(@truncate(num), gen, data, allocator),
            .RC4 => |filter_instance| filter_instance.decryptData(@truncate(num), gen, data, allocator),
            .Identity => |filter_instance| filter_instance.decryptData(num, gen, data, allocator),
        };
    }
};

/// Decrypts a list of stream objects in place.
pub fn decryptObjects(
    objects: []PdfDict,
    default_filter: CryptFilter,
    filters: std.StringHashMap(CryptFilter),
    allocator: Allocator,
) !void {
    var name_buffer: [64]u8 = undefined;
    var tmp_allocator = std.heap.FixedBufferAllocator.init(&name_buffer);

    var it = streamObjects(objects);
    while (it.next()) |obj| {
        if (obj.getPrivate("decrypted") != null) continue;

        var current_filter = default_filter;

        const filter_name_key = try PdfName.init_from_raw(tmp_allocator.allocator(), "Filter");
        defer filter_name_key.deinit(tmp_allocator.allocator());

        const filter_objects_opt = try obj.get(&filter_name_key);
        if (filter_objects_opt) |filter_obj| {
            defer filter_obj.deinit(allocator);
            const crypt_name_key = try PdfName.init_from_raw(tmp_allocator.allocator(), "Crypt");
            defer crypt_name_key.deinit(tmp_allocator.allocator());

            var filter_is_crypt = false;

            if (filter_obj.asArray()) |arr| {
                if (arr.items.items.len > 0) {
                    const first_item = &arr.items.items[0];
                    if (first_item.* == .resolved) {
                        if (first_item.resolved.isName() and first_item.resolved.asName().?.eql(crypt_name_key)) {
                            filter_is_crypt = true;
                        }
                    } else return CryptError.InvalidArrayItemType;
                }
            } else {
                if (filter_obj.isName() and filter_obj.asName().?.eql(crypt_name_key)) {
                    filter_is_crypt = true;
                }
            }

            if (filter_is_crypt) {
                const parms_key_dp = try PdfName.init_from_raw(tmp_allocator.allocator(), "DP");
                defer parms_key_dp.deinit(tmp_allocator.allocator());
                const parms_key_decode = try PdfName.init_from_raw(tmp_allocator.allocator(), "DecodeParms");
                defer parms_key_decode.deinit(tmp_allocator.allocator());

                const params_obj_opt = (try obj.get(&parms_key_decode)) orelse (try obj.get(&parms_key_dp));
                if (params_obj_opt) |params_obj| {
                    defer params_obj.deinit(allocator);
                    const params = params_obj.asDict() orelse return CryptError.DictKeyHasWrongType;

                    const name_key = try PdfName.init_from_raw(tmp_allocator.allocator(), "Name");
                    defer name_key.deinit(tmp_allocator.allocator());
                    const name_obj_opt = try params.get(&name_key);
                    if (name_obj_opt) |name_obj| {
                        defer name_obj.deinit(allocator);
                        const name = name_obj.asName() orelse return CryptError.DictKeyHasWrongType;
                        const filter_name_slice = name.value[1..];

                        if (filters.get(filter_name_slice)) |new_filter_ptr| {
                            current_filter = new_filter_ptr;
                        } else {
                            return CryptError.UnsupportedFilter;
                        }
                    } else {
                        return CryptError.MissingRequiredDictKey;
                    }
                } else {
                    return CryptError.MissingRequiredDictKey;
                }
            }
        }

        const obj_num: u32 = obj.indirect_num orelse 0;
        const obj_gen: u16 = obj.indirect_gen orelse 0;

        const stream_to_decrypt = obj.stream orelse continue;
        const decrypted_data = try current_filter.decryptData(obj_num, obj_gen, stream_to_decrypt, allocator);

        try obj.setStream(decrypted_data);
        allocator.free(decrypted_data);

        const decrypted_flag = PdfObject{ .Boolean = true };
        try obj.setPrivate("decrypted", decrypted_flag);
    }
}
