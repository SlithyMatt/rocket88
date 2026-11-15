/*
 * r88asm - assembler for the ROCKET88 8-bit architecture
 * See https://github.com/SlithyMatt/rocket88 for current code and documentation
 *
 * Portable C99: builds with gcc (Linux, MinGW) or clang, no extra libraries.
 *
 *   r88asm [-f bin|hex|mem] [-o output] [-l listing] [-p pad] input.asm [more.asm ...]
 *
 * Syntax (see README.md in this directory for details):
 *   label:                     define a label at the current address
 *   NAME = expression          define a constant
 *   .org expression            set the current address
 *   .byte expr|"string", ...   emit bytes          (also .db)
 *   .word expr, ...            emit 16-bit values  (also .addr, .dw), little endian
 *   .fill count [, value]      emit count copies of a byte
 *   .macro NAME [param, ...]   define a macro, ended by .endmacro (or .endm);
 *                              use it as NAME [argument, ...]
 *   mnemonic [operand]         one instruction; operands: a b c bc dd ee (bc) (dd)
 *                              #expression, or an address / label
 *   ; comment
 * Numbers: $FF, 0xFF, %1010, 255, 'A'. Expressions: + - * / & | ^ << >> ~,
 * parentheses, * for the current address, and .low / .high suffixes.
 */

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VERSION "1.0"
#define MAX_LINE 1024
#define MAX_NAME 64
#define MAX_PASSES 32

/* ------------------------------------------------------------------------- */
/* Opcode table                                                              */
/* ------------------------------------------------------------------------- */

enum form {
    F_NONE,     /* no operand                 */
    F_A, F_B, F_C,
    F_BC, F_DD, F_EE,
    F_IND_BC,   /* (bc)                       */
    F_IND_DD,   /* (dd)                       */
    F_IMM,      /* #N                         */
    F_ABS,      /* NN                         */
    F_REL       /* label (signed 8-bit offset) */
};

struct opcode {
    const char *mnemonic;
    enum form form;
    int op;
    int zero_op;    /* Zero mode opcode used for "#0", or -1 */
};

