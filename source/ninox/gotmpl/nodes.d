/*
 * Copyright (C) 2024 Mai-Lapyst
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/** 
 * Module containing the complete AST of an template.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module ninox.gotmpl.nodes;

import ninox.gotmpl.templ;
import ninox.gotmpl.exceptions;

import ninox.std.callable;
import ninox.std.variant;

alias Emit = Callable!(void, const char[]);

struct Context {
    struct Var {
        string name;
        Variant value;
    }

    /// All currently declared variables (i.e. '$x')
    Var[] vars;

    /// Custom globals
    Variant globals;

    /// The root or '$'
    Variant root;

    /// The current self or '.'
    Variant self;

    /// The callable to emit rendered data
    Emit emit;

    /// The current template
    Template tmpl;

    /** 
     * Returns the current value of the requested variable.
     * 
     * Params:
     *   name = The name of the variable to look up.
     * 
     * Throws: `ExecuteTemplateException` if the requested variable is not declared.
     * 
     * Returns: The variable's value.
     */
    ref Variant getVar(string name) {
        foreach_reverse (ref var; this.vars) {
            if (var.name == name) {
                return var.value;
            }
        }

        throw new ExecuteTemplateException("Could read from undeclared variable '$" ~ name ~ "'");
    }

    /** 
     * Sets the current value of an already declared variable.
     * Will write to the most recently pushed / declared variable.
     * Used by assignments.
     * 
     * Params:
     *   name = The name of the variable to assign to.
     *   value = The new value of the variable.
     * 
     * Throws: `ExecuteTemplateException` if the requested variable is not declared.
     */
    void setVar(string name, ref Variant value) {
        if (name == "") {
            throw new ExecuteTemplateException("Could not assign to variable '$'");
        }

        foreach_reverse (ref var; this.vars) {
            if (var.name == name) {
                var.value = value;
                return;
            }
        }

        throw new ExecuteTemplateException("Could not assign to undeclared variable '$" ~ name ~ "'");
    }

    /** 
     * Pushes or "declares" a new variable.
     * 
     * Params:
     *   name = The name of the variable to declare.
     *   value = The initial value of the variable.
     */
    void push(string name, ref Variant value) {
        if (name == "") {
            throw new ExecuteTemplateException("Could not re-declare variable '$'");
        }

        this.vars ~= Var(
            name: name,
            value: value,
        );
    }

    /** 
     * Retrieves a mark for the current position of the variable stack,
     * to be used with `pop(mark)`.
     * 
     * Returns: A mark for the current position of the variable stack.
     */
    ulong mark() {
        return this.vars.length;
    }

    /** 
     * Pops off variables of the variable stack, until the mark is reached.
     * Used at the end of blocks to remove all declared variables.
     * 
     * Params:
     *   mark = The mark to which variables should be removed.
     */
    void pop(ulong mark) {
        this.vars = this.vars[0..mark];
    }
}

abstract class Expr {
    enum Kind : ubyte {
        kUnknown,
        kVar,
        kField,
        kDot,
        kBool,
        kIdent,
        kNumber,
        kString,
        kPipeline,
    }

    @property Kind kind() const pure @safe nothrow;

    /** 
     * Evaluates the expression in the given context.
     * 
     * Params:
     *   ctx = The current context.
     * 
     * Returns: The value this expression has been evaluated to.
     */
    Variant evaluate(ref Context ctx) const;
}

/** 
 * Represents variables '$x'; the dollar sign is not part of the stored name.
 * The root variable '$' is stored with an empty name.
 */
class VarExpr : Expr {
    /// The name of the variable (i.e '$x'), without the dollar sign.
    string name;

    this(string name) {
        this.name = name;
    }

    override @property Kind kind() const pure @safe nothrow {
        return Kind.kVar;
    }

    override Variant evaluate(ref Context ctx) const {
        if (this.name == "") {
            return ctx.root;
        }
        return ctx.getVar(this.name);
    }
}

/** 
 * Field expression (i.e. `.a.b`).
 * Each name of the expression (i.e. 'a' and 'b' for `.a.b`) is a seperated string
 * stored inside an array.
 * 
 * For expressions with an base (i.e. `(x).a.b`), it is stored seperately as well.
 * If a expression has none, this is `null`.
 * 
 * If no base expression is set, and no names are present, this represents `.`.
 */
