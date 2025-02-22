const std = @import("std");
const builtin = @import("builtin");

pub const SearchResult = struct {
    doc_id: u32,
    score: f32,
};

pub const Index = struct {
    documents: std.ArrayList(Document),
    terms: std.StringHashMap(TermInfo),
    allocator: std.mem.Allocator,
    avg_doc_length: f32,

    const Document = struct {
        id: u32,
        length: u32,
        terms: std.StringHashMap(u32),
    };

    const TermInfo = struct {
        doc_freq: u32,
        postings: std.ArrayList(Posting),
    };

    const Posting = struct {
        doc_id: u32,
        freq: u32,
    };

    const k1: f32 = 1.2;
    const b: f32 = 0.75;

    pub fn init(allocator: std.mem.Allocator) !*Index {
        const index = try allocator.create(Index);
        index.* = Index{
            .documents = std.ArrayList(Document).init(allocator),
            .terms = std.StringHashMap(TermInfo).init(allocator),
            .allocator = allocator,
            .avg_doc_length = 0,
        };
        return index;
    }

    pub fn deinit(self: *Index) void {
        for (self.documents.items) |*doc| {
            doc.terms.deinit();
        }
        self.documents.deinit();

        var term_iter = self.terms.iterator();
        while (term_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.postings.deinit();
        }
        self.terms.deinit();
        self.allocator.destroy(self);
    }

    pub fn addDocument(self: *Index, doc_id: u32, text: []const u8) !void {
        var doc = Document{
            .id = doc_id,
            .length = 0,
            .terms = std.StringHashMap(u32).init(self.allocator),
        };

        var words = std.mem.splitSequence(u8, text, " ");
        while (words.next()) |word| {
            doc.length += 1;
            const term_count = try doc.terms.getOrPut(word);
            if (!term_count.found_existing) {
                term_count.value_ptr.* = 0;
            }
            term_count.value_ptr.* += 1;
        }

        try self.documents.append(doc);

        // Update average document length
        const total_docs = @as(f32, @floatFromInt(self.documents.items.len));
        const doc_length = @as(f32, @floatFromInt(doc.length));
        self.avg_doc_length = (self.avg_doc_length * (total_docs - 1) + doc_length) / total_docs;

        // Update term frequencies and postings
        var term_iter = doc.terms.iterator();
        while (term_iter.next()) |entry| {
            const term = entry.key_ptr.*;
            const freq = entry.value_ptr.*;

            const term_copy = try self.allocator.dupe(u8, term);
            const term_info = try self.terms.getOrPut(term_copy);
            if (!term_info.found_existing) {
                term_info.value_ptr.* = TermInfo{
                    .doc_freq = 0,
                    .postings = std.ArrayList(Posting).init(self.allocator),
                };
            } else {
                // Free the copy if key already exists
                self.allocator.free(term_copy);
            }
            term_info.value_ptr.doc_freq += 1;
            try term_info.value_ptr.postings.append(Posting{
                .doc_id = doc_id,
                .freq = freq,
            });
        }
    }

    pub fn search(self: *Index, query: []const u8) ![]SearchResult {
        var results = std.ArrayList(SearchResult).init(self.allocator);
        defer results.deinit();

        var scores = try std.ArrayList(f32).initCapacity(self.allocator, self.documents.items.len);
        defer scores.deinit();
        try scores.appendNTimes(0, self.documents.items.len);

        const avg_len = self.avg_doc_length;

        var query_terms = std.mem.splitSequence(u8, query, " ");
        while (query_terms.next()) |term| {
            if (self.terms.get(term)) |term_info| {
                const idf = std.math.log(f32, 10, @as(f32, @floatFromInt(self.documents.items.len)) / @as(f32, @floatFromInt(term_info.doc_freq)));

                for (term_info.postings.items) |posting| {
                    const doc = self.documents.items[posting.doc_id];
                    const tf = @as(f32, @floatFromInt(posting.freq));
                    const doc_len = @as(f32, @floatFromInt(doc.length));

                    const numerator = tf * (Index.k1 + 1.0);
                    const denominator = tf + Index.k1 * (1.0 - Index.b + Index.b * doc_len / avg_len);

                    scores.items[posting.doc_id] += idf * numerator / denominator;
                }
            }
        }

        // Convert scores to results
        for (scores.items, 0..) |score, i| {
            if (score > 0) {
                try results.append(SearchResult{
                    .doc_id = @intCast(i),
                    .score = score,
                });
            }
        }

        // Sort results by score
        std.mem.sort(SearchResult, results.items, {}, struct {
            fn lessThan(_: void, left: SearchResult, right: SearchResult) bool {
                return left.score > right.score;
            }
        }.lessThan);

        return results.toOwnedSlice();
    }

    pub fn saveToDisk(self: *Index, filename: []const u8) !void {
        const file = if (builtin.os.tag == .windows)
            try std.fs.cwd().createFileW(try std.unicode.utf8ToUtf16LeAlloc(self.allocator, filename), .{})
        else
            try std.fs.cwd().createFile(filename, .{});
        defer file.close();
        const writer = file.writer();

        // Write document count
        try writer.writeInt(u32, @intCast(self.documents.items.len), .little);

        // Write documents
        for (self.documents.items) |doc| {
            try writer.writeInt(u32, doc.id, .little);
            try writer.writeInt(u32, doc.length, .little);

            // Write term count for this document
            try writer.writeInt(u32, @intCast(doc.terms.count()), .little);

            var term_iter = doc.terms.iterator();
            while (term_iter.next()) |entry| {
                // Write term length and term
                try writer.writeInt(u32, @intCast(entry.key_ptr.*.len), .little);
                try writer.writeAll(entry.key_ptr.*);
                // Write term frequency
                try writer.writeInt(u32, entry.value_ptr.*, .little);
            }
        }

        // Write term count
        try writer.writeInt(u32, @intCast(self.terms.count()), .little);

        // Write terms
        var term_iter = self.terms.iterator();
        while (term_iter.next()) |entry| {
            // Write term length and term
            try writer.writeInt(u32, @intCast(entry.key_ptr.*.len), .little);
            try writer.writeAll(entry.key_ptr.*);

            // Write term info
            const info = entry.value_ptr.*;
            try writer.writeInt(u32, info.doc_freq, .little);

            // Write posting count
            try writer.writeInt(u32, @intCast(info.postings.items.len), .little);

            // Write postings
            for (info.postings.items) |posting| {
                try writer.writeInt(u32, posting.doc_id, .little);
                try writer.writeInt(u32, posting.freq, .little);
            }
        }

        // Write average document length
        try writer.writeInt(u32, @bitCast(self.avg_doc_length), .little);
    }

    pub fn loadFromDisk(allocator: std.mem.Allocator, filename: []const u8) !*Index {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        const reader = file.reader();

        const index = try allocator.create(Index);
        index.* = Index{
            .documents = std.ArrayList(Document).init(allocator),
            .terms = std.StringHashMap(TermInfo).init(allocator),
            .allocator = allocator,
            .avg_doc_length = 0,
        };

        // Read document count
        const doc_count = try reader.readInt(u32, .little);
        try index.documents.ensureTotalCapacity(doc_count);

        // Read documents
        for (0..doc_count) |_| {
            const id = try reader.readInt(u32, .little);
            const length = try reader.readInt(u32, .little);
            const term_count = try reader.readInt(u32, .little);

            var doc = Document{
                .id = id,
                .length = length,
                .terms = std.StringHashMap(u32).init(allocator),
            };

            for (0..term_count) |_| {
                const term_len = try reader.readInt(u32, .little);
                const term = try allocator.alloc(u8, term_len);
                try reader.readNoEof(term);
                const freq = try reader.readInt(u32, .little);
                try doc.terms.put(term, freq);
            }

            try index.documents.append(doc);
        }

        // Read term count
        const term_count = try reader.readInt(u32, .little);

        // Read terms
        for (0..term_count) |_| {
            const term_len = try reader.readInt(u32, .little);
            const term = try allocator.alloc(u8, term_len);
            try reader.readNoEof(term);

            const doc_freq = try reader.readInt(u32, .little);
            const posting_count = try reader.readInt(u32, .little);

            var term_info = TermInfo{
                .doc_freq = doc_freq,
                .postings = std.ArrayList(Posting).init(allocator),
            };
            try term_info.postings.ensureTotalCapacity(posting_count);

            for (0..posting_count) |_| {
                const doc_id = try reader.readInt(u32, .little);
                const freq = try reader.readInt(u32, .little);
                term_info.postings.appendAssumeCapacity(Posting{
                    .doc_id = doc_id,
                    .freq = freq,
                });
            }

            try index.terms.put(term, term_info);
        }

        // Read average document length
        const avg_doc_length_bits = try reader.readInt(u32, .little);
        index.avg_doc_length = @bitCast(avg_doc_length_bits);

        return index;
    }
};
