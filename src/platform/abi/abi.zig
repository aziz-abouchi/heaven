//! Facade de la couche ABI (docs/spec/_platform.md, _metrics.md).
//!
//! Re-exporte les sous-modules. Un consommateur externe importe
//! `abi` et accede a `abi.Precision`, `abi.Profile`, etc.

pub const precision = @import("precision.zig");
pub const error_ = @import("error.zig");
pub const capability = @import("capability.zig");
pub const metric = @import("metric.zig");
pub const profile = @import("profile.zig");
pub const profile_ser = @import("profile_ser.zig");
pub const profile_tree = @import("profile_tree.zig");
pub const profile_annotations = @import("profile_annotations.zig");

// Re-exports directs des types les plus utilises.
pub const Precision = precision.Precision;
pub const Monotonic = precision.Monotonic;
pub const Value = precision.Value;
pub const Metric = precision.Metric;

pub const PlatformError = error_.PlatformError;
pub const FailureReason = error_.FailureReason;

pub const FileCap = capability.FileCap;
pub const NetCap = capability.NetCap;
pub const EnergyCap = capability.EnergyCap;

pub const Profile = profile.Profile;
pub const ProfileId = profile.ProfileId;
pub const ProfileDiff = profile.ProfileDiff;
pub const ScopeKind = profile.ScopeKind;

pub const ProfileTree = profile_tree.ProfileTree;

pub const ProfileAnnotations = profile_annotations.ProfileAnnotations;
pub const MetricKind = profile_annotations.MetricKind;
pub const Best = profile_annotations.Best;
