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
 * Module containing the template type itself.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module ninox.gotmpl.templ;

import ninox.gotmpl.nodes;
import ninox.gotmpl.parser;
import ninox.gotmpl.exceptions;

import ninox.std.callable;
import ninox.std.variant;

import core.stdc.stdio;
import core.sys.posix.stdio : fmemopen;
import std.meta;
import ninox.gotmpl.printer;

private alias EmitVariants = AliasSeq!(
    void function(const char[]),
    void delegate(const char[]),
    Callable!(void, const char[])
);

alias FuncMap = Variant[string];

private class Common {
    FuncMap globals;
    Template[string] templates;
}

class Template {

    package(ninox.gotmpl) {
        string _name;
    }

    Block block;

    Common common;
    alias common this;

    this(string name) {
        this._name = name;
        this.common = new Common();
    }

    private this(string name, Common c) {
        this._name = name;
        this.common = c;
    }

    /** 
     * Retrieves the name of the template
     * 
     * Returns: The name of the current template
     */
    pragma(inline) @property string name() const pure @safe nothrow {
        return this._name;
    }

    /** 
     * Parse template from a plain string.
     * 
     * Params:
     *   name = The name the template should be given.
     *   content = The string to parse.
     * 
     * Returns: The parsed template.
     */
    static Template parseString(string name, string content) {
        auto file = fmemopen(content.ptr, content.length, "rb");
        scope(exit) fclose(file);
        return Parser().parse(name, file);
    }

    /** 
     * Parse template from a file loaded from the given filepath.
     * 
     * Params:
     *   name = The name the template should be given.
     *   filepath = The path to the file to use.
     *
     * Returns: The parsed template.
     */
    static Template parseFile(string name, string filepath) {
        auto file = fopen(filepath.ptr, "rb");
        scope(exit) fclose(file);
        return Parser().parse(name, file);
    }

    /** 
     * Parse template from a libc stream handle.
     * 
     * Params:
     *   name = The name the template should be given.
     *   file = The libc stream handle to parse from.
     * 
     * Returns: The parsed template.
     */
    pragma(inline)
    static Template parseFile(string name, FILE* file) {
        return Parser().parse(name, file);
    }

    /** 
     * Try to retrieve a associated template by it's name.
     * 
     * Params:
     *   name = The name of the template.
     * 
     * Returns: The requested template or `null` if non could be found.
     */
    Template getTemplate(string name) {
        auto ptr = name in this.templates;
        if (ptr !is null)
            return *ptr;
        return null;
    }

    static foreach (EmitTy; EmitVariants) {
        pragma(inline)
        void execute(T)(EmitTy emit, T data) {
            this.execute(emit, Variant(data));
        }

        pragma(inline)
        void execute(EmitTy emit, Variant data) {
            import std.traits : isInstanceOf;
            static if (isInstanceOf!(EmitTy, Callable)) {
                this.executeInternal(emit, data);
            } else {
                Callable!(void, const char[]) _emit = emit;
                this.executeInternal(_emit, data);
            }
        }

        pragma(inline)
        void execute(T)(EmitTy emit, string name, T data) {
            this.execute(emit, name, Variant(data));
        }

        pragma(inline)
        void execute(EmitTy emit, string name, Variant data) {
            auto ptr = name in this.templates;
            if (ptr is null)
                throw new ExecuteTemplateException("Unknown template to execute: '" ~ name ~ "'");
            (*ptr).execute(emit, data);
        }
    }

    /** 
     * Prints the AST of the current template to stdout
     */
    void dump() {
        Printer p;
        p.visit(this);
    }

    package(ninox.gotmpl) void executeInternal(
        ref Callable!(void, const char[]) emit,
        ref Variant data
    ) {
        Context ctx;
        ctx.emit = emit;
        ctx.self = data;
        ctx.root = data;
        ctx.globals = this.globals;
        ctx.tmpl = this;
        foreach (ref node; this.block) {
            node.execute(ctx);
        }
    }

    /** 
     * Clones the template;
     * Does a shallow clone of the AST, but a deeper clone of the declared templates.
     * 
     * Returns: The cloned template.
     */
    Template clone() {
        auto ret = new Template(this._name);
        ret.block = this.block;
        foreach (ref name, ref tmpl; this.templates) {
            if (name == this.name) {
                ret.templates[name] = ret;
                continue;
            }
            ret.templates[name] = tmpl;
        }
        ret.globals = this.globals;
        return ret;
    }

    /** 
     * Creates a new sub-template.
     * 
     * Params:
     *   name = The name of the sub template.
     * 
     * Returns: The newly created template.
     */
    pragma(inline) Template createNew(string name) {
        return new Template(name, this.common);
    }

    /** 
     * Checks if the template's AST is empty,
     * which means that either the AST holds no nodes or only
     * text notes which contain only whitespace.
     * 
     * Returns: `true` or `false`.
     */
    @property bool isEmpty() const {
        import std.algorithm : all;
        return this.block is null || this.block.length < 1 || all!("a.isEmpty")(this.block);
    }

    /** 
     * Parses a new template content from a string and merges it with the current one.
     * See `parseFile(FILE*)` for more infos.
     * 
     * Params:
     *   content = The template content to parse.
     * 
     * Returns: The current template.
     */
    Template parseString(string content) {
        auto file = fmemopen(content.ptr, content.length, "rb");
        scope(exit) fclose(file);
        return this.parseFile(file);
    }

    /** 
     * Parses a new template content from file and merges it with the current one.
     * See `parseFile(FILE*)` for more infos.
     * 
     * Params:
     *   content = The path to the template file to parse.
     * 
     * Returns: The current template.
     */
    Template parseFile(string filepath) {
        auto file = fopen(filepath.ptr, "rb");
        scope(exit) fclose(file);
        return this.parseFile(file);
    }

    /** 
     * Parses a new template content from a libc stream handle and merges it with the current one.
     * 
     * The merging is done for the "root" template and all "sub"-templates (created via `define` or `block`).
     * If the template already has an AST, it is only replaced if the new template is not empty (see `isEmpty`).
     * 
     * Params:
     *   content = The libc stream handle to read from.
     * 
     * Returns: The current template.
     */
    Template parseFile(FILE* file) {
        auto nt = new Template(this.name, this.common);
        Parser().parse(nt, file);
        foreach (ref name, ref tmpl; nt.templates) {
            auto ptr = name in this.templates;
            if (ptr is null) {
                this.templates[name] = tmpl;
            }
            else if (!tmpl.isEmpty) {
                this.templates[name].block = tmpl.block;
            }
        }
        return this;
    }

}