class FieldExpr : Expr {
    /// The base expression, i.e. the `(x)` in `(x).a.b`.
    Expr base = null;

    /// The different names of the expression; i.e. `['a','b']` for `.a.b`
    string[] names;

    this(string[] names) {
        this.names = names;
    }

    this(Expr base, string[] names) {
        this.base = base;
        this.names = names;
    }

    override @property Kind kind() const pure @safe nothrow {
        return Kind.kField;
    }

    override Variant evaluate(ref Context ctx) const {
        Variant v = base !is null ? base.evaluate(ctx) : ctx.self;
        foreach (ref name; this.names) {
            if (!v.hasValue) {
                break;
            }
            if (cast(TypeInfo_Delegate) v.type) {
                v = v();
            }
            v = v.lookupMember(name);
        }
        return v;
    }
}

class DotExpr : Expr {
    override @property Kind kind() const pure @safe nothrow {
        return Kind.kDot;
    }

    override Variant evaluate(ref Context ctx) const {
        return ctx.self;
    }
}

/** 
 * Boolean literal `true` or `false`.
 */
class BoolExpr : Expr {
    bool value;

    this(bool value) {
        this.value = value;
    }

    override @property Kind kind() const pure @safe nothrow {
        return Kind.kBool;
    }

    override Variant evaluate(ref Context ctx) const {
        return Variant(this.value);
    }
}

/** 
 * Identifier "literal"; used commonly to call functions.
 * Example: `call`
 * 
 * Evaluation is done by looking up the identifier first in the user-supplied globals
 * and if not found, then in the builtin functions.
 */
class IdentExpr : Expr {
    string id;

    this(string id) {
        this.id = id;
    }

    override @property Kind kind() const pure @safe nothrow {
        return Kind.kIdent;
    }

    override Variant evaluate(ref Context ctx) const {
        auto v = this.id in ctx.globals;
        if (v.hasValue) {
            return v;
        }

        import ninox.gotmpl.builtin : builtins;
        auto ptr = this.id in builtins;
        if (ptr !is null) {
            return *ptr;
        }

        return Variant();
    }
}

/** 
 * Numeric/Character literal.
 */
class NumberExpr : Expr {
    enum NumKind : ubyte {
        sInt8, sInt16, sInt32, sInt64,
        uInt8, uInt16, uInt32, uInt64,
        f32, f64,
        chr8, chr16, chr32,
    }
    NumKind _numKind;
    union {
        byte _sint8;
        short _sint16;
        int _sint32;
        long _sint64;

        ubyte _uint8;
        ushort _uint16;
        uint _uint32;
        ulong _uint64;

        float _f32;
        double _f64;

        char _chr8;
        wchar _chr16;
        dchar _chr32;
    }

    this(char c) {
        this._chr8 = c;
        this._numKind = NumKind.chr8;
    }

    this(wchar c) {
        this._chr16 = c;
        this._numKind = NumKind.chr16;
    }

    this(dchar c) {
        this._chr32 = c;
        this._numKind = NumKind.chr32;
    }

