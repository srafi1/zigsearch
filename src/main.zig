const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create index
    var index = try root.Index.init(allocator);
    defer index.deinit();

    // Generate vocabulary of 100 terms
    var terms = std.ArrayList([]const u8).init(allocator);
    defer terms.deinit();

    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    // Create some random terms
    for (0..100) |i| {
        const term = try std.fmt.allocPrint(allocator, "term{d}", .{i});
        try terms.append(term);
    }
    defer {
        for (terms.items) |term| {
            allocator.free(term);
        }
    }

    // Store documents for later printing
    var documents = std.ArrayList([]u8).init(allocator);
    defer {
        for (documents.items) |doc| {
            allocator.free(doc);
        }
        documents.deinit();
    }

    // Start timing document indexing
    var timer = try std.time.Timer.start();
    const index_start = timer.lap();

    // Generate 10000 documents with 100 random words each
    for (0..10000) |doc_id| {
        var doc = std.ArrayList(u8).init(allocator);
        defer doc.deinit();

        for (0..100) |_| {
            // Select random term
            const term = terms.items[random.intRangeAtMost(usize, 0, terms.items.len - 1)];
            if (doc.items.len > 0) {
                try doc.append(' ');
            }
            try doc.appendSlice(term);
        }

        // Store document content
        try documents.append(try allocator.dupe(u8, doc.items));
        try index.addDocument(@intCast(doc_id), doc.items);
    }

    const index_end = timer.lap();
    const index_time_ms = @as(f64, @floatFromInt(index_end - index_start)) / 1_000_000.0;
    const docs_per_second = @as(f64, 10000) / (index_time_ms / 1000.0);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nIndexing Stats:\n", .{});
    try stdout.print("Total time: {d:.2}ms\n", .{index_time_ms});
    try stdout.print("Documents per second: {d:.2}\n", .{docs_per_second});

    // Test some queries
    const queries = [_][]const u8{
        "term0",
        "term0 term1",
        "term99",
        "term50 term51 term52",
    };

    try stdout.print("\nQuery Results:\n", .{});
    var total_query_time_ms: f64 = 0;

    for (queries) |query| {
        const query_start = timer.lap();

        try stdout.print("\nQuery: {s}\n", .{query});
        const results = try index.search(query);
        defer allocator.free(results);

        const query_end = timer.lap();
        const query_time_ms = @as(f64, @floatFromInt(query_end - query_start)) / 1_000_000.0;
        total_query_time_ms += query_time_ms;

        try stdout.print("Query time: {d:.2}ms\n", .{query_time_ms});
        try stdout.print("Top 5 results:\n", .{});
        const num_results = @min(results.len, 5);
        for (results[0..num_results]) |result| {
            try stdout.print("Doc {d}: score {d:.3}\n", .{ result.doc_id, result.score });
        }
    }

    const avg_query_time_ms = total_query_time_ms / queries.len;
    try stdout.print("Average query time: {d:.2}ms\n", .{avg_query_time_ms});
}
