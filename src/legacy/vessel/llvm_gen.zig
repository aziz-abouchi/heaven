const std = @import("std");
const matrix_lib = @import("../core/matrix.zig");

// On simule ici la génération de bitcode LLVM
pub fn emitNode(matrix: *matrix_lib.Matrix, id: u32) ![]const u8 {
    const node = matrix.nodes.get(id) orelse return error.NotFound;
    return switch (node) {
        .Scalar => |v| try std.fmt.allocPrint(matrix.allocator, "f64 {d}", .{v}),
        .Apply => |a| try std.fmt.allocPrint(matrix.allocator, "call @{d}(...)", .{a.func}),
        else => "void",
    };
}

// Note : Tu devras lier llvm dans ton build (ex: -lLLVM-15)
pub const LLVMGenerator = struct {
    context: anytype, // LLVMContextRef
    module: anytype,  // LLVMModuleRef
    builder: anytype, // LLVMBuilderRef
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, module_name: [:0]const u8) !LLVMGenerator {
        // Import des fonctions C de LLVM via @cImport ou extern
        // Pour cet exemple, on simule la structure logique
        return .{
            .allocator = allocator,
            .context = null, // LLVMContextCreate()
            .module = null,  // LLVMModuleCreateWithNameInContext(module_name, context)
            .builder = null, // LLVMCreateBuilderInContext(context)
        };
    }

    pub fn genFunctionForAtom(self: *LLVMGenerator, matrix: *matrix_lib.Matrix, atom_id: u32) !void {
        const node = matrix.nodes.get(atom_id) orelse return error.NodeNotFound;
        
        // On crée une signature : void atom_X()
        const func_name = try std.fmt.allocPrintZ(self.allocator, "atom_{d}", .{atom_id});
        defer self.allocator.free(func_name);

        // --- Logique de génération de bitcode ---
        // 1. Définir la fonction
        // 2. Créer un bloc de base (Entry)
        // 3. Traduire le contenu du nœud en instructions LLVM IR
        
        switch (node) {
            .Scalar => |v| {
                // Retourne simplement la constante
                _ = v; 
            },
            .Apply => |a| {
                // Génère un 'call' vers la fonction de l'atome a.func
                _ = a;
            },
            else => {},
        }
    }

    pub fn dumpIR(self: *LLVMGenerator) void {
        // LLVMDumpModule(self.module)
    }
};