    this(string str) {
        import std.conv : to, ConvOverflowException;
        import std.meta : AliasSeq;
        import std.algorithm : any;

        bool isNeg = false;
        if (str[0] == '-') {
            isNeg = true;
            str = str[1..$];
        }

        if (any!"a == '.' || a == 'e' || a == 'E' || a == 'p' || a == 'P'"(str)) {
            float m = isNeg ? -1 : 1;

            try {
                this._f32 = str.to!float;
                this._numKind = NumKind.f32;
                return;
            } catch (ConvOverflowException) {}

            try {
                this._f64 = str.to!double;
                this._numKind = NumKind.f64;
                return;
            } catch (ConvOverflowException) {}
        }
        else {
            int base = 10;
            if (str[0] == '0') {
                switch (str[1]) {
                    case 'x':
                    case 'X':
                        base = 16;
                        goto LcommonPrefix;
                    case 'o':
                    case 'O':
                        base = 8;
                        goto LcommonPrefix;
                    case 'b':
                    case 'B':
                        base = 2;
                    LcommonPrefix:
                        str = str[2..$];
                        break;

                    default:
                        break;
                }
            }

            int m = isNeg ? -1 : 1;

            template inner(alias T) {
                import std.conv : to;
                import std.traits : isSigned;
                enum field = (isSigned!T ? 's' : 'u') ~ "int" ~ (T.sizeof * 8).to!string;
                enum kind = (isSigned!T ? 's' : 'u') ~ "Int" ~ (T.sizeof * 8).to!string;
                enum inner = ("
                    try {
                        this._" ~ field ~ " = cast(" ~ T.stringof ~ ")(str.to!(" ~ T.stringof ~ ")(base) * m);
                        this._numKind = NumKind." ~ kind ~ ";
                        return;
                    } catch (ConvOverflowException) {}
                ");
            }

            mixin(inner!byte);
            mixin(inner!short);
            mixin(inner!int);
            mixin(inner!long);

            if (!isNeg) {
                mixin(inner!ubyte);
                mixin(inner!ushort);
                mixin(inner!uint);
                mixin(inner!ulong);
            }
        }

        throw new ParseTemplateException("Invalid number: '" ~ str ~ "'");
    }

    override @property Kind kind() const pure @safe nothrow {
        return Kind.kNumber;
    }

    @property NumKind numKind() const pure @safe nothrow {
        return this._numKind;
    }

    override Variant evaluate(ref Context ctx) const {
        final switch (this._numKind) {
            case NumKind.sInt8: return Variant(cast(byte) this._sint8);
            case NumKind.sInt16: return Variant(cast(short) this._sint16);
            case NumKind.sInt32: return Variant(cast(int) this._sint32);
            case NumKind.sInt64: return Variant(cast(long) this._sint64);

            case NumKind.uInt8: return Variant(cast(ubyte) this._uint8);
            case NumKind.uInt16: return Variant(cast(ushort) this._uint16);
            case NumKind.uInt32: return Variant(cast(uint) this._uint32);
            case NumKind.uInt64: return Variant(cast(ulong) this._uint64);

            case NumKind.f32: return Variant(cast(float) this._f32);
            case NumKind.f64: return Variant(cast(double) this._f64);

            case NumKind.chr8: return Variant(cast(char) this._chr8);
            case NumKind.chr16: return Variant(cast(wchar) this._chr16);
            case NumKind.chr32: return Variant(cast(dchar) this._chr32);
        }
    }

    override string toString() const @safe pure {
        import std.conv : to;
        final switch (this._numKind) {
            case NumKind.sInt8: return this._sint8.to!string;
            case NumKind.sInt16: return this._sint16.to!string;
            case NumKind.sInt32: return this._sint32.to!string;
            case NumKind.sInt64: return this._sint64.to!string;

            case NumKind.uInt8: return this._uint8.to!string;
            case NumKind.uInt16: return this._uint16.to!string;
            case NumKind.uInt32: return this._uint32.to!string;
            case NumKind.uInt64: return this._uint64.to!string;

            case NumKind.f32: return this._f32.to!string;
            case NumKind.f64: return this._f64.to!string;

            case NumKind.chr8: return this._chr8.to!string;
            case NumKind.chr16: return this._chr16.to!string;
            case NumKind.chr32: return this._chr32.to!string;
        }
    }
}

/** 
 * String literal.
 */
class StringExpr : Expr {
    string content;

    this(string content) {
        this.content = content;
    }

    override @property Kind kind() const pure @safe nothrow {
        return Kind.kString;
    }

    override Variant evaluate(ref Context ctx) const {
        return Variant(this.content);
    }
}

// ------------------------------------------------------

/** 
 * A command is an space seperated list of expressions.
 * If the first expression is callable, it is invoked with the rest as arguments.
 */
class Command {
    Expr[] args;

