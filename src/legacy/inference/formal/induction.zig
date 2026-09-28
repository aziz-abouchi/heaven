pub const InductionScheme = union(enum) {
    nat,
    list,
    tree,
    custom,
};
