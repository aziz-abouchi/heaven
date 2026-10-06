// ═══════════════════════════════════════════════════════════════════════════════
// Heaven Knowledge — Turtle Parser (MVP)
// ═══════════════════════════════════════════════════════════════════════════════
// 
// Format Turtle supporté (subset RDF) :
//   @prefix foaf: <http://xmlns.com/foaf/0.1/> .
//   ex:alice foaf:name "Alice" .
//   ex:alice foaf:knows ex:bob .
//
// ═══════════════════════════════════════════════════════════════════════════════

const std = @import("std");

// ─── Types de données RDF ──────────────────────────────────────────────────────

pub const Term = union(enum) {
    iri: []const u8,              // URI complète ou préfixée
    literal: Literal,             // Chaîne, nombre, booléen
    blank_node: []const u8,       // _:label
    
    pub const Literal = struct {
        value: []const u8,
        datatype: Datatype,
        lang: ?[]const u8 = null, // @en, @fr, etc.
        
        pub const Datatype = enum {
            string,
            integer,
            decimal,
            boolean,
            custom,
        };
    };
    
    pub fn deinit(self: Term, allocator: std.mem.Allocator) void {
        switch (self) {
            .iri => |iri| allocator.free(iri),
            .blank_node => |bn| allocator.free(bn),
            .literal => |lit| {
                allocator.free(lit.value);
                if (lit.lang) |l| allocator.free(l);
            },
        }
    }
};

pub const Triple = struct {
    subject: Term,
    predicate: Term,
    object: Term,
    
    pub fn deinit(self: Triple, allocator: std.mem.Allocator) void {
        self.subject.deinit(allocator);
        self.predicate.deinit(allocator);
        self.object.deinit(allocator);
    }
};

pub const PrefixMap = std.StringHashMap([]const u8);

// ─── Erreurs de parsing ────────────────────────────────────────────────────────

pub const ParseError = error{
    InvalidSyntax,
    MissingPrefix,
    UnterminatedString,
    UnterminatedIri,
    InvalidTerm,
    MissingDot,
    UnexpectedToken,
    OutOfMemory,
};

// ─── Parser principal ──────────────────────────────────────────────────────────