/* Generated from the opcode table in the main README (all documented opcodes) */
static const struct opcode opcodes[] = {
    {"NOP", F_NONE, 0x00, -1},
    {"LDAZ", F_NONE, 0x10, -1},
    {"LDA", F_A, 0x11, -1},
    {"LDA", F_B, 0x12, -1},
    {"LDA", F_C, 0x13, -1},
    {"LDA", F_IMM, 0x14, 0x10},
    {"LDA", F_ABS, 0x15, -1},
    {"LDA", F_IND_BC, 0x16, -1},
    {"PLA", F_NONE, 0x17, -1},
    {"CPAZ", F_NONE, 0x18, -1},
    {"CPA", F_A, 0x19, -1},
    {"CPA", F_B, 0x1A, -1},
    {"CPA", F_C, 0x1B, -1},
    {"CPA", F_IMM, 0x1C, 0x18},
    {"STA", F_ABS, 0x1D, -1},
    {"STA", F_IND_BC, 0x1E, -1},
    {"PHA", F_NONE, 0x1F, -1},
    {"LDBZ", F_NONE, 0x20, -1},
    {"LDB", F_A, 0x21, -1},
    {"LDB", F_B, 0x22, -1},
    {"LDB", F_C, 0x23, -1},
    {"LDB", F_IMM, 0x24, 0x20},
    {"LDB", F_ABS, 0x25, -1},
    {"LDB", F_IND_BC, 0x26, -1},
    {"PLB", F_NONE, 0x27, -1},
    {"CPBZ", F_NONE, 0x28, -1},
    {"CPB", F_A, 0x29, -1},
    {"CPB", F_B, 0x2A, -1},
    {"CPB", F_C, 0x2B, -1},
    {"CPB", F_IMM, 0x2C, 0x28},
    {"STB", F_ABS, 0x2D, -1},
    {"STB", F_IND_BC, 0x2E, -1},
    {"PHB", F_NONE, 0x2F, -1},
    {"LDCZ", F_NONE, 0x30, -1},
    {"LDC", F_A, 0x31, -1},
    {"LDC", F_B, 0x32, -1},
    {"LDC", F_C, 0x33, -1},
    {"LDC", F_IMM, 0x34, 0x30},
    {"LDC", F_ABS, 0x35, -1},
    {"LDC", F_IND_BC, 0x36, -1},
    {"PLC", F_NONE, 0x37, -1},
    {"CPCZ", F_NONE, 0x38, -1},
    {"CPC", F_A, 0x39, -1},
    {"CPC", F_B, 0x3A, -1},
    {"CPC", F_C, 0x3B, -1},
    {"CPC", F_IMM, 0x3C, 0x38},
    {"STC", F_ABS, 0x3D, -1},
    {"STC", F_IND_BC, 0x3E, -1},
    {"PHC", F_NONE, 0x3F, -1},
    {"EXD", F_NONE, 0x40, -1},
    {"JMPR", F_REL, 0x44, -1},
    {"JMP", F_ABS, 0x45, -1},
    {"JMP", F_IND_BC, 0x46, -1},
    {"EXE", F_NONE, 0x48, -1},
    {"JSRR", F_REL, 0x4C, -1},
    {"JSR", F_ABS, 0x4D, -1},
    {"JSR", F_IND_BC, 0x4E, -1},
    {"LDA", F_IND_DD, 0x50, -1},
    {"JPNZ", F_REL, 0x54, -1},
    {"JMPZ", F_ABS, 0x55, -1},
    {"JMPZ", F_IND_BC, 0x56, -1},
    {"STA", F_IND_DD, 0x58, -1},
    {"JSNZ", F_REL, 0x5C, -1},
    {"JSRZ", F_ABS, 0x5D, -1},
    {"JSRZ", F_IND_BC, 0x5E, -1},
    {"INC", F_DD, 0x60, -1},
    {"JMPP", F_REL, 0x64, -1},
    {"JMPN", F_ABS, 0x65, -1},
    {"JMPN", F_IND_BC, 0x66, -1},
    {"DEC", F_DD, 0x68, -1},
    {"JSRP", F_REL, 0x6C, -1},
    {"JSRN", F_ABS, 0x6D, -1},
    {"JSRN", F_IND_BC, 0x6E, -1},
    {"INC", F_EE, 0x70, -1},
    {"JPNC", F_REL, 0x74, -1},
    {"JMPC", F_ABS, 0x75, -1},
    {"JMPC", F_IND_BC, 0x76, -1},
    {"DEC", F_EE, 0x78, -1},
    {"JSNC", F_REL, 0x7C, -1},
    {"JSRC", F_ABS, 0x7D, -1},
    {"JSRC", F_IND_BC, 0x7E, -1},
    {"ADDZ", F_NONE, 0x80, -1},
    {"ADD", F_A, 0x81, -1},
    {"ADD", F_B, 0x82, -1},
    {"ADD", F_C, 0x83, -1},
    {"ADD", F_IMM, 0x84, 0x80},
    {"ADD", F_ABS, 0x85, -1},
    {"ADD", F_IND_BC, 0x86, -1},
    {"INC", F_A, 0x87, -1},
    {"ADCZ", F_NONE, 0x88, -1},
    {"ADC", F_A, 0x89, -1},
    {"ADC", F_B, 0x8A, -1},
    {"ADC", F_C, 0x8B, -1},
    {"ADC", F_IMM, 0x8C, 0x88},
    {"ADC", F_ABS, 0x8D, -1},
    {"ADC", F_IND_BC, 0x8E, -1},
    {"INC", F_B, 0x8F, -1},
    {"SUBZ", F_NONE, 0x90, -1},
    {"SUB", F_A, 0x91, -1},
    {"SUB", F_B, 0x92, -1},
    {"SUB", F_C, 0x93, -1},
    {"SUB", F_IMM, 0x94, 0x90},
    {"SUB", F_ABS, 0x95, -1},
    {"SUB", F_IND_BC, 0x96, -1},
    {"INC", F_C, 0x97, -1},
    {"SBCZ", F_NONE, 0x98, -1},
    {"SBC", F_A, 0x99, -1},
    {"SBC", F_B, 0x9A, -1},
    {"SBC", F_C, 0x9B, -1},
    {"SBC", F_IMM, 0x9C, 0x98},
    {"SBC", F_ABS, 0x9D, -1},
    {"SBC", F_IND_BC, 0x9E, -1},
    {"DEC", F_A, 0x9F, -1},
    {"LSR", F_A, 0xA1, -1},
    {"LSR", F_B, 0xA2, -1},
    {"LSR", F_C, 0xA3, -1},
    {"LSR", F_ABS, 0xA5, -1},
    {"LSR", F_IND_BC, 0xA6, -1},
    {"DEC", F_B, 0xA7, -1},
    {"ROR", F_A, 0xA9, -1},
    {"ROR", F_B, 0xAA, -1},
    {"ROR", F_C, 0xAB, -1},
    {"ROR", F_ABS, 0xAD, -1},
    {"ROR", F_IND_BC, 0xAE, -1},
    {"DEC", F_C, 0xAF, -1},
    {"ASL", F_A, 0xB1, -1},
    {"ASL", F_B, 0xB2, -1},
    {"ASL", F_C, 0xB3, -1},
    {"ASL", F_ABS, 0xB5, -1},
    {"ASL", F_IND_BC, 0xB6, -1},
    {"NEG", F_NONE, 0xB7, -1},
    {"ROL", F_A, 0xB9, -1},
    {"ROL", F_B, 0xBA, -1},
    {"ROL", F_C, 0xBB, -1},
    {"ROL", F_ABS, 0xBD, -1},
    {"ROL", F_IND_BC, 0xBE, -1},
    {"INC", F_IND_BC, 0xBF, -1},
    {"ORZ", F_NONE, 0xC0, -1},
    {"ORA", F_A, 0xC1, -1},
    {"ORA", F_B, 0xC2, -1},
    {"ORA", F_C, 0xC3, -1},
    {"ORA", F_IMM, 0xC4, 0xC0},
    {"ORA", F_ABS, 0xC5, -1},
    {"ORA", F_IND_BC, 0xC6, -1},
    {"INV", F_B, 0xC7, -1},
    {"NORZ", F_NONE, 0xC8, -1},
    {"NOR", F_A, 0xC9, -1},
    {"NOR", F_B, 0xCA, -1},
    {"NOR", F_C, 0xCB, -1},
    {"NOR", F_IMM, 0xCC, 0xC8},
    {"NOR", F_ABS, 0xCD, -1},
    {"NOR", F_IND_BC, 0xCE, -1},
    {"INV", F_C, 0xCF, -1},
    {"ANDZ", F_NONE, 0xD0, -1},
    {"AND", F_A, 0xD1, -1},
    {"AND", F_B, 0xD2, -1},
    {"AND", F_C, 0xD3, -1},
    {"AND", F_IMM, 0xD4, 0xD0},
    {"AND", F_ABS, 0xD5, -1},
    {"AND", F_IND_BC, 0xD6, -1},
    {"SED", F_NONE, 0xD7, -1},
    {"NNDZ", F_NONE, 0xD8, -1},
    {"NND", F_A, 0xD9, -1},
    {"NND", F_B, 0xDA, -1},
    {"NND", F_C, 0xDB, -1},
    {"NND", F_IMM, 0xDC, 0xD8},
    {"NND", F_ABS, 0xDD, -1},
    {"NND", F_IND_BC, 0xDE, -1},
    {"CLD", F_NONE, 0xDF, -1},
    {"XORZ", F_NONE, 0xE0, -1},
    {"XOR", F_A, 0xE1, -1},
    {"XOR", F_B, 0xE2, -1},
    {"XOR", F_C, 0xE3, -1},
    {"XOR", F_IMM, 0xE4, 0xE0},
    {"XOR", F_ABS, 0xE5, -1},
    {"XOR", F_IND_BC, 0xE6, -1},
    {"PHP", F_NONE, 0xE7, -1},
    {"XNRZ", F_NONE, 0xE8, -1},
    {"XNR", F_A, 0xE9, -1},
    {"XNR", F_B, 0xEA, -1},
    {"XNR", F_C, 0xEB, -1},
    {"XNR", F_IMM, 0xEC, 0xE8},
    {"XNR", F_ABS, 0xED, -1},
    {"XNR", F_IND_BC, 0xEE, -1},
    {"PLP", F_NONE, 0xEF, -1},
    {"SEI", F_NONE, 0xF0, -1},
    {"CLI", F_NONE, 0xF1, -1},
    {"RTS", F_NONE, 0xF2, -1},
    {"RTI", F_NONE, 0xF3, -1},
    {"HLT", F_NONE, 0xF4, -1},
    {"BRK", F_NONE, 0xF5, -1},
    {"RST", F_NONE, 0xF6, -1},
    {"LDS", F_ABS, 0xF7, -1},
    {"LDS", F_BC, 0xF8, -1},
    {"LDS", F_IND_BC, 0xF9, -1},
    {"LBCS", F_NONE, 0xFA, -1},
    {"CLC", F_NONE, 0xFB, -1},
    {"SEC", F_NONE, 0xFC, -1},
    {"INC", F_BC, 0xFD, -1},
    {"DEC", F_BC, 0xFE, -1},
};

#define NUM_OPCODES ((int)(sizeof(opcodes) / sizeof(opcodes[0])))

/* ------------------------------------------------------------------------- */
/* Source lines                                                              */
/* ------------------------------------------------------------------------- */

struct line {
    const char *file;
    int number;
    char *text;
    long addr;              /* address at start of line (final pass) */
    int count;              /* bytes emitted by this line (final pass) */
    int skip;               /* listed, not assembled (macro definitions and uses) */
    int hidden;             /* assembled, not listed (a label split from a macro use) */
    const char *macro;      /* macro this line was expanded from, or NULL */
    const char *use_file;   /* where the (outermost) macro was used */
    int use_number;
};

