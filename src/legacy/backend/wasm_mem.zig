const std = @import("std");
const WasmBackend = @import("wasm.zig").WasmBackend;
const WasmOpcode = @import("wasm.zig").WasmOpcode;

pub const MemoryLayout = struct {
    pub const HEAP_BASE: u32 = 1024; // Alignement post-stack static

    /// Génère le préambule de la mémoire linéaire Wasm (1 page = 64KB)
    pub fn emitMemorySection(backend: *WasmBackend) !void {
        // Section Memory (ID 5) : 1 page minimum
        try backend.code.appendSlice(&[_]u8{ 0x05, 0x03, 0x01, 0x00, 0x01 });
    }

    /// Génère la fonction d'allocation dynamique interne (bump allocator)
    /// alloc(size: i32) -> ptr: i32
    pub fn emitBumpAlloc(backend: *WasmBackend) !void {
        // Charge HEAP_BASE, additionne la taille demandée et met à jour le pointeur
        try backend.emitOpcode(.i32_const);
        try backend.emitLeb128(HEAP_BASE);
        try backend.emitOpcode(.local_get);
        try backend.emitLeb128(0); // argument 'size'
        try backend.emitOpcode(.i32_add);
    }

    /// Écrit un struct de 2 champs en mémoire (ex: Pair a b)
    pub fn emitAllocPair(backend: *WasmBackend) !void {
        // i32.store offset=0 (Champ 1)
        try backend.emitOpcode(.i32_store);
        try backend.emitLeb128(2); // alignement 2^2 = 4
        try backend.emitLeb128(0); // offset 0

        // i32.store offset=4 (Champ 2)
        try backend.emitOpcode(.i32_store);
        try backend.emitLeb128(2);
        try backend.emitLeb128(4); // offset 4
    }
};