pub const TurtleParser = struct {
    allocator: std.mem.Allocator,
    prefixes: PrefixMap,
    triples: std.ArrayListUnmanaged(Triple),
    
    pub fn init(allocator: std.mem.Allocator) TurtleParser {
        return .{
            .allocator = allocator,
            .prefixes = PrefixMap.init(allocator),
            .triples = std.ArrayListUnmanaged(Triple){},
        };
    }
    
    pub fn deinit(self: *TurtleParser) void {
        // Libérer les préfixes (clés et valeurs)
        var it = self.prefixes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.prefixes.deinit();
        
        // Libérer les triplets
        for (self.triples.items) |triple| {
            triple.deinit(self.allocator);
        }
        self.triples.deinit(self.allocator);
    }
    
    /// Parse un document Turtle complet
    pub fn parse(self: *TurtleParser, input: []const u8) ParseError!void {
        var pos: usize = 0;
        
        while (pos < input.len) {
            // Skip whitespace et commentaires
            pos = self.skipWhitespaceAndComments(input, pos);
            if (pos >= input.len) break;
            
            // Directive @prefix
            if (std.mem.startsWith(u8, input[pos..], "@prefix")) {
                pos = try self.parsePrefix(input, pos);
            }
            // Directive @base (non implémentée dans MVP)
            else if (std.mem.startsWith(u8, input[pos..], "@base")) {
                pos = self.skipLine(input, pos);
            }
            // Triplet
            else {
                pos = try self.parseTriple(input, pos);
            }
        }
    }
    
    // ─── Parsing des directives ────────────────────────────────────────────────
    
    fn parsePrefix(self: *TurtleParser, input: []const u8, pos: usize) ParseError!usize {
        var p = pos + "@prefix".len;
        
        // Skip whitespace
        p = self.skipWhitespace(input, p);
        
        // Lire le préfixe (ex: "foaf:")
        const prefix_start = p;
        while (p < input.len and input[p] != ':') p += 1;
        if (p >= input.len) return ParseError.InvalidSyntax;
        
        const prefix = input[prefix_start..p];
        p += 1; // skip ':'
        
        // Skip whitespace
        p = self.skipWhitespace(input, p);
        
        // Lire l'URI <...>
        if (input[p] != '<') return ParseError.InvalidSyntax;
        p += 1;
        
        const uri_start = p;
        while (p < input.len and input[p] != '>') p += 1;
        if (p >= input.len) return ParseError.UnterminatedIri;
        
        const uri = input[uri_start..p];
        p += 1; // skip '>'
        
        // Skip whitespace et '.'
        p = self.skipWhitespace(input, p);
        if (p >= input.len or input[p] != '.') return ParseError.MissingDot;
        p += 1;
        
        // Enregistrer le préfixe
        const prefix_owned = try self.allocator.dupe(u8, prefix);
        errdefer self.allocator.free(prefix_owned);
        const uri_owned = try self.allocator.dupe(u8, uri);
        errdefer self.allocator.free(uri_owned);
        try self.prefixes.put(prefix_owned, uri_owned);
        
        return p;
    }
    
    // ─── Parsing des triplets ──────────────────────────────────────────────────
    
    fn parseTriple(self: *TurtleParser, input: []const u8, pos: usize) ParseError!usize {
        var p = pos;
        
        // Sujet
        const subject = try self.parseTerm(input, &p);
        defer subject.deinit(self.allocator);
        p = self.skipWhitespace(input, p);
        
        // Boucle sur les predicats (;)
        while (true) {
            const predicate = try self.parseTerm(input, &p);
            defer predicate.deinit(self.allocator);
            p = self.skipWhitespace(input, p);
            
            // Boucle sur les objets (,)
            while (true) {
                const object = try self.parseTerm(input, &p);
                p = self.skipWhitespace(input, p);
                
                // Clone subject et predicate pour ce triple
                const subj_copy = try self.cloneTerm(subject);
                errdefer subj_copy.deinit(self.allocator);
                const pred_copy = try self.cloneTerm(predicate);
                errdefer pred_copy.deinit(self.allocator);
                
                try self.triples.append(self.allocator, .{
                    .subject = subj_copy,
                    .predicate = pred_copy,
                    .object = object,
                });
                
                if (p < input.len and input[p] == ',') {
                    p += 1;
                    p = self.skipWhitespace(input, p);
                    continue;
                }
                break;
            }
            
            if (p < input.len and input[p] == ';') {
                p += 1;
                p = self.skipWhitespace(input, p);
                // `;` suivi de `.` = fin de triple (predicat optionnel)
                if (p < input.len and input[p] == '.') break;
                continue;
            }
            break;
        }
        
        // Point final
        if (p >= input.len or input[p] != '.') return ParseError.MissingDot;
        p += 1;
        
        return p;
    }
    
    /// Duplique un Term (chaque triple possede ses propres slices).
    fn cloneTerm(self: *TurtleParser, t: Term) ParseError!Term {
        switch (t) {
            .iri => |iri| return Term{ .iri = try self.allocator.dupe(u8, iri) },
            .blank_node => |bn| return Term{ .blank_node = try self.allocator.dupe(u8, bn) },
            .literal => |lit| {
                const val = try self.allocator.dupe(u8, lit.value);
                errdefer self.allocator.free(val);
                const lang = if (lit.lang) |l| try self.allocator.dupe(u8, l) else null;
                return Term{ .literal = .{
                    .value = val,
                    .datatype = lit.datatype,
                    .lang = lang,
                } };
            },
        }
    }

    fn parseTerm(self: *TurtleParser, input: []const u8, pos: *usize) ParseError!Term {
        var p = pos.*;
        
        // IRI complète <...>
        if (input[p] == '<') {
            p += 1;
            const start = p;
            while (p < input.len and input[p] != '>') p += 1;
            if (p >= input.len) return ParseError.UnterminatedIri;
            
            const iri = try self.allocator.dupe(u8, input[start..p]);
            p += 1;
            pos.* = p;
            return Term{ .iri = iri };
        }
        
        // Littéral "..."
        if (input[p] == '"') {
            return self.parseLiteral(input, pos);
        }
        
        // Blank node _:label
        if (p + 1 < input.len and input[p] == '_' and input[p + 1] == ':') {
            p += 2;
            const start = p;
            while (p < input.len and !isWhitespace(input[p])
                   and input[p] != '.' and input[p] != ';' and input[p] != ',') p += 1;
            
            const label = try self.allocator.dupe(u8, input[start..p]);
            pos.* = p;
            return Term{ .blank_node = label };
        }
        
        // Préfixe ou IRI sans préfixe (ex: foaf:name ou <http://...>)
        const start = p;
        while (p < input.len and !isWhitespace(input[p])
               and input[p] != '.' and input[p] != ';' and input[p] != ',') p += 1;
        
        const token = input[start..p];
        if (token.len == 0) return ParseError.InvalidTerm;
        
        // Raccourci 'a' = rdf:type
        if (std.mem.eql(u8, token, "a")) {
            pos.* = p;
            return Term{ .iri = try self.allocator.dupe(u8,
                "http://www.w3.org/1999/02/22-rdf-syntax-ns#type") };
        }
        
        // Résoudre le préfixe si présent
        if (std.mem.indexOfScalar(u8, token, ':')) |colon_pos| {
            const prefix = token[0..colon_pos];
            const local = token[colon_pos + 1 ..];
            
            if (self.prefixes.get(prefix)) |base| {
                var full_iri = std.ArrayListUnmanaged(u8){};
                defer full_iri.deinit(self.allocator);
                
                try full_iri.appendSlice(self.allocator, base);
                try full_iri.appendSlice(self.allocator, local);
                
                pos.* = p;
                return Term{ .iri = try full_iri.toOwnedSlice(self.allocator) };
            } else {
                return ParseError.MissingPrefix;
            }
        }
        
        // Pas de préfixe, c'est une IRI relative ou un nom local
        const iri = try self.allocator.dupe(u8, token);
        pos.* = p;
        return Term{ .iri = iri };
    }
    
    fn parseLiteral(self: *TurtleParser, input: []const u8, pos: *usize) ParseError!Term {
        var p = pos.* + 1; // skip '"'
        const start = p;
        
        // Lire jusqu'au guillemet fermant (gérer les échappements simples)
        while (p < input.len) {
            if (input[p] == '\\' and p + 1 < input.len) {
                p += 2; // skip escaped char
                continue;
            }
            if (input[p] == '"') break;
            p += 1;
        }
        
        if (p >= input.len) return ParseError.UnterminatedString;
        
        const value = try self.allocator.dupe(u8, input[start..p]);
        errdefer self.allocator.free(value);
        p += 1; // skip '"'
        
        // Vérifier datatype ou langue
        var datatype = Term.Literal.Datatype.string;
        var lang: ?[]const u8 = null;
        
        if (p < input.len and input[p] == '^') {
            // ^^datatype
            p += 2;
            // TODO: parser datatype custom
            datatype = .custom;
            while (p < input.len and !isWhitespace(input[p]) and input[p] != '.') p += 1;
        } else if (p < input.len and input[p] == '@') {
            // @lang
            p += 1;
            const lang_start = p;
            while (p < input.len and !isWhitespace(input[p]) and input[p] != '.') p += 1;
            lang = try self.allocator.dupe(u8, input[lang_start..p]);
        } else {
            // Détecter le type automatiquement
            datatype = detectDatatype(value);
        }
        
        pos.* = p;
        return Term{ .literal = .{
            .value = value,
            .datatype = datatype,
            .lang = lang,
        } };
    }
    
    // ─── Utilitaires ───────────────────────────────────────────────────────────
    
    fn skipWhitespace(self: TurtleParser, input: []const u8, pos: usize) usize {
        _ = self;
        var p = pos;
        while (p < input.len and isWhitespace(input[p])) p += 1;
        return p;
    }
    
    fn skipWhitespaceAndComments(self: TurtleParser, input: []const u8, pos: usize) usize {
        var p = self.skipWhitespace(input, pos);
        
        // Commentaires # jusqu'à la fin de ligne
        while (p < input.len and input[p] == '#') {
            p = self.skipLine(input, p);
            p = self.skipWhitespace(input, p);
        }
        
        return p;
    }
    
    fn skipLine(self: TurtleParser, input: []const u8, pos: usize) usize {
        _ = self;
        var p = pos;
        while (p < input.len and input[p] != '\n') p += 1;
        return if (p < input.len) p + 1 else p;
    }
};

