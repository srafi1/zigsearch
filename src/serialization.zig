const std = @import("std");
const Index = @import("index.zig").Index;
const PostingList = @import("index.zig").PostingList;

pub fn serialize(index: *Index, buffer: []u8) !usize {
    var stream = std.io.fixedBufferStream(buffer);
    var writer = stream.writer();

    try writer.writeIntLittle(u32, index.doc_count);

    var term_it = index.terms.iterator();
    try writer.writeIntLittle(u32, @as(u32, index.terms.count()));

    while (term_it.next()) |entry| {
        const term = entry.key_ptr.*;
        try writer.writeIntLittle(u32, @as(u32, term.len));
        try writer.writeAll(term);

        const posting_list = entry.value_ptr.*;
        try writer.writeIntLittle(u32, @as(u32, posting_list.items.len));

        for (posting_list.items) |posting| {
            try writer.writeIntLittle(u32, posting.doc_id);
            try writer.writeIntLittle(u32, @as(u32, posting.positions.items.len));
            for (posting.positions.items) |pos| {
                try writer.writeIntLittle(usize, pos);
            }
        }
    }

    return stream.pos;
}

pub fn deserialize(allocator: std.mem.Allocator, buffer: []const u8) !*Index {
    var stream = std.io.fixedBufferStream(buffer);
    var reader = stream.reader();

    var index = try allocator.create(Index);
    index.* = try Index.init(allocator);

    index.doc_count = try reader.readIntLittle(u32);
    const term_count = try reader.readIntLittle(u32);

    var i: u32 = 0;
    while (i < term_count) : (i += 1) {
        const term_len = try reader.readIntLittle(u32);
        const term = try allocator.alloc(u8, term_len);
        _ = try reader.readAll(term);

        var posting_list = std.ArrayList(PostingList).init(allocator);
        const posting_count = try reader.readIntLittle(u32);

        var j: u32 = 0;
        while (j < posting_count) : (j += 1) {
            const doc_id = try reader.readIntLittle(u32);
            const pos_count = try reader.readIntLittle(u32);

            var positions = std.ArrayList(usize).init(allocator);
            var k: u32 = 0;
            while (k < pos_count) : (k += 1) {
                const pos = try reader.readIntLittle(usize);
                try positions.append(pos);
            }

            try posting_list.append(PostingList{
                .doc_id = doc_id,
                .positions = positions,
            });
        }

        try index.terms.put(term, posting_list);
    }

    return index;
}
