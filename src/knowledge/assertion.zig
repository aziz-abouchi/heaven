const triple = @import("triple");

pub const Status = enum {
    asserted,
    imported,
    derived,
    inferred,
    certified,
};

pub const Confidence = enum {
    low,
    medium,
    high,
};

pub const SourceKind = enum {
    user,
    wikidata,
    rdf,
    rdfs,
    owl,
    llm,
    smt,
    lean,
    rocq,
    internal,
};

pub const Provenance = struct {
    source: SourceKind,
    source_id: ?[]const u8 = null,
    timestamp: i64 = 0,
    revision: ?[]const u8 = null,
};

pub const Assertion = struct {
    triple: triple.Triple,
    status: Status,
    confidence: ?Confidence = null,
    provenance: Provenance,
};