static struct line *raw_lines;  /* lines as read from the source files */
static int num_raw, cap_raw;
static struct line *lines;      /* lines after macro expansion */
static int num_lines, cap_lines;

static void *xrealloc(void *p, size_t size);

static void append_line(struct line **arr, int *num, int *cap, const struct line *ln)
{
    if (*num == *cap) {
        *cap = *cap ? *cap * 2 : 1024;
        *arr = xrealloc(*arr, (size_t)*cap * sizeof(**arr));
    }
    (*arr)[(*num)++] = *ln;
}

/* ------------------------------------------------------------------------- */
/* Symbols                                                                   */
/* ------------------------------------------------------------------------- */

struct symbol {
    char name[MAX_NAME];
    long value;
    int known;          /* value is valid */
    int pass;           /* pass in which it was last defined */
    int is_const;       /* defined with = rather than as a label */
};

static struct symbol *symbols;
static int num_symbols, cap_symbols;

/* ------------------------------------------------------------------------- */
/* Assembly state                                                            */
/* ------------------------------------------------------------------------- */

static unsigned char mem[65536];
static unsigned char written[65536];
static long pc;
static int pass;
static int final_pass;
static int changed;         /* a symbol changed value during this pass */
static int unresolved;      /* an unknown value was used during this pass */
static int errors;
static struct line *cur;
static int pc_overflow_reported;

static void fatal(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "r88asm: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    exit(1);
}

/* Report an error at a line. Errors in a macro expansion are reported where
   the macro was used, with the macro name and the line of its definition. */
static void report(const struct line *ln, const char *fmt, va_list ap)
{
    if (ln->macro)
        fprintf(stderr, "%s:%d: error: ", ln->use_file, ln->use_number);
    else
        fprintf(stderr, "%s:%d: error: ", ln->file, ln->number);
    vfprintf(stderr, fmt, ap);
    if (ln->macro)
        fprintf(stderr, " (in macro '%s', %s:%d)", ln->macro, ln->file, ln->number);
    fprintf(stderr, "\n");
    errors++;
}

/* Errors are only reported in the final pass, where every value is known */
static void error(const char *fmt, ...)
{
    va_list ap;
    if (!final_pass)
        return;
    va_start(ap, fmt);
    report(cur, fmt, ap);
    va_end(ap);
}

/* Errors found while reading the source and expanding macros */
static void line_error(const struct line *ln, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    report(ln, fmt, ap);
    va_end(ap);
}

static void *xrealloc(void *p, size_t size)
{
    p = realloc(p, size);
    if (!p)
        fatal("out of memory");
    return p;
}

static int ieq(const char *a, const char *b)
{
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b))
            return 0;
        a++;
        b++;
    }
    return *a == *b;
}

static int ident_start(int c) { return isalpha(c) || c == '_'; }
static int ident_char(int c) { return isalnum(c) || c == '_'; }

static const char *skip_ws(const char *p)
{
    while (*p == ' ' || *p == '\t')
        p++;
    return p;
}

/* Copy an identifier into buf; returns pointer past it, or NULL if none */
static const char *read_ident(const char *p, char *buf)
{
    int n = 0;
    if (!ident_start((unsigned char)*p))
        return NULL;
    while (ident_char((unsigned char)*p)) {
        if (n < MAX_NAME - 1)
            buf[n++] = *p;
        p++;
    }
    buf[n] = '\0';
    return p;
}

static struct symbol *find_symbol(const char *name)
{
    int i;
    for (i = 0; i < num_symbols; i++)
        if (strcmp(symbols[i].name, name) == 0)
            return &symbols[i];
    return NULL;
}

static void define_symbol(const char *name, long value, int known, int is_const)
{
    struct symbol *s = find_symbol(name);
    if (!s) {
        if (num_symbols == cap_symbols) {
            cap_symbols = cap_symbols ? cap_symbols * 2 : 256;
            symbols = xrealloc(symbols, (size_t)cap_symbols * sizeof(*symbols));
        }
        s = &symbols[num_symbols++];
        memset(s, 0, sizeof(*s));
        strncpy(s->name, name, MAX_NAME - 1);
    }
    if (s->pass == pass) {
        /* defined again in the same pass: only an identical constant is allowed */
        if (!(is_const && s->is_const && known && s->known && s->value == value))
            error("'%s' is already defined", name);
        return;
    }
    if (!known || !s->known || s->value != value)
        changed = 1;
    if (!known)
        unresolved = 1;
    s->value = value;
    s->known = known;
    s->pass = pass;
    s->is_const = is_const;
}

/* ------------------------------------------------------------------------- */
/* Expressions                                                               */
/* ------------------------------------------------------------------------- */

struct value {
    long v;
    int known;
};

static const char *ep;      /* expression cursor */
static int expr_failed;

static void expr_error(const char *msg)
{
    if (!expr_failed)
        error("%s", msg);
    expr_failed = 1;
}

static struct value parse_or(void);

static int digit_value(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    c = tolower(c);
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return 99;
}

static struct value parse_number(int base)
{
    struct value r = {0, 1};
    int digits = 0;
    while (digit_value((unsigned char)*ep) < base) {
        r.v = r.v * base + digit_value((unsigned char)*ep);
        ep++;
        digits++;
    }
    if (!digits || ident_char((unsigned char)*ep))
        expr_error("invalid number");
    return r;
}

static int parse_char_escape(const char **pp)
{
    const char *p = *pp;
    int c = (unsigned char)*p++;
    if (c == '\\') {
        c = (unsigned char)*p++;
        switch (c) {
        case 'n': c = '\n'; break;
        case 'r': c = '\r'; break;
        case 't': c = '\t'; break;
        case '0': c = 0; break;
        default: break;     /* \\ \' \" */
        }
    }
    *pp = p;
    return c;
}

static struct value parse_primary(void)
{
    struct value r = {0, 1};
    ep = skip_ws(ep);
    if (*ep == '(') {
        ep++;
        r = parse_or();
        ep = skip_ws(ep);
        if (*ep != ')')
            expr_error("missing ')'");
        else
            ep++;
    } else if (*ep == '$') {
        ep++;
        r = parse_number(16);
    } else if (ep[0] == '0' && (ep[1] == 'x' || ep[1] == 'X')) {
        ep += 2;
        r = parse_number(16);
    } else if (*ep == '%') {
        ep++;
        r = parse_number(2);
    } else if (isdigit((unsigned char)*ep)) {
        r = parse_number(10);
    } else if (*ep == '\'') {
        ep++;
        if (*ep == '\0' || *ep == '\'') {
            expr_error("empty character constant");
        } else {
            r.v = parse_char_escape(&ep);
            if (*ep != '\'')
                expr_error("missing closing '");
            else
                ep++;
        }
    } else if (*ep == '*') {
        ep++;
        r.v = pc;
    } else {
        expr_error("expected a value");
    }
    return r;
}

