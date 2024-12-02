const std = @import("std");
const SearchResult = @import("search_result.zig").SearchResult;

pub const Term = struct {
    text: []const u8,
    frequency: u32,
};

pub const PostingList = struct {
    doc_id: u32,
    positions: std.ArrayList(usize),
};

pub const Index = struct {
    allocator: std.mem.Allocator,
    terms: std.StringHashMap(std.ArrayList(PostingList)),
    doc_count: u32,

    pub fn init(allocator: std.mem.Allocator) !Index {
        return Index{
            .allocator = allocator,
            .terms = std.StringHashMap(std.ArrayList(PostingList)).init(allocator),
            .doc_count = 0,
        };
    }

    pub fn deinit(self: *Index) void {
        var it = self.terms.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |*posting| {
                posting.positions.deinit();
            }
            entry.value_ptr.deinit();
        }
        self.terms.deinit();
    }

    pub fn addDocument(self: *Index, id: u32, text: []const u8) !void {
        var tokens = std.mem.tokenize(u8, text, " \t\n\r");
        var position: usize = 0;

        while (tokens.next()) |token| {
            const term_entry = try self.terms.getOrPut(token);
            if (!term_entry.found_existing) {
                term_entry.value_ptr.* = std.ArrayList(PostingList).init(self.allocator);
            }

            var posting_list = &term_entry.value_ptr.*;
            if (posting_list.items.len == 0 or posting_list.items[posting_list.items.len - 1].doc_id != id) {
                try posting_list.append(PostingList{
                    .doc_id = id,
                    .positions = std.ArrayList(usize).init(self.allocator),
                });
            }

            try posting_list.items[posting_list.items.len - 1].positions.append(position);
            position += 1;
        }

        self.doc_count += 1;
    }

    pub fn search(self: *Index, query: []const u8, results: *std.ArrayList(SearchResult)) !void {
        var scores = std.AutoHashMap(u32, f32).init(self.allocator);
        defer scores.deinit();

        var tokens = std.mem.tokenize(u8, query, " \t\n\r");
        while (tokens.next()) |token| {
            if (self.terms.get(token)) |posting_list| {
                for (posting_list.items) |posting| {
                    const tf: f32 = @floatFromInt(posting.positions.items.len);
                    const count_as_float: f32 = @floatFromInt(self.doc_count);
                    const num_items_as_float: f32 = @floatFromInt(posting.positions.items.len);
                    const idf = std.math.log(f32, 10, count_as_float / num_items_as_float);
                    const score = tf * idf;

                    const entry = try scores.getOrPut(posting.doc_id);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = score;
                    } else {
                        entry.value_ptr.* += score;
                    }
                }
            }
        }

        var it = scores.iterator();
        while (it.next()) |entry| {
            try results.append(SearchResult{
                .doc_id = entry.key_ptr.*,
                .score = entry.value_ptr.*,
            });
        }

        std.mem.sort(SearchResult, results.items, {}, SearchResult.compareDesc);
    }
};
