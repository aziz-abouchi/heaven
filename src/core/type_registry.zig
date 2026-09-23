//! TypeRegistry — registre des types de données Heaven.
//!
//! v0 : stocke les `data` déclarés avec leurs paramètres typés et
//! leurs constructeurs. Ne fait PAS de type-checking (v1) — sert
//! uniquement à (a) vérifier qu'un type est bien déclaré, (b) rendre
//! les params accessibles pour l'affichage et l'élaboration future.

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Id = expr.Id;

pub const ParamInfo = struct {
    /// Nom du paramètre (`n` dans `Vec (n : Nat)`).
    name: []const u8,
    /// Id du type (`Nat`). Optionnel : un paramètre non-typé
    /// (`Maybe a`) a `ty = null` en v0.
    ty: ?Id,
};

pub const CtorInfo = struct {
    /// Nom du constructeur (`Nil`, `Cons`).
    name: []const u8,
    /// Nombre d'arguments (champs) du constructeur.
    arity: u8,
    /// Types des arguments (optionnels en v0 — souvent juste Id de symboles).
    arg_types: []Id,
};

pub const TypeInfo = struct {
    /// Nom du type (`Vec`).
    name: []const u8,
    /// Paramètres (`[(n, Nat)]`). Peut être vide.
    params: []ParamInfo,
    /// Constructeurs.
    ctors: []CtorInfo,
};

pub const TypeRegistry = struct {
    allocator: Allocator,
    types: std.StringHashMapUnmanaged(TypeInfo) = .{},

    pub fn init(allocator: Allocator) TypeRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TypeRegistry) void {
        var it = self.types.iterator();
        while (it.next()) |entry| {
            const ti = entry.value_ptr.*;
            // Libère les chaînes (name, param names, ctor names, arg_types).
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(ti.name);
            for (ti.params) |p| {
                self.allocator.free(p.name);
            }
            self.allocator.free(ti.params);
            for (ti.ctors) |c| {
                self.allocator.free(c.name);
                self.allocator.free(c.arg_types);
            }
            self.allocator.free(ti.ctors);
        }
        self.types.deinit(self.allocator);
    }

    pub fn register(self: *TypeRegistry, info: TypeInfo) !void {
        // Duplique le nom pour la clé (indépendant du `info.name`).
        const key = try self.allocator.dupe(u8, info.name);
        errdefer self.allocator.free(key);
        // Si déjà présent, on remplace (comportement : dernière déclaration gagne).
        if (self.types.getPtr(info.name)) |existing| {
            self.allocator.free(key);
            // Libère l'ancien et remplace.
            self.allocator.free(existing.name);
            for (existing.params) |p| self.allocator.free(p.name);
            self.allocator.free(existing.params);
            for (existing.ctors) |c| {
                self.allocator.free(c.name);
                self.allocator.free(c.arg_types);
            }
            self.allocator.free(existing.ctors);
            existing.* = info;
            return;
        }
        try self.types.put(self.allocator, key, info);
    }

    pub fn get(self: *const TypeRegistry, name: []const u8) ?TypeInfo {
        return self.types.get(name);
    }

    pub fn count(self: *const TypeRegistry) usize {
        return self.types.count();
    }
};
