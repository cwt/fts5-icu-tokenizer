const c = @import("c");

pub const ubrk_open = if (@hasDecl(c, "ubrk_open")) c.ubrk_open else if (@hasDecl(c, "ubrk_open_77")) c.ubrk_open_77 else @field(c, "ubrk_open");
pub const ubrk_close = if (@hasDecl(c, "ubrk_close")) c.ubrk_close else if (@hasDecl(c, "ubrk_close_77")) c.ubrk_close_77 else @field(c, "ubrk_close");
pub const ubrk_clone = if (@hasDecl(c, "ubrk_clone")) c.ubrk_clone else if (@hasDecl(c, "ubrk_clone_77")) c.ubrk_clone_77 else @field(c, "ubrk_clone");
pub const ubrk_setText = if (@hasDecl(c, "ubrk_setText")) c.ubrk_setText else if (@hasDecl(c, "ubrk_setText_77")) c.ubrk_setText_77 else @field(c, "ubrk_setText");
pub const ubrk_first = if (@hasDecl(c, "ubrk_first")) c.ubrk_first else if (@hasDecl(c, "ubrk_first_77")) c.ubrk_first_77 else @field(c, "ubrk_first");
pub const ubrk_next = if (@hasDecl(c, "ubrk_next")) c.ubrk_next else if (@hasDecl(c, "ubrk_next_77")) c.ubrk_next_77 else @field(c, "ubrk_next");
pub const ubrk_getRuleStatus = if (@hasDecl(c, "ubrk_getRuleStatus")) c.ubrk_getRuleStatus else if (@hasDecl(c, "ubrk_getRuleStatus_77")) c.ubrk_getRuleStatus_77 else @field(c, "ubrk_getRuleStatus");
pub const u_strFromUTF8 = if (@hasDecl(c, "u_strFromUTF8")) c.u_strFromUTF8 else if (@hasDecl(c, "u_strFromUTF8_77")) c.u_strFromUTF8_77 else @field(c, "u_strFromUTF8");
pub const u_strToUTF8WithSub = if (@hasDecl(c, "u_strToUTF8WithSub")) c.u_strToUTF8WithSub else if (@hasDecl(c, "u_strToUTF8WithSub_77")) c.u_strToUTF8WithSub_77 else @field(c, "u_strToUTF8WithSub");
pub const u_strToUTF8 = if (@hasDecl(c, "u_strToUTF8")) c.u_strToUTF8 else if (@hasDecl(c, "u_strToUTF8_77")) c.u_strToUTF8_77 else @field(c, "u_strToUTF8");
pub const utrans_openU = if (@hasDecl(c, "utrans_openU")) c.utrans_openU else if (@hasDecl(c, "utrans_openU_77")) c.utrans_openU_77 else @field(c, "utrans_openU");
pub const utrans_close = if (@hasDecl(c, "utrans_close")) c.utrans_close else if (@hasDecl(c, "utrans_close_77")) c.utrans_close_77 else @field(c, "utrans_close");
pub const utrans_transUChars = if (@hasDecl(c, "utrans_transUChars")) c.utrans_transUChars else if (@hasDecl(c, "utrans_transUChars_77")) c.utrans_transUChars_77 else @field(c, "utrans_transUChars");
