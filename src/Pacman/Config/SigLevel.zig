/// Defines the complete verification policy for a given target (e.g., a package or database).
pub const VerificationPolicy = struct {
    verification: VerificationLevel = .optional,
    trust: TrustLevel = .trusted_only,
};

package: VerificationPolicy = .{
    .verification = .required,
},
database: VerificationPolicy = .{},

pub fn toInt(self: SigLevel) c_int {
    var bitmask: c_int = 0;
    switch (self.package.verification) {
        .never => {},
        .required => {
            bitmask |= c.ALPM_SIG_PACKAGE;
        },
        .optional => {
            bitmask |= c.ALPM_SIG_PACKAGE | c.ALPM_SIG_PACKAGE_OPTIONAL;
        },
    }
    switch (self.database.verification) {
        .never => {},
        .required => {
            bitmask |= c.ALPM_SIG_DATABASE;
        },
        .optional => {
            bitmask |= c.ALPM_SIG_DATABASE | c.ALPM_SIG_DATABASE_OPTIONAL;
        },
    }
    if (self.package.trust == .trust_all) {
        bitmask |= c.ALPM_SIG_PACKAGE_MARGINAL_OK | c.ALPM_SIG_PACKAGE_UNKNOWN_OK;
    }
    if (self.database.trust == .trust_all) {
        bitmask |= c.ALPM_SIG_DATABASE_MARGINAL_OK | c.ALPM_SIG_DATABASE_UNKNOWN_OK;
    }
    return bitmask;
}

pub const VerificationLevel = enum {
    never,
    optional,
    required,
};

pub const TrustLevel = enum {
    trust_all,
    trusted_only,
};

const c = @import("c");
const SigLevel = @This();
