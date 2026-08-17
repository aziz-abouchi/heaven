const std = @import("std");
const llm = @import("llm.zig");

pub const Agent = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Agent {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Agent) void {
        _ = self;
        // Si l'agent alloue des ressources, libérez-les ici
    }

    /// Retourne une commande Heaven à exécuter, ou null si pas d'idée.
    pub fn suggest(self: *Agent, prompt: []const u8) !?[]const u8 {
        // Essayer d'abord le LLM (Ollama)
        if (try llm.query(prompt, self.allocator)) |response| {
            return response;
        }
        // Sinon, réponses codées
        if (std.mem.containsAtLeast(u8, prompt, 1, "commutativité") or std.mem.containsAtLeast(u8, prompt, 1, "commute")) {
            return try self.allocator.dupe(u8, "theorem comm_test : a + b = b + a");
        }

        if (std.mem.containsAtLeast(u8, prompt, 1, "factorise") or std.mem.containsAtLeast(u8, prompt, 1, "distributivité")) {
            return try self.allocator.dupe(u8, "rewrite a*(b+c) => a*b + a*c");
        }
        if (std.mem.containsAtLeast(u8, prompt, 1, "simplifie") or std.mem.containsAtLeast(u8, prompt, 1, "x+0")) {
            return try self.allocator.dupe(u8, "simplify x+0");
        }
        if (std.mem.containsAtLeast(u8, prompt, 1, "prouve") and std.mem.containsAtLeast(u8, prompt, 1, "add_comm")) {
            return try self.allocator.dupe(u8, "prove add_comm by simplify");
        }
        if (std.mem.containsAtLeast(u8, prompt, 1, "factorielle")) {
            return try self.allocator.dupe(u8, "let fac(n) = (if (== n 0) 1 (* n (fac (- n 1))))");
        }
        return null;
    }
};

pub fn deinit(self: *Agent) void {
    _ = self;
    // Nettoyage des ressources si nécessaire
}
