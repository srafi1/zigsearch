pub const SearchResult = struct {
    doc_id: u32,
    score: f32,

    pub fn compareDesc(context: void, a: SearchResult, b: SearchResult) bool {
        _ = context;
        return a.score > b.score;
    }
};