/* Primary with symbol lookup and .low / .high suffix */
static struct value parse_postfix(void)
{
    struct value r;
    char name[MAX_NAME];
    const char *after;
    ep = skip_ws(ep);
    after = read_ident(ep, name);
    if (after) {
        struct symbol *s = find_symbol(name);
        ep = after;
        if (s && s->known) {
            r.v = s->value;
            r.known = 1;
        } else {
            r.v = 0;
            r.known = 0;
            unresolved = 1;
            if (final_pass && !expr_failed) {
                error("undefined symbol '%s'", name);
                expr_failed = 1;
            }
        }
    } else {
        r = parse_primary();
    }
    /* .low / .high */
    if (*ep == '.') {
        char suffix[MAX_NAME];
        const char *p = read_ident(ep + 1, suffix);
        if (p && ieq(suffix, "low")) {
            r.v &= 0xFF;
            ep = p;
        } else if (p && ieq(suffix, "high")) {
            r.v = (r.v >> 8) & 0xFF;
            ep = p;
        } else {
            expr_error("expected .low or .high");
        }
    }
    return r;
}

static struct value parse_unary(void)
{
    struct value r;
    ep = skip_ws(ep);
    if (*ep == '-') {
        ep++;
        r = parse_unary();
        r.v = -r.v;
    } else if (*ep == '+') {
        ep++;
        r = parse_unary();
    } else if (*ep == '~') {
        ep++;
        r = parse_unary();
        r.v = ~r.v & 0xFFFF;
    } else {
        r = parse_postfix();
    }
    return r;
}

static struct value combine(struct value a, struct value b, long v)
{
    struct value r;
    r.v = v;
    r.known = a.known && b.known;
    return r;
}

static struct value parse_mul(void)
{
    struct value a = parse_unary(), b;
    for (;;) {
        ep = skip_ws(ep);
        if (*ep == '*') {
            ep++;
            b = parse_unary();
            a = combine(a, b, a.v * b.v);
        } else if (*ep == '/') {
            ep++;
            b = parse_unary();
            if (b.known && b.v == 0) {
                if (a.known)
                    expr_error("division by zero");
                a = combine(a, b, 0);
            } else {
                a = combine(a, b, b.v ? a.v / b.v : 0);
            }
        } else {
            return a;
        }
    }
}

static struct value parse_add(void)
{
    struct value a = parse_mul(), b;
    for (;;) {
        ep = skip_ws(ep);
        if (*ep == '+') {
            ep++;
            b = parse_mul();
            a = combine(a, b, a.v + b.v);
        } else if (*ep == '-') {
            ep++;
            b = parse_mul();
            a = combine(a, b, a.v - b.v);
        } else {
            return a;
        }
    }
}

static struct value parse_shift(void)
{
    struct value a = parse_add(), b;
    for (;;) {
        ep = skip_ws(ep);
        if (ep[0] == '<' && ep[1] == '<') {
            ep += 2;
            b = parse_add();
            a = combine(a, b, (b.v >= 0 && b.v < 32) ? a.v << b.v : 0);
        } else if (ep[0] == '>' && ep[1] == '>') {
            ep += 2;
            b = parse_add();
            a = combine(a, b, (b.v >= 0 && b.v < 32) ? a.v >> b.v : 0);
        } else {
            return a;
        }
    }
}

static struct value parse_and(void)
{
    struct value a = parse_shift(), b;
    for (;;) {
        ep = skip_ws(ep);
        if (*ep != '&')
            return a;
        ep++;
        b = parse_shift();
        a = combine(a, b, a.v & b.v);
    }
}

static struct value parse_xor(void)
{
    struct value a = parse_and(), b;
    for (;;) {
        ep = skip_ws(ep);
        if (*ep != '^')
            return a;
        ep++;
        b = parse_and();
        a = combine(a, b, a.v ^ b.v);
    }
}

static struct value parse_or(void)
{
    struct value a = parse_xor(), b;
    for (;;) {
        ep = skip_ws(ep);
        if (*ep != '|')
            return a;
        ep++;
        b = parse_xor();
        a = combine(a, b, a.v | b.v);
    }
}

/* Evaluate a whole expression string */
static struct value eval(const char *s)
{
    struct value r;
    ep = s;
    expr_failed = 0;
    r = parse_or();
    ep = skip_ws(ep);
    if (*ep != '\0')
        expr_error("unexpected text in expression");
    if (expr_failed)
        r.known = final_pass ? 1 : r.known;
    return r;
}

/* ------------------------------------------------------------------------- */
/* Output                                                                    */
/* ------------------------------------------------------------------------- */

static void emit(long byte)
{
    if (pc > 0xFFFF) {
        if (!pc_overflow_reported)
            error("address past $FFFF");
        pc_overflow_reported = 1;
        pc++;
        return;
    }
    if (final_pass) {
        if (written[pc])
            error("address $%04lX is written more than once", pc);
        mem[pc] = (unsigned char)(byte & 0xFF);
        written[pc] = 1;
        cur->count++;
    }
    pc++;
}

static void emit_byte(struct value v)
{
    if (v.known && (v.v < -128 || v.v > 255))
        error("value %ld does not fit in a byte", v.v);
    emit(v.v);
}

static void emit_word(struct value v)
{
    if (v.known && (v.v < -32768 || v.v > 65535))
        error("value %ld does not fit in 16 bits", v.v);
    emit(v.v);
    emit(v.v >> 8);
}

/* ------------------------------------------------------------------------- */
/* Directives and instructions                                               */
/* ------------------------------------------------------------------------- */

/* Split a comma-separated list, respecting quotes and parentheses.
   Returns the number of items; items point into buf. */
static int split_list(char *buf, char **items, int max)
{
    int n = 0, depth = 0;
    char quote = 0;
    char *p = buf, *start = buf;
    for (;; p++) {
        if (quote) {
            if (*p == '\\' && p[1])
                p++;
            else if (*p == quote)
                quote = 0;
            else if (*p == '\0')
                break;
            continue;
        }
        if (*p == '"' || *p == '\'') {
            quote = *p;
        } else if (*p == '(') {
            depth++;
        } else if (*p == ')') {
            depth--;
        } else if ((*p == ',' && depth == 0) || *p == '\0') {
            int end = (*p == '\0');
            char *e = p;
            *p = '\0';
            while (*start == ' ' || *start == '\t')
                start++;
            while (e > start && (e[-1] == ' ' || e[-1] == '\t'))
                *--e = '\0';
            if (n < max)
                items[n++] = start;
            if (end)
                break;
            start = p + 1;
        }
    }
    return n;
}