    Variant evaluate(ref Context ctx, ref Variant extraParam) const {

        if (auto ident = cast(IdentExpr) this.args[0]) {
            if (ident.id == "and" || ident.id == "or") {
                auto isOr = ident.id == "or";
                Variant v;
                foreach (ref arg; this.args[1..$]) {
                    v = arg.evaluate(ctx);
                    if (v.isTruthy == isOr) {
                        return v;
                    }
                }
                if (extraParam.hasValue) {
                    v = extraParam;
                }
                return v;
            }
        }

        Variant arg0 = this.args[0].evaluate(ctx);
        if (!arg0.hasValue) {
            return Variant();
        }

        if (arg0.isCallable) {
            import ninox.gotmpl.builtin : and, or;

            Variant[] params;
            foreach (ref arg; this.args[1..$]) {
                params ~= arg.evaluate(ctx);
            }
            if (extraParam.hasValue) {
                params ~= extraParam;
            }

            if (arg0.peek!(Variant function(Variant[]...)) !is null) {
                return arg0.get!(Variant function(Variant[]...))()(params);
            }
            else if (arg0.peek!(Variant function(Variant)) !is null) {
                if (params.length != 1) {
                    import std.conv : to;
                    throw new ExecuteTemplateException(
                        "Mismatching argument count for command: expected 1 but got " ~ params.length.to!string
                    );
                }
                return arg0.get!(Variant function(Variant))()(params[0]);
            }

            return arg0.doCall(params);
        }
        else {
            if (this.args.length > 1) {
                throw new ExecuteTemplateException("To many arguments for command");
            }
            return arg0;
        }
    }
}

/** 
 * A pipeline is a pipe (`|`) seperated list of commands.
 * 
 * Each command after the first is given the result of the previous as it's last argument.
 * 
 * If any declarations or assignments are present, those get the value of the pipeline.
 */
class Pipeline : Expr {
    bool isAssign = false;
    string[] decls;
    Command[] commands;

    override @property Kind kind() const pure @safe nothrow {
        return Kind.kPipeline;
    }

    override Variant evaluate(ref Context ctx) const {
        Variant v;
        foreach (ref cmd; commands) {
            v = cmd.evaluate(ctx, v);
        }

        foreach (ref decl; this.decls) {
            if (this.isAssign) {
                ctx.setVar(decl, v);
            }
            else {
                ctx.push(decl, v);
            }
        }
        return v;
    }
}

// ------------------------------------------------------

/** 
 * A node in the template's AST.
 */
abstract class Node {
    /** 
     * Executes the node with the given context.
     * 
     * Params:
     *   ctx = The current context.
     */
    void execute(ref Context ctx);

    /** 
     * Retrieves the state if an node is empty or not.
     * 
     * Returns: `true` if the node is empty, `false if not`
     */
    @property bool isEmpty() const {
        return false;
    }
}

alias Block = Node[];

/** 
 * Plain text; gets emitted as-is.
 */
class TextNode : Node {
    string content;

    override void execute(ref Context ctx) {
        ctx.emit(this.content);
    }

    override @property bool isEmpty() const {
        import std.string : strip;
        return content.strip.length == 0;
    }
}

/** 
 * Evaluates the contained pipeline; if it has no variables to declare or assign,
 * the result of the evaluated pipeline is converted to a string and emitted.
 */
class PipelineNode : Node {
    Pipeline pipeline;

    this(Pipeline pipeline) {
        this.pipeline = pipeline;
    }

