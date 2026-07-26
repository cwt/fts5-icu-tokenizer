const c = @import("c");

comptime {
    // Verify ICU version: prefer _77 suffix on Fedora
    if (!@hasDecl(c, "ubrk_open")) {
        if (!@hasDecl(c, "ubrk_open_77")) {
            @compileError("ICU 77 bindings not found - ubrk_open missing from translate-c output");
        }
    }
}

pub const ubrk_open = if (@hasDecl(c, "ubrk_open")) c.ubrk_open else c.ubrk_open_77;
pub const ubrk_close = if (@hasDecl(c, "ubrk_close")) c.ubrk_close else c.ubrk_close_77;
pub const ubrk_setText = if (@hasDecl(c, "ubrk_setText")) c.ubrk_setText else c.ubrk_setText_77;
pub const ubrk_first = if (@hasDecl(c, "ubrk_first")) c.ubrk_first else c.ubrk_first_77;
pub const ubrk_next = if (@hasDecl(c, "ubrk_next")) c.ubrk_next else c.ubrk_next_77;
pub const ubrk_getRuleStatus = if (@hasDecl(c, "ubrk_getRuleStatus")) c.ubrk_getRuleStatus else c.ubrk_getRuleStatus_77;
pub const u_strFromUTF8 = if (@hasDecl(c, "u_strFromUTF8")) c.u_strFromUTF8 else c.u_strFromUTF8_77;
pub const u_strToUTF8WithSub = if (@hasDecl(c, "u_strToUTF8WithSub")) c.u_strToUTF8WithSub else c.u_strToUTF8WithSub_77;
pub const u_strToUTF8 = if (@hasDecl(c, "u_strToUTF8")) c.u_strToUTF8 else c.u_strToUTF8_77;
pub const utrans_openU = if (@hasDecl(c, "utrans_openU")) c.utrans_openU else c.utrans_openU_77;
pub const utrans_close = if (@hasDecl(c, "utrans_close")) c.utrans_close else c.utrans_close_77;
pub const utrans_transUChars = if (@hasDecl(c, "utrans_transUChars")) c.utrans_transUChars else c.utrans_transUChars_77;