static void directive(const char *p)
{
    char name[MAX_NAME];
    char args[MAX_LINE];
    char *items[256];
    int n, i;
    const char *rest = read_ident(p + 1, name);

    if (!rest) {
        error("expected a directive name after '.'");
        return;
    }
    strncpy(args, skip_ws(rest), MAX_LINE - 1);
    args[MAX_LINE - 1] = '\0';

    if (ieq(name, "org")) {
        struct value v = eval(args);
        if (!v.known) {
            error(".org address must be known before it is used");
            return;
        }
        if (v.v < 0 || v.v > 0xFFFF)
            error(".org address $%lX is out of range", v.v);
        else
            pc = v.v;
        pc_overflow_reported = 0;
    } else if (ieq(name, "byte") || ieq(name, "db")) {
        n = split_list(args, items, 256);
        if (n == 0 || (n == 1 && items[0][0] == '\0'))
            error(".byte needs at least one value");
        for (i = 0; i < n; i++) {
            if (items[i][0] == '"') {
                const char *s = items[i] + 1;
                while (*s && *s != '"')
                    emit(parse_char_escape(&s));
                if (*s != '"' || s[1] != '\0')
                    error("bad string %s", items[i]);
            } else {
                emit_byte(eval(items[i]));
            }
        }
    } else if (ieq(name, "word") || ieq(name, "addr") || ieq(name, "dw")) {
        n = split_list(args, items, 256);
        if (n == 0 || (n == 1 && items[0][0] == '\0'))
            error(".%s needs at least one value", name);
        for (i = 0; i < n; i++)
            emit_word(eval(items[i]));
    } else if (ieq(name, "fill")) {
        struct value count, value = {0, 1};
        n = split_list(args, items, 3);
        if (n < 1 || n > 2) {
            error(".fill needs a count and an optional value");
            return;
        }
        count = eval(items[0]);
        if (n == 2)
            value = eval(items[1]);
        if (!count.known) {
            error(".fill count must be known before it is used");
            return;
        }
        if (count.v < 0 || count.v > 65536) {
            error(".fill count %ld is out of range", count.v);
            return;
        }
        for (i = 0; i < count.v; i++)
            emit_byte(value);
    } else {
        error("unknown directive .%s", name);
    }
}

static const struct opcode *find_opcode(const char *mnemonic, enum form form, int *mnemonic_exists)
{
    int i;
    *mnemonic_exists = 0;
    for (i = 0; i < NUM_OPCODES; i++) {
        if (ieq(opcodes[i].mnemonic, mnemonic)) {
            *mnemonic_exists = 1;
            if (opcodes[i].form == form)
                return &opcodes[i];
        }
    }
    return NULL;
}

/* Is the operand exactly one of the register names, ignoring case and spaces? */
static int operand_is(const char *operand, const char *name)
{
    const char *a = operand, *b = name;
    for (;;) {
        while (*a == ' ' || *a == '\t')
            a++;
        if (!*a || !*b)
            return !*a && !*b;
        if (tolower((unsigned char)*a) != *b)
            return 0;
        a++;
        b++;
    }
}

static void instruction(const char *p)
{
    char mnemonic[MAX_NAME];
    const char *operand;
    const struct opcode *op;
    enum form form;
    int exists;
    struct value v = {0, 1};
    long start = pc;

    operand = read_ident(p, mnemonic);
    if (!operand) {
        error("expected an instruction");
        return;
    }
    operand = skip_ws(operand);

    if (*operand == '\0') form = F_NONE;
    else if (operand_is(operand, "a")) form = F_A;
    else if (operand_is(operand, "b")) form = F_B;
    else if (operand_is(operand, "c")) form = F_C;
    else if (operand_is(operand, "bc")) form = F_BC;
    else if (operand_is(operand, "dd")) form = F_DD;
    else if (operand_is(operand, "ee")) form = F_EE;
    else if (operand_is(operand, "(bc)")) form = F_IND_BC;
    else if (operand_is(operand, "(dd)")) form = F_IND_DD;
    else if (*operand == '#') form = F_IMM;
    else {
        /* an address: relative if this mnemonic has a relative form */
        form = find_opcode(mnemonic, F_REL, &exists) ? F_REL : F_ABS;
    }

    op = find_opcode(mnemonic, form, &exists);
    if (!op) {
        if (!exists)
            error("unknown instruction '%s'", mnemonic);
        else
            error("'%s' does not support the operand '%s'", mnemonic, operand);
        return;
    }

    switch (form) {
    case F_IMM:
        v = eval(operand + 1);
        if (op->zero_op >= 0 && v.known && v.v == 0) {
            emit(op->zero_op);      /* "#0" uses the Zero mode opcode */
        } else {
            emit(op->op);
            emit_byte(v);
        }
        break;
    case F_ABS:
        v = eval(operand);
        emit(op->op);
        emit_word(v);
        break;
    case F_REL: {
        long offset;
        v = eval(operand);
        offset = v.v - (start + 2);
        if (v.known && (offset < -128 || offset > 127))
            error("relative target is out of range (offset %ld)", offset);
        emit(op->op);
        emit(offset);
        break;
    }
    default:
        emit(op->op);
        break;
    }
}

/* ------------------------------------------------------------------------- */
/* Lines and passes                                                          */
/* ------------------------------------------------------------------------- */

/* Copy a line without its comment (a ';' outside of quotes), trimmed */
static void strip_line(const char *src, char *dst)
{
    char quote = 0;
    char *d = dst;
    for (; *src; src++) {
        if (quote) {
            if (*src == '\\' && src[1]) {
                *d++ = *src++;
            } else if (*src == quote) {
                quote = 0;
            }
        } else if (*src == '"' || *src == '\'') {
            quote = *src;
        } else if (*src == ';') {
            break;
        }
        *d++ = *src;
    }
    *d = '\0';
    while (d > dst && isspace((unsigned char)d[-1]))
        *--d = '\0';
}

static void process_line(struct line *ln)
{
    char text[MAX_LINE];
    char name[MAX_NAME];
    const char *p, *q;

    cur = ln;
    if (final_pass) {
        ln->addr = pc;
        ln->count = 0;
    }
    if (ln->skip)
        return;
    strip_line(ln->text, text);
    p = skip_ws(text);

    /* label: */
    q = read_ident(p, name);
    if (q && *skip_ws(q) == ':') {
        define_symbol(name, pc, 1, 0);
        p = skip_ws(skip_ws(q) + 1);
    } else if (q && *skip_ws(q) == '=' && skip_ws(q)[1] != '=') {
        /* NAME = expression */
        struct value v = eval(skip_ws(q) + 1);
        define_symbol(name, v.v, v.known, 1);
        return;
    }

    if (*p == '\0')
        return;
    if (*p == '@') {
        error("@ labels can only be used inside a macro");
        return;
    }
    if (*p == '.')
        directive(p);
    else
        instruction(p);
}

static void run_pass(void)
{
    int i;
    pass++;
    pc = 0;
    changed = 0;
    unresolved = 0;
    pc_overflow_reported = 0;
    for (i = 0; i < num_lines; i++)
        process_line(&lines[i]);
}

