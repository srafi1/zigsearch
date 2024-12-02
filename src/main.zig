const std = @import("std");
const Index = @import("index.zig").Index;
const SearchResult = @import("search_result.zig").SearchResult;
const serialization = @import("serialization.zig");

extern fn jsConsoleLog(ptr: [*]const u8, len: usize) void;

// JavaScript API exports
export fn createIndex() ?*Index {
    const index = std.heap.page_allocator.create(Index) catch {
        return null;
    };
    index.* = Index.init(std.heap.page_allocator) catch {
        return null;
    };
    return index;
}

export fn addDocument(index: *Index, id: u32, text_ptr: [*]const u8, text_len: usize) void {
    const text = text_ptr[0..text_len];
    index.addDocument(id, text) catch {
        jsConsoleLog("Failed to add document", 21);
    };
}

export fn search(index: *Index, query_ptr: [*]const u8, query_len: usize, results_ptr: [*]u32, max_results: usize) usize {
    const query = query_ptr[0..query_len];
    var results = std.ArrayList(SearchResult).init(std.heap.page_allocator);
    defer results.deinit();

    index.search(query, &results) catch {
        jsConsoleLog("Search failed", 12);
        return 0;
    };

    const result_count = @min(results.items.len, max_results);
    for (results.items[0..result_count], 0..) |result, i| {
        results_ptr[i] = result.doc_id;
    }
    return result_count;
}

export fn serializeIndex(index: *Index, buffer_ptr: [*]u8, buffer_len: usize) usize {
    return serialization.serialize(index, buffer_ptr[0..buffer_len]) catch 0;
}

export fn deserializeIndex(buffer_ptr: [*]const u8, buffer_len: usize) ?*Index {
    return serialization.deserialize(std.heap.page_allocator, buffer_ptr[0..buffer_len]) catch null;
}
