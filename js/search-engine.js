class SearchEngine {
    constructor() {
        this.instance = null;
        this.memory = null;
    }

    async init() {
        const response = await fetch('search_engine.wasm');
        const wasmModule = await WebAssembly.instantiateStreaming(response, {
            env: {
                jsConsoleLog: (ptr, len) => {
                    const buffer = new Uint8Array(this.memory.buffer, ptr, len);
                    const text = new TextDecoder().decode(buffer);
                    console.log(text);
                }
            }
        });

        this.instance = wasmModule.instance;
        this.memory = this.instance.exports.memory;
    }

    createIndex() {
        return this.instance.exports.createIndex();
    }

    addDocument(index, id, text) {
        const encoder = new TextEncoder();
        const textBuffer = encoder.encode(text);
        const ptr = this._allocateMemory(textBuffer.length);
        
        const memory = new Uint8Array(this.memory.buffer);
        memory.set(textBuffer, ptr);
        
        this.instance.exports.addDocument(index, id, ptr, textBuffer.length);
    }

    search(index, query, maxResults = 10) {
        const encoder = new TextEncoder();
        const queryBuffer = encoder.encode(query);
        const queryPtr = this._allocateMemory(queryBuffer.length);
        
        const memory = new Uint8Array(this.memory.buffer);
        memory.set(queryBuffer, queryPtr);
        
        const resultsPtr = this._allocateMemory(maxResults * 4);
        const resultCount = this.instance.exports.search(index, queryPtr, queryBuffer.length, resultsPtr, maxResults);
        
        const results = new Uint32Array(this.memory.buffer, resultsPtr, resultCount);
        return Array.from(results);
    }

    serializeIndex(index) {
        const bufferSize = 1024 * 1024; // 1MB buffer
        const ptr = this._allocateMemory(bufferSize);
        const size = this.instance.exports.serializeIndex(index, ptr, bufferSize);
        const buffer = new Uint8Array(this.memory.buffer, ptr, size);
        return buffer.slice();
    }

    deserializeIndex(buffer) {
        const ptr = this._allocateMemory(buffer.length);
        const memory = new Uint8Array(this.memory.buffer);
        memory.set(buffer, ptr);
        return this.instance.exports.deserializeIndex(ptr, buffer.length);
    }

    _allocateMemory(size) {
        // Simple bump allocator - in real implementation, should use proper memory management
        const ptr = this.instance.exports.__heap_base || 65536;
        this.instance.exports.__heap_base = ptr + size;
        return ptr;
    }
}
