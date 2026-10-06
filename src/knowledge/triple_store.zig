// ═══════════════════════════════════════════════════════════════════════════════
// Heaven Knowledge — TripleStore (Global RDF Storage)
// ═══════════════════════════════════════════════════════════════════════════════
// 
// Stocke les triplets RDF parsés depuis les fichiers .ttl
// Accessible globalement via le runtime Heaven.
//
// ═══════════════════════════════════════════════════════════════════════════════

const std = @import("std");
const turtle = @import("turtle_parser");

pub const TripleStore = struct {
    allocator: std.mem.Allocator,
    triples: std.ArrayListUnmanaged(turtle.Triple),
    prefixes: std.StringHashMap([]const u8),
    
    pub fn init(allocator: std.mem.Allocator) TripleStore {
        return .{
            .allocator = allocator,
            .triples = std.ArrayListUnmanaged(turtle.Triple){},
            .prefixes = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *TripleStore) void {
        // Libérer tous les triplets
        for (self.triples.items) |triple| {
            triple.deinit(self.allocator);
        }
        self.triples.deinit(self.allocator);
        
        // Libérer les préfixes
        var it = self.prefixes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.prefixes.deinit();
    }
    
    /// Ajoute des triplets parsés depuis un document Turtle
    pub fn addTurtle(self: *TripleStore, input: []const u8) !usize {
        const new_triples = try turtle.parseTurtle(self.allocator, input);
        defer self.allocator.free(new_triples);
        
        const added = new_triples.len;
        for (new_triples) |triple| {
            try self.triples.append(self.allocator, triple);
        }
        
        return added;
    }
    
    /// Requête simple : trouver tous les triplets avec un sujet donné
    pub fn queryBySubject(self: *TripleStore, subject_iri: []const u8) ![]turtle.Triple {
        var results = std.ArrayListUnmanaged(turtle.Triple){};
        errdefer results.deinit(self.allocator);
        
        for (self.triples.items) |triple| {
            switch (triple.subject) {
                .iri => |iri| {
                    if (std.mem.eql(u8, iri, subject_iri)) {
                        try results.append(self.allocator, triple);
                    }
                },
                else => {},
            }
        }
        
        return results.toOwnedSlice(self.allocator);
    }
    
    /// Requête simple : trouver tous les triplets avec un prédicat donné
    pub fn queryByPredicate(self: *TripleStore, predicate_iri: []const u8) ![]turtle.Triple {
        var results = std.ArrayListUnmanaged(turtle.Triple){};
        errdefer results.deinit(self.allocator);
        
        for (self.triples.items) |triple| {
            switch (triple.predicate) {
                .iri => |iri| {
                    if (std.mem.eql(u8, iri, predicate_iri)) {
                        try results.append(self.allocator, triple);
                    }
                },
                else => {},
            }
        }
        
        return results.toOwnedSlice(self.allocator);
    }
    
    /// Retourne le nombre total de triplets
    pub fn count(self: *TripleStore) usize {
        return self.triples.items.len;
    }
    
    /// Retourne tous les triplets (pour itération)
    pub fn getAll(self: *TripleStore) []const turtle.Triple {
        return self.triples.items;
    }
};