    override void execute(ref Context ctx) {
        auto val = this.pipeline.evaluate(ctx);
        if (this.pipeline.decls.length > 0) {
            return;
        }

        import std.conv : to;
        ctx.emit(val.to!(const char[]));
    }
}

/** 
 * Base-class for all branching nodes.
 */
abstract class BranchNode : Node {
    Pipeline pipeline;
    Block bodyBlock = null;
    Block elseBlock = null;
}

/** 
 * An `if`; evaluates the pipeline, and if the result is truthy,
 * the body is executed; if not, the else block is executed instead.
 * 
 * Pops all variables declared inside if it finishes.
 */
class IfNode : BranchNode {
    override void execute(ref Context ctx) {
        auto mark = ctx.mark();
        scope(exit) ctx.pop(mark);

        auto v = this.pipeline.evaluate(ctx);
        Block block = this.bodyBlock;
        if (!v.isTruthy) {
            block = this.elseBlock;
        }
        foreach (ref node; block) {
            node.execute(ctx);
        }
    }
}

/** 
 * An range or `foreach`;
 * 
 * Evaluates the pipeline and if truthy, iterates over it,
 * executing the body block for each element. Sets the variables
 * in the pipeline on each iteration to the key and value,
 * and updates the self (`.`) to the value aswell. Pops all variables
 * declared inside the body on each new iteration. Self is reset to the original
 * value after the iteration is over.
 * 
 * If the evaluated pipeline is not truthy, it executes the else block instead.
 * 
 * Pops all variables declared inside if it finishes.
 */
class RangeNode : BranchNode {
    override void execute(ref Context ctx) {
        auto mark = ctx.mark();
        scope(exit) ctx.pop(mark);

        auto v = this.pipeline.evaluate(ctx);
        if (v.isTruthy) {
            auto oldSelf = ctx.self;
            v.iterateOver((ref Variant key, ref Variant value) {
                if (this.pipeline.decls.length > 1) {
                    ctx.setVar(this.pipeline.decls[0], key);
                    ctx.setVar(this.pipeline.decls[1], value);
                }
                else if (this.pipeline.decls.length > 0) {
                    ctx.setVar(this.pipeline.decls[0], value);
                }

                auto mark = ctx.mark();
                scope(exit) ctx.pop(mark);

                ctx.self = value;

                foreach (ref node; this.bodyBlock) {
                    try {
                        node.execute(ctx);
                    } catch (RangeControl e) {
                        return e.isBreak;
                    }
                }

                return 0;
            });
            ctx.self = oldSelf;
        }
        else {
            foreach (ref node; this.elseBlock) {
                node.execute(ctx);
            }
        }
    }
}

/** 
 * Evaluates the pipeline and if truthy, sets the self (`.`) to this
 * value and executes the body block. Resets self afterwards.
 * 
 * If the pipeline does not evaluates to a truthy value, the else block
 * is executed instead.
 * 
 * Pops all variables declared inside if it finishes.
 */
class WithNode : BranchNode {
    override void execute(ref Context ctx) {
        auto mark = ctx.mark();
        scope(exit) ctx.pop(mark);

        auto v = this.pipeline.evaluate(ctx);
        if (v.isTruthy) {
            auto oldSelf = ctx.self;
            ctx.self = v;
            foreach (ref node; this.bodyBlock) {
                node.execute(ctx);
            }
            ctx.self = oldSelf;
        } else {
            foreach (ref node; this.elseBlock) {
                node.execute(ctx);
            }
        }
    }
}

private class RangeControl : Throwable {
    bool isBreak;

    this(bool isBreak) {
        super("rangeControl");
        this.isBreak = isBreak;
    }
}

/** 
 * Controls the iteration of an `RangeNode` by stoping the iteration alltogether.
 */
class BreakNode : Node {
    override void execute(ref Context ctx) {
        throw new RangeControl(true);
    }
}

/** 
 * Controls the iteration of an `RangeNode` by skiping the rest of the block and directly
 * starts the next iteration.
 */
class ContinueNode : Node {
    override void execute(ref Context ctx) {
        throw new RangeControl(false);
    }
}

/** 
 * Calls another (named) template.
 * 
 * If an pipeline is given, it is evaluated and used as the data for the template,
 * setting both `$` and the initial `.` to this value for the template should be executed.
 * 
 * Does not touch the current template's `$` nor the current `.`.
 */
class TemplateCallNode : Node {
    string name;
    Pipeline pipeline;

    this(string name, Pipeline pipeline) {
        this.name = name;
        this.pipeline = pipeline;
    }

    override void execute(ref Context ctx) {
        auto tmpl = ctx.tmpl.getTemplate(this.name);
        if (tmpl is null) {
            throw new ExecuteTemplateException("Cannot call undeclared template '" ~ this.name ~ "'");
        }
        auto v = Variant();
        if (this.pipeline !is null) {
            v = this.pipeline.evaluate(ctx);
        }
        tmpl.executeInternal(ctx.emit, v);
    }
}