static void assemble(void)
{
    int i;
    for (i = 0; i < MAX_PASSES; i++) {
        run_pass();
        if (!changed && !unresolved)
            break;
    }
    final_pass = 1;
    run_pass();
    if (changed && errors == 0) {
        cur = &lines[num_lines - 1];
        error("addresses did not settle after %d passes", MAX_PASSES);
    }
}

static void read_source(const char *path)
{
    FILE *f = fopen(path, "rb");
    char buf[MAX_LINE + 2];
    int number = 0;
    if (!f)
        fatal("can't open %s", path);
    while (fgets(buf, sizeof(buf), f)) {
        size_t len = strlen(buf);
        number++;
        if (len == sizeof(buf) - 1 && buf[len - 1] != '\n')
            fatal("%s:%d: line is longer than %d characters", path, number, MAX_LINE);
        while (len && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
            buf[--len] = '\0';
        {
            struct line ln;
            memset(&ln, 0, sizeof(ln));
            ln.file = path;
            ln.number = number;
            ln.text = xrealloc(NULL, len + 1);
            memcpy(ln.text, buf, len + 1);
            append_line(&raw_lines, &num_raw, &cap_raw, &ln);
        }
    }
    fclose(f);
}

/* ------------------------------------------------------------------------- */
/* Macros                                                                    */
/*                                                                           */
/*   .macro NAME [param, ...]                                                */
/*       ...body, using the parameters...                                    */
/*   .endmacro                       (or .endm)                              */
/*                                                                           */
/*   NAME [argument, ...]                                                    */
/*                                                                           */
/* Each use is replaced by the body, with every parameter replaced by the    */
/* text of its argument. An argument that is an expression (anything but a   */
/* single name or number, a "string", a #value or something already in      */
/* parentheses) is put in parentheses, so it keeps its meaning inside a      */
/* larger expression. Labels written @name in a body are made unique to each */
/* use of the macro. Macros may use other macros, but not themselves.        */
/* ------------------------------------------------------------------------- */

#define MAX_MACRO_DEPTH 64

struct macro {
    char name[MAX_NAME];
    char (*params)[MAX_NAME];
    int num_params;
    int first, count;           /* body: raw_lines[first .. first+count-1] */
    const struct line *def;
    int expanding;              /* guards against a macro using itself */
};

static struct macro *macros;
static int num_macros, cap_macros;
static int expansion_count;

static struct macro *find_macro(const char *name)
{
    int i;
    for (i = 0; i < num_macros; i++)
        if (strcmp(macros[i].name, name) == 0)
            return &macros[i];
    return NULL;
}

/* If the line (without comment) is the directive .name, return what follows it */
static const char *is_directive(const char *text, const char *name)
{
    char word[MAX_NAME];
    const char *p = skip_ws(text), *q;
    if (*p != '.')
        return NULL;
    q = read_ident(p + 1, word);
    if (!q || !ieq(word, name) || (*q && *q != ' ' && *q != '\t'))
        return NULL;
    return skip_ws(q);
}

static int is_register_name(const char *s)
{
    return ieq(s, "a") || ieq(s, "b") || ieq(s, "c") ||
           ieq(s, "bc") || ieq(s, "dd") || ieq(s, "ee");
}

static int is_mnemonic(const char *s)
{
    int i;
    for (i = 0; i < NUM_OPCODES; i++)
        if (ieq(opcodes[i].mnemonic, s))
            return 1;
    return 0;
}

/* Find the .macro definitions in raw_lines and mark their lines to skip */
static void collect_macros(void)
{
    int i;
    char text[MAX_LINE];
    for (i = 0; i < num_raw; i++) {
        const struct line *ln = &raw_lines[i];
        const char *rest, *after;
        char name[MAX_NAME];
        char params[MAX_LINE];
        char *items[MAX_LINE / 2];
        struct macro *m;
        int n, j, k, end;

        strip_line(ln->text, text);
        if (is_directive(text, "endmacro") || is_directive(text, "endm")) {
            line_error(ln, ".endmacro without .macro");
            continue;
        }
        rest = is_directive(text, "macro");
        if (!rest)
            continue;

        /* find the end of the definition */
        end = -1;
        for (j = i + 1; j < num_raw; j++) {
            strip_line(raw_lines[j].text, text);
            if (is_directive(text, "endmacro") || is_directive(text, "endm")) {
                end = j;
                break;
            }
            if (is_directive(text, "macro")) {
                line_error(&raw_lines[j], "a macro can't be defined inside another macro");
                break;
            }
        }
        if (end < 0) {
            line_error(ln, ".macro without .endmacro");
            for (j = i; j < num_raw; j++)
                raw_lines[j].skip = 1;
            return;
        }
        for (j = i; j <= end; j++)
            raw_lines[j].skip = 1;

        strip_line(ln->text, text);
        rest = is_directive(text, "macro");
        after = read_ident(rest, name);
        if (!after) {
            line_error(ln, ".macro needs a name");
            i = end;
            continue;
        }
        if (is_mnemonic(name) || find_macro(name)) {
            line_error(ln, is_mnemonic(name) ? "'%s' is an instruction, so it can't be a macro name"
                                              : "macro '%s' is already defined", name);
            i = end;
            continue;
        }

        if (num_macros == cap_macros) {
            cap_macros = cap_macros ? cap_macros * 2 : 32;
            macros = xrealloc(macros, (size_t)cap_macros * sizeof(*macros));
        }
        m = &macros[num_macros++];
        memset(m, 0, sizeof(*m));
        strcpy(m->name, name);
        m->first = i + 1;
        m->count = end - i - 1;
        m->def = ln;

        /* parameters */
        strcpy(params, skip_ws(after));
        n = params[0] ? split_list(params, items, MAX_LINE / 2) : 0;
        m->params = xrealloc(NULL, (size_t)(n ? n : 1) * sizeof(*m->params));
        for (j = 0; j < n; j++) {
            char pname[MAX_NAME];
            const char *pend = read_ident(items[j], pname);
            if (!pend || *pend) {
                line_error(ln, "bad macro parameter '%s'", items[j]);
                continue;
            }
            if (is_register_name(pname)) {
                line_error(ln, "'%s' is a register, so it can't be a parameter name", pname);
                continue;
            }
            for (k = 0; k < m->num_params; k++)
                if (strcmp(m->params[k], pname) == 0)
                    break;
            if (k < m->num_params) {
                line_error(ln, "parameter '%s' is listed twice", pname);
                continue;
            }
            strcpy(m->params[m->num_params++], pname);
        }
        i = end;
    }
}

/* Is the argument a single token, a string, a #value, or fully parenthesized?
   If not, it's an expression that gets parentheses when substituted. */
static int simple_argument(const char *a)
{
    const char *p;
    if (a[0] == '#' || a[0] == '"' || a[0] == '\'')
        return 1;
    if (a[0] == '(') {
        int depth = 0;
        for (p = a; *p; p++) {
            if (*p == '(')
                depth++;
            else if (*p == ')' && --depth == 0)
                return p[1] == '\0';
        }
        return 0;
    }
    for (p = a; *p; p++)
        if (!ident_char((unsigned char)*p) && *p != '$' && *p != '%')
            return 0;
    return 1;
}

/* Append s to the output buffer; returns 0 if it doesn't fit */
static int put(char *out, size_t *len, size_t size, const char *s)
{
    size_t n = strlen(s);
    if (*len + n >= size)
        return 0;
    memcpy(out + *len, s, n + 1);
    *len += n;
    return 1;
}

/* Substitute a macro's arguments and local labels into one body line */
static int substitute(const char *src, const struct macro *m, char **args, int id,
                      char *out, size_t size)
{
    size_t len = 0;
    char quote = 0;
    char name[MAX_NAME];
    char tmp[MAX_NAME + 32];
    int prev = 0;
    const char *p = src;
    out[0] = '\0';
    while (*p) {
        if (quote) {
            char c[3] = {0, 0, 0};
            c[0] = *p;
            if (*p == '\\' && p[1])
                c[1] = *++p;
            else if (*p == quote)
                quote = 0;
            p++;
            if (!put(out, &len, size, c))
                return 0;
            prev = 0;
            continue;
        }
        if (*p == ';')
            return put(out, &len, size, p);
        if (*p == '"' || *p == '\'') {
            char c[2] = {0, 0};
            c[0] = quote = *p++;
            if (!put(out, &len, size, c))
                return 0;
            continue;
        }
        if (*p == '@' && ident_start((unsigned char)p[1]) && !ident_char(prev)) {
            /* local label: unique to this use of the macro */
            p = read_ident(p + 1, name);
            sprintf(tmp, "__%s_%d", name, id);
            if (!put(out, &len, size, tmp))
                return 0;
            prev = 'x';
            continue;
        }
        if (ident_start((unsigned char)*p) && !ident_char(prev) && prev != '.') {
            int i;
            const char *text = name;
            p = read_ident(p, name);
            for (i = 0; i < m->num_params; i++)
                if (strcmp(m->params[i], name) == 0)
                    break;
            if (i < m->num_params) {
                if (simple_argument(args[i])) {
                    text = args[i];
                } else {
                    if (!put(out, &len, size, "("))
                        return 0;
                    if (!put(out, &len, size, args[i]))
                        return 0;
                    text = ")";
                }
            }
            if (!put(out, &len, size, text))
                return 0;
            prev = 'x';
            continue;
        }
        if (*p == '$' || *p == '%' || isdigit((unsigned char)*p)) {
            /* a number: copy it whole, so its digits aren't taken for names */
            const char *start = p++;
            char num[MAX_LINE];
            while (ident_char((unsigned char)*p))
                p++;
            if ((size_t)(p - start) >= sizeof(num))
                return 0;
            memcpy(num, start, (size_t)(p - start));
            num[p - start] = '\0';
            if (!put(out, &len, size, num))
                return 0;
            prev = 'x';
            continue;
        }
        {
            char c[2] = {0, 0};
            c[0] = *p++;
            if (!put(out, &len, size, c))
                return 0;
            prev = (unsigned char)c[0];
        }
    }
    return 1;
}

static void expand_line(const struct line *ln, int depth);

/* Expand one use of a macro, with the argument text after its name */
static void use_macro(struct macro *m, const char *argtext, const struct line *at, int depth)
{
    char buf[MAX_LINE];
    char *args[MAX_LINE / 2];
    int n, i, id;

    if (m->expanding) {
        line_error(at, "macro '%s' uses itself", m->name);
        return;
    }
    if (depth >= MAX_MACRO_DEPTH) {
        line_error(at, "macros are nested more than %d deep", MAX_MACRO_DEPTH);
        return;
    }
    strcpy(buf, argtext);
    n = buf[0] ? split_list(buf, args, MAX_LINE / 2) : 0;
    if (n != m->num_params) {
        line_error(at, "macro '%s' takes %d argument%s, but %d %s given", m->name, m->num_params,
                   m->num_params == 1 ? "" : "s", n, n == 1 ? "was" : "were");
        return;
    }
    for (i = 0; i < n; i++) {
        if (args[i][0] == '\0') {
            line_error(at, "argument %d of macro '%s' is empty", i + 1, m->name);
            return;
        }
    }

    id = ++expansion_count;
    m->expanding = 1;
    for (i = 0; i < m->count; i++) {
        const struct line *body = &raw_lines[m->first + i];
        char text[MAX_LINE];
        struct line ln;
        if (!substitute(body->text, m, args, id, text, sizeof(text))) {
            memset(&ln, 0, sizeof(ln));
            ln = *body;
            ln.macro = m->name;
            ln.use_file = at->macro ? at->use_file : at->file;
            ln.use_number = at->macro ? at->use_number : at->number;
            line_error(&ln, "line is longer than %d characters after substituting arguments", MAX_LINE - 1);
            continue;
        }
        memset(&ln, 0, sizeof(ln));
        ln.file = body->file;
        ln.number = body->number;
        ln.text = xrealloc(NULL, strlen(text) + 1);
        strcpy(ln.text, text);
        ln.macro = m->name;
        ln.use_file = at->macro ? at->use_file : at->file;
        ln.use_number = at->macro ? at->use_number : at->number;
        expand_line(&ln, depth + 1);
    }
    m->expanding = 0;
}

/* Append a line to the program, expanding it if it uses a macro */
static void expand_line(const struct line *ln, int depth)
{
    char text[MAX_LINE];
    char name[MAX_NAME];
    const char *p, *q, *word;
    struct macro *m;

    if (ln->skip) {
        append_line(&lines, &num_lines, &cap_lines, ln);
        return;
    }
    strip_line(ln->text, text);
    p = skip_ws(text);
    word = p;
    q = read_ident(p, name);
    if (q && *skip_ws(q) == ':') {
        word = skip_ws(skip_ws(q) + 1);
        q = read_ident(word, name);
    }
    if (!q || (*q && *q != ' ' && *q != '\t') || !(m = find_macro(name))) {
        append_line(&lines, &num_lines, &cap_lines, ln);
        return;
    }
    if (word != p) {
        /* keep a label in front of the macro, on its own line */
        struct line label = *ln;
        size_t len = (size_t)(word - p);
        label.hidden = 1;
        label.text = xrealloc(NULL, len + 1);
        memcpy(label.text, p, len);
        label.text[len] = '\0';
        append_line(&lines, &num_lines, &cap_lines, &label);
    }
    {
        /* list the use of the macro itself, then its expansion */
        struct line use = *ln;
        use.skip = 1;
        if (word != p) {
            use.text = xrealloc(NULL, strlen(ln->text) + 1);
            strcpy(use.text, ln->text);
        }
        append_line(&lines, &num_lines, &cap_lines, &use);
    }
    use_macro(m, skip_ws(q), ln, depth);
}

static void expand_macros(void)
{
    int i;
    collect_macros();
    for (i = 0; i < num_raw; i++)
        expand_line(&raw_lines[i], 0);
}

/* ------------------------------------------------------------------------- */
/* Output files                                                              */
/* ------------------------------------------------------------------------- */

static int used_range(long *lo, long *hi)
{
    long a;
    *lo = -1;
    *hi = -1;
    for (a = 0; a < 65536; a++) {
        if (written[a]) {
            if (*lo < 0)
                *lo = a;
            *hi = a;
        }
    }
    return *lo >= 0;
}

static void write_bin(FILE *f, int pad)
{
    long lo, hi, a;
    if (!used_range(&lo, &hi))
        return;
    for (a = lo; a <= hi; a++)
        fputc(written[a] ? mem[a] : pad, f);
}

static void write_hex(FILE *f)
{
    long a = 0;
    while (a < 65536) {
        int n = 0, sum, i;
        if (!written[a]) {
            a++;
            continue;
        }
        while (n < 16 && a + n < 65536 && written[a + n])
            n++;
        sum = n + (int)((a >> 8) & 0xFF) + (int)(a & 0xFF);
        fprintf(f, ":%02X%04lX00", n, a);
        for (i = 0; i < n; i++) {
            fprintf(f, "%02X", mem[a + i]);
            sum += mem[a + i];
        }
        fprintf(f, "%02X\n", (-sum) & 0xFF);
        a += n;
    }
    fprintf(f, ":00000001FF\n");
}

static void write_mem(FILE *f)
{
    long a = 0;
    int col = 0;
    int in_run = 0;
    for (a = 0; a < 65536; a++) {
        if (!written[a]) {
            if (in_run && col)
                fputc('\n', f);
            in_run = 0;
            col = 0;
            continue;
        }
        if (!in_run)
            fprintf(f, "@%04lx\n", a);
        in_run = 1;
        fprintf(f, col ? " %02x" : "%02x", mem[a]);
        if (++col == 16) {
            fputc('\n', f);
            col = 0;
        }
    }
    if (in_run && col)
        fputc('\n', f);
}

static void write_listing(FILE *f)
{
    int i, j;
    for (i = 0; i < num_lines; i++) {
        struct line *ln = &lines[i];
        char bytes[3 * 4 + 1];
        char number[16];
        int shown = 0;
        if (ln->hidden)
            continue;
        /* lines from a macro are numbered by where it was used, marked + */
        if (ln->macro)
            sprintf(number, "%5d+", ln->use_number);
        else
            sprintf(number, "%5d ", ln->number);
        do {
            bytes[0] = '\0';
            for (j = 0; j < 4 && shown + j < ln->count; j++)
                sprintf(bytes + 3 * j, "%02X ", mem[(ln->addr + shown + j) & 0xFFFF]);
            if (shown == 0)
                fprintf(f, "%s %04lX  %-12s  %s\n", number, ln->addr & 0xFFFF, bytes, ln->text);
            else
                fprintf(f, "       %04lX  %-12s\n", (ln->addr + shown) & 0xFFFF, bytes);
            shown += 4;
        } while (shown < ln->count);
    }
    fprintf(f, "\nSymbols:\n");
    for (i = 0; i < num_symbols; i++)
        fprintf(f, "  %-24s $%04lX%s\n", symbols[i].name, symbols[i].value & 0xFFFF,
                symbols[i].is_const ? "  (constant)" : "");
}

static FILE *open_output(const char *path, const char *mode)
{
    FILE *f = fopen(path, mode);
    if (!f)
        fatal("can't create %s", path);
    return f;
}

static void usage(FILE *f)
{
    fprintf(f,
        "r88asm " VERSION " - ROCKET88 assembler\n"
        "usage: r88asm [options] input.asm [more.asm ...]\n"
        "  -o <file>    output file (default: first input with .bin/.hex/.mem)\n"
        "  -f <format>  bin: raw binary from lowest to highest address (default)\n"
        "               hex: Intel HEX\n"
        "               mem: Verilog $readmemh image\n"
        "  -l <file>    write a listing\n"
        "  -p <byte>    pad value for gaps in bin output (default 0)\n"
        "  -h           show this help\n");
}

static char *default_output(const char *input, const char *ext)
{
    size_t len = strlen(input);
    const char *dot = strrchr(input, '.');
    const char *slash1 = strrchr(input, '/');
    const char *slash2 = strrchr(input, '\\');
    char *out;
    if (dot && (!slash1 || dot > slash1) && (!slash2 || dot > slash2))
        len = (size_t)(dot - input);
    out = xrealloc(NULL, len + strlen(ext) + 1);
    memcpy(out, input, len);
    strcpy(out + len, ext);
    return out;
}

int main(int argc, char **argv)
{
    const char *format = "bin";
    const char *output = NULL;
    const char *listing = NULL;
    int pad = 0;
    int i, inputs = 0;
    const char *first_input = NULL;
    FILE *f;

    for (i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
            usage(stdout);
            return 0;
        } else if (strcmp(a, "--version") == 0) {
            printf("r88asm " VERSION "\n");
            return 0;
        } else if (strcmp(a, "-o") == 0 || strcmp(a, "-f") == 0 ||
                   strcmp(a, "-l") == 0 || strcmp(a, "-p") == 0) {
            if (i + 1 >= argc)
                fatal("%s needs a value", a);
            if (a[1] == 'o') output = argv[++i];
            else if (a[1] == 'f') format = argv[++i];
            else if (a[1] == 'l') listing = argv[++i];
            else {
                char *end;
                long v = strtol(argv[++i], &end, 0);
                if (*end || v < 0 || v > 255)
                    fatal("-p needs a byte value");
                pad = (int)v;
            }
        } else if (a[0] == '-' && a[1] != '\0') {
            usage(stderr);
            fatal("unknown option %s", a);
        } else {
            if (!first_input)
                first_input = a;
            read_source(a);
            inputs++;
        }
    }
    if (!inputs) {
        usage(stderr);
        return 1;
    }
    expand_macros();
    if (strcmp(format, "bin") && strcmp(format, "hex") && strcmp(format, "mem"))
        fatal("unknown format '%s' (use bin, hex or mem)", format);
    if (num_lines && !errors)
        assemble();
    if (errors) {
        fprintf(stderr, "r88asm: %d error%s, no output written\n", errors, errors == 1 ? "" : "s");
        return 1;
    }

    if (!output)
        output = default_output(first_input, strcmp(format, "bin") == 0 ? ".bin" :
                                strcmp(format, "hex") == 0 ? ".hex" : ".mem");
    if (strcmp(format, "bin") == 0) {
        f = open_output(output, "wb");
        write_bin(f, pad);
    } else {
        f = open_output(output, "w");
        if (strcmp(format, "hex") == 0)
            write_hex(f);
        else
            write_mem(f);
    }
    fclose(f);

    if (listing) {
        f = open_output(listing, "w");
        write_listing(f);
        fclose(f);
    }
    return 0;
}