// ─── Fonctions globales ────────────────────────────────────────────────────────

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

fn detectDatatype(value: []const u8) Term.Literal.Datatype {
    // Booléen
    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false")) {
        return .boolean;
    }
    
    // Entier
    var is_int = true;
    for (value, 0..) |c, i| {
        if (i == 0 and (c == '+' or c == '-')) continue;
        if (!std.ascii.isDigit(c)) {
            is_int = false;
            break;
        }
    }
    if (is_int and value.len > 0) return .integer;
    
    // Nombre décimal
    if (std.fmt.parseFloat(f64, value) catch null) |_| {
        return .decimal;
    }
    
    return .string;
}

/// Parse un document Turtle et retourne les triplets.
/// Le caller est responsable de libérer chaque Triple via `triple.deinit(allocator)`
/// puis le slice via `allocator.free(triples)`.
pub fn parseTurtle(allocator: std.mem.Allocator, input: []const u8) ParseError![]Triple {
    var parser = TurtleParser.init(allocator);
    errdefer parser.deinit();
    
    try parser.parse(input);
    
    // Transférer la propriété des triplets vers le caller (on les "vole" au parser)
    // Les slices internes (IRIs, strings) restent valides.
    const result = try parser.triples.toOwnedSlice(allocator);
    
    // Maintenant le parser est vide de triplets, on peut le deinit proprement
    // (seuls les préfixes de la HashMap seront libérés)
    parser.deinit();
    
    return result;
}

// ─── Tests unitaires ──────────────────────────────────────────────────────────

test "parse simple prefix and triple" {
    const allocator = std.testing.allocator;
    
    const input =
        \\@prefix ex: <http://example.org/> .
        \\ex:alice ex:name "Alice" .
    ;
    
    const triples = try parseTurtle(allocator, input);
    defer {
        for (triples) |triple| {
            triple.deinit(allocator);
        }
        allocator.free(triples);
    }
    
    try std.testing.expectEqual(@as(usize, 1), triples.len);
    
    // Vérifier le sujet
    try std.testing.expectEqualStrings("http://example.org/alice", triples[0].subject.iri);
    
    // Vérifier le prédicat
    try std.testing.expectEqualStrings("http://example.org/name", triples[0].predicate.iri);
    
    // Vérifier l'objet
    try std.testing.expectEqualStrings("Alice", triples[0].object.literal.value);
}
