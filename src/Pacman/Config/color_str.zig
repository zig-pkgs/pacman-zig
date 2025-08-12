pub const on: c.colstr_t = .{
    .colon = BOLDBLUE ++ "::" ++ BOLD ++ " ",
    .title = BOLD,
    .repo = BOLDMAGENTA,
    .version = BOLDGREEN,
    .groups = BOLDBLUE,
    .meta = BOLDCYAN,
    .warn = BOLDYELLOW,
    .err = BOLDRED,
    .faint = GREY46,
    .nocolor = NOCOLOR,
};

pub const off: c.colstr_t = .{
    .colon = ":: ",
    .title = "",
    .repo = "",
    .version = "",
    .groups = "",
    .meta = "",
    .warn = "",
    .err = "",
    .faint = "",
    .nocolor = "",
};

pub const On = struct {
    pub const colon = BOLDBLUE ++ "::" ++ BOLD ++ " ";
    pub const title = BOLD;
    pub const repo = BOLDMAGENTA;
    pub const version = BOLDGREEN;
    pub const groups = BOLDBLUE;
    pub const meta = BOLDCYAN;
    pub const warn = BOLDYELLOW;
    pub const err = BOLDRED;
    pub const faint = GREY46;
    pub const nocolor = NOCOLOR;
};

pub const Off = struct {
    pub const colon = ":: ";
    pub const title = "";
    pub const repo = "";
    pub const version = "";
    pub const groups = "";
    pub const meta = "";
    pub const warn = "";
    pub const err = "";
    pub const faint = "";
    pub const nocolor = "";
};

pub const NOCOLOR = "\x1b[0m";

pub const BOLD = "\x1b[0;1m";

pub const BLACK = "\x1b[0;30m";
pub const RED = "\x1b[0;31m";
pub const GREEN = "\x1b[0;32m";
pub const YELLOW = "\x1b[0;33m";
pub const BLUE = "\x1b[0;34m";
pub const MAGENTA = "\x1b[0;35m";
pub const CYAN = "\x1b[0;36m";
pub const WHITE = "\x1b[0;37m";

pub const BOLDBLACK = "\x1b[1;30m";
pub const BOLDRED = "\x1b[1;31m";
pub const BOLDGREEN = "\x1b[1;32m";
pub const BOLDYELLOW = "\x1b[1;33m";
pub const BOLDBLUE = "\x1b[1;34m";
pub const BOLDMAGENTA = "\x1b[1;35m";
pub const BOLDCYAN = "\x1b[1;36m";
pub const BOLDWHITE = "\x1b[1;37m";
pub const GREY46 = "\x1b[38;5;243m";

const c = @import("c");
