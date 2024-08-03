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
 * Module containing the template parser.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module ninox.gotmpl.parser;

import ninox.gotmpl.templ;
import ninox.gotmpl.nodes;
import ninox.gotmpl.exceptions;

import ninox.std.string : Unquoter, unquoteString;

import core.stdc.stdio;
import std.stdio : writeln;

pragma(inline)
private bool isAlphaNumeric(char c) {
    return (
        (c >= 'a' && c <= 'z')
        || (c >= 'A' && c <= 'Z')
        || c == '_'
        || (c >= '0' && c <= '9')
    );
}

pragma(inline)
private bool isSpace(char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

struct Parser {
    FILE* file;
    string openDelim = "{{";
    string closeDelim = "}}";
    bool isSubParser = false;
    bool nextTextTrimStart = false;

    pragma(inline)
    private char consumeChar() {
        char c;
        if (fread(&c, char.sizeof, 1, this.file) != 1) {
            throw new ParseTemplateException("Unexpected end of file");
        }
        return c;
    }

    pragma(inline)
    private char peekChar() {
        char c;
        if (fread(&c, char.sizeof, 1, this.file) != 1) {
            throw new ParseTemplateException("Unexpected end of file");
        }
        fseek(this.file, -1, SEEK_CUR);
        return c;
    }

    pragma(inline)
    private ulong savePos() {
        return ftell(this.file);
    }

    pragma(inline)
    private void jumpTo(ulong pos) {
        fseek(this.file, pos, SEEK_SET);
    }

    pragma(inline)
    private void rewind(int i = 1) {
        assert(i > 0);
        fseek(this.file, -i, SEEK_CUR);
    }

    private string parseIdent() {
        string id = "";
        while (true) {
            char c = this.consumeChar();
            if (c.isAlphaNumeric) {
                id ~= c;
                continue;
            }
            fseek(this.file, -1, SEEK_CUR);
            break;
        }
        return id;
    }

    private void consumeClose() {
        auto pos = this.savePos();
        if (this.consumeChar() == ' ' && this.consumeChar() == '-') {
            nextTextTrimStart = true;
        } else {
            this.jumpTo(pos);
        }

        foreach (ref ch; this.closeDelim) {
            char c = this.consumeChar();
            if (c != ch) {
                throw new ParseTemplateException("Expected end delimiter");
            }
        }
    }

    private bool matchClose() {
        auto pos = this.savePos();
        if (!(this.consumeChar() == ' ' && this.consumeChar() == '-')) {
            this.jumpTo(pos);
        }

        foreach (ref ch; this.closeDelim) {
            char c;
            if (fread(&c, char.sizeof, 1, this.file) != 1 || c != ch) {
                this.jumpTo(pos);
                return false;
            }
        }
        this.jumpTo(pos);
        return true;
    }

    private void skipWs() {
        while (true) {
            char c;
            if (fread(&c, char.sizeof, 1, this.file) != 1) {
                return;
            }
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                continue;
            }
            fseek(this.file, -1, SEEK_CUR);
            return;
        }
    }

    private BranchNode parseBranch(string ctx) {
        BranchNode ret = null;
        switch (ctx) {
            case "if": ret = new IfNode(); break;
            case "range": ret = new RangeNode(); break;
            case "with": ret = new WithNode(); break;
            default: throw new ParseTemplateException("Unexpected branch context: '" ~ ctx ~ "'");
        }
        ret.pipeline = this.parsePipeline(ctx, false);
        this.consumeClose();
        return ret;
    }

    private Pipeline parsePipeline(string ctx, bool isInner) {
        auto ret = new Pipeline();

        this.skipWs();

        auto pos = this.savePos();
        if (this.consumeChar() == '$') {
            string[] decls;
            decls ~= this.parseIdent();

            this.skipWs();
            if (this.consumeChar() == ',') {
                if (ctx != "range") {
                    throw new ParseTemplateException("Cannot declare mutltiple vars");
                }
                this.skipWs();

                if (this.consumeChar() != '$') {
                    throw new ParseTemplateException("Expected '$' to start with the second variable");
                }
                decls ~= this.parseIdent();
            } else {
                this.rewind();
            }

            this.skipWs();

            char c = this.consumeChar();
            if (c == '=') {
                // is assign!
                ret.decls = decls;
                ret.isAssign = true;
            }
            else if (c == ':' && this.peekChar() == '=') {
                // is decl!
                fseek(this.file, 1, SEEK_CUR);
                ret.decls = decls;
            }
            else {
                this.jumpTo(pos);
                goto LpipelineMain;
            }
        } else {
            this.rewind();
        }

        LpipelineMain:

        while (true) {
            if (isInner) {
                char c = this.consumeChar();
                if (c == ')') break;
                this.rewind();
            }
            else {
                if (matchClose()) break;
            }

            ret.commands ~= this.parseCommand();
        }

        // Check pipeline before returning it
        if (ret.commands.length <= 0) {
            throw new ParseTemplateException("missing value for " ~ ctx);
        }

        return ret;
    }

    private Command parseCommand() {
        auto cmd = new Command();
        while (true) {
            this.skipWs();
            auto op = this.parseOperand();
            if (op !is null) {
                cmd.args ~= op;
            }

            char c = this.peekChar();
            if (c == '|') {
                fseek(this.file, 1, SEEK_CUR);
                break;
            }
            else if (c == ')' || this.matchClose()) break;
            else if (c.isSpace) continue;

            throw new ParseTemplateException("Unexpected token in command: '" ~ c ~ "'");
        }

        if (cmd.args.length <= 0) {
            throw new ParseTemplateException("Empty command");
        }

        return cmd;
    }

    private Expr parseOperand() {
        auto term = parseTerm();
        if (term is null) {
            return null;
        }

        string[] chain;
        while (true) {
            auto pos = this.savePos();
            auto c = this.consumeChar();
            if (c == '.') {
                c = this.consumeChar();
                if (c.isAlphaNumeric) {
                    this.rewind();
                    chain ~= this.parseIdent();
                    continue;
                }
            }
            this.jumpTo(pos);
            break;
        }

        if (chain.length < 1) {
            return term;
        }
        else {
            return new FieldExpr(term, chain);
        }


        /*auto pos = this.savePos();
        char c = this.consumeChar();
        if (c == '.') {
            c = this.consumeChar();
            if (c.isAlphaNumeric) {
                // is indeed field
                this.jumpTo(pos);

                Expr[] chain;
                while (true) {
                    pos = this.savePos();
                    c = this.consumeChar();
                    if (c == '.') {
                        c = this.consumeChar();
                        if (c.isAlphaNumeric) {

                        }
                    }
                }
                return new ChainExpr(chain);
            }
        }
        this.jumpTo(pos);
        return term;*/
    }

    private Expr parseTerm() {
        char c = this.consumeChar();
        if (c == '.') {
            c = this.peekChar();
            if (c.isAlphaNumeric) {
                // is a field, not the special '.' keyword

                string[] names = [];
                names ~= this.parseIdent();
                while(this.peekChar == '.') {
                    this.consumeChar();
                    names ~= this.parseIdent();
                }
                return new FieldExpr(names);
            }
            else {
                return new DotExpr();
            }
        }
        else if (c == '$') {
            auto var = this.parseIdent();
            // TODO: check if variable is declared
            return new VarExpr(var);
        }
        else if (c == '\'') {
            string s = "";
            while (true) {
                c = this.consumeChar();
                if (c == '\\') {
                    s ~= '\\';
                    s ~= this.consumeChar();
                    continue;
                }
                else if (c == '\'') {
                    break;
                }
                s ~= c;
            }

            auto unquoter = Unquoter(s, '\'');
            dchar r = unquoter.next();
            if (unquoter.hasError) {
                throw new ParseTemplateException("Invalid character constant: '" ~ s ~ "'");
            }

            switch (unquoter.size) {
                case 1:
                    return new NumberExpr(cast(char) r);
                case 2:
                    return new NumberExpr(cast(wchar) r);
                case 4:
                    return new NumberExpr(r);
                default:
                    throw new ParseTemplateException("Invalid character constant: UnquoteChar reports invalid size");
            }
        }
        else if (c == '(') {
            return this.parsePipeline("parenthesized pipeline", true);
        }
        else if (c == '"') {
            string s = "";
            while (true) {
                c = this.consumeChar();
                if (c == '\\') {
                    s ~= '\\';
                    s ~= this.consumeChar();
                    continue;
                }
                else if (c == '\"') {
                    break;
                }
                s ~= c;
            }
            return new StringExpr(s.unquoteString);
        }
        else if (c == '`') {
            string s = "";
            while (true) {
                c = this.consumeChar();
                if (c == '`') {
                    break;
                }
                s ~= c;
            }
            return new StringExpr(s);
        }
        else if (c == '+' || c == '-' || (c >= '0' && c <= '9')) {
            this.rewind();
            return this.parseNumber();
        }
        else if (c.isAlphaNumeric) {
            this.rewind();
            auto id = this.parseIdent();
            switch (id) {
                case "true": return new BoolExpr(true);
                case "false": return new BoolExpr(false);
                default: return new IdentExpr(id);
            }
        }
        this.rewind();
        return null;
    }

    private NumberExpr parseNumber() {
        string str = "";

        char c = this.consumeChar();
        if (c == '+' || c == '-') {
            str ~= c;
            c = this.consumeChar();
        }

        auto isDigit = (char c) => (c >= '0' && c <= '9') || c == '_';
        int base = 10;
        if (c == '0') {
            str ~= '0';
            c = this.consumeChar();
            if (c == 'x' || c == 'X') {
                str ~= c;
                c = this.consumeChar();
                isDigit = (char c) => (
                    (c >= '0' && c <= '9')
                    || (c >= 'a' && c <= 'f')
                    || (c >= 'A' && c <= 'F')
                    || c == '_'
                );
                base = 16;
            }
            else if (c == 'o' || c == 'O') {
                str ~= c;
                c = this.consumeChar();
                isDigit = (char c) => (c >= '0' && c <= '7') || c == '_';
                base = 8;
            }
            else if (c == 'b' || c == 'B') {
                str ~= c;
                c = this.consumeChar();
                isDigit = (char c) => c == '0' || c == '1' || c == '_';
                base = 2;
            }
            else {
                this.rewind();
            }
        }

        void parseDigits(bool function(char) isDigit) {
            while (true) {
                char ch = this.consumeChar();
                if (isDigit(ch)) {
                    str ~= ch;
                    continue;
                }
                this.rewind();
                break;
            }
        }

        this.rewind();
        parseDigits(isDigit);
        c = this.consumeChar();
        if (c == '.') {
            str ~= c;
            parseDigits(isDigit);
            c = this.consumeChar();
        }
        if (base == 10 && (c == 'e' || c == 'E')) {
            str ~= c;
            c = this.consumeChar();
            if (c == '+' || c == '-') {
                str ~= c;
            } else {
                this.rewind();
            }
            parseDigits((char c) => (c >= '0' && c <= '9') || c == '_');
            c = this.consumeChar();
        }
        if (base == 16 && (c == 'p' || c == 'P')) {
            str ~= c;
            c = this.consumeChar();
            if (c == '+' || c == '-') {
                str ~= c;
            } else {
                this.rewind();
            }
            parseDigits((char c) => (c >= '0' && c <= '9') || c == '_');
            c = this.consumeChar();
        }

        this.rewind();
        return new NumberExpr(str);
    }

    Template parse(string name, FILE* file) {
        auto ret = new Template(name);
        this.parse(ret, file);
        return ret;
    }

    void parse(Template ret, FILE* file) {
        this.file = file;
        scope(exit) this.file = null;

        int rangeDepth = 0;
        TextNode curText = null;

        struct Entry {
            BranchNode node;
            Block* block;
            bool isElseIf = false;
        }
        Entry[] stack = [];
        @property Block* block() {
            if (stack.length == 0) {
                return &(ret.block);
            }
            else {
                return stack[$-1].block;
            }
        }

        bool consumeTextUntilOpen() {
            while (!feof(this.file)) {
                auto pos = this.savePos();
                foreach (ref ch; this.openDelim) {
                    char c;
                    if (fread(&c, char.sizeof, 1, this.file) != 1) {
                        return false;
                    }
                    if (c != ch) {
                        this.jumpTo(pos);
                        goto LnotOpenDelim;
                    }
                }

                // is open delimiter
                curText = null;
                return true;

                LnotOpenDelim: {
                    this.jumpTo(pos);
                    char c;
                    fread(&c, char.sizeof, 1, this.file);

                    if (this.nextTextTrimStart) {
                        if (c.isSpace) {
                            continue;
                        }
                        this.nextTextTrimStart = false;
                    }

                    if (curText is null) {
                        curText = new TextNode();
                        *block ~= curText;
                    }
                    curText.content ~= c;

                    continue;
                }
            }
            return false;
        }

        while (true) {
            if (!consumeTextUntilOpen()) break;

            this.nextTextTrimStart = false;

            auto pos = this.savePos();

            if (this.consumeChar() == '-' && this.consumeChar() == ' ') {
                pos = this.savePos();
                // strip end of any last text node
                if ((*block).length > 0) {
                    if (auto text = cast(TextNode) (*block)[$-1]) {
                        import std.string : stripRight;
                        text.content = text.content.stripRight;
                    }
                }
            } else {
                this.jumpTo(pos);
            }

            this.skipWs();
            auto id = this.parseIdent();
            switch (id) {
                case "block": {
                    this.skipWs();

                    auto nameExpr = this.parseTerm();
                    if (nameExpr is null || nameExpr.kind() != Expr.Kind.kString) {
                        throw new ParseTemplateException("Expected a string expression for a name");
                    }

                    auto pipeline = this.parsePipeline("template clause", false);

                    this.skipWs();
                    this.consumeClose();

                    Parser subParse;
                    subParse.openDelim = this.openDelim;
                    subParse.closeDelim = this.closeDelim;
                    subParse.isSubParser = true;
                    subParse.nextTextTrimStart = this.nextTextTrimStart;

                    auto subTmpl = ret.createNew((cast(StringExpr) nameExpr).content);
                    subParse.parse(subTmpl, this.file);

                    ret.templates[subTmpl.name] = subTmpl;
                    this.nextTextTrimStart = subParse.nextTextTrimStart;

                    *block ~= new TemplateCallNode(
                        (cast(StringExpr)nameExpr).content,
                        pipeline
                    );

                    break;
                }
                case "define": {
                    this.skipWs();

                    auto nameExpr = this.parseTerm();
                    if (nameExpr is null || nameExpr.kind() != Expr.Kind.kString) {
                        throw new ParseTemplateException("Expected a string expression for a name");
                    }

                    this.skipWs();
                    this.consumeClose();

                    Parser subParse;
                    subParse.openDelim = this.openDelim;
                    subParse.closeDelim = this.closeDelim;
                    subParse.isSubParser = true;
                    subParse.nextTextTrimStart = this.nextTextTrimStart;

                    auto subTmpl = ret.createNew((cast(StringExpr) nameExpr).content);
                    subParse.parse(subTmpl, this.file);

                    ret.templates[subTmpl.name] = subTmpl;
                    this.nextTextTrimStart = subParse.nextTextTrimStart;
                    break;
                }
                case "template": {
                    this.skipWs();

                    auto nameExpr = this.parseTerm();
                    if (nameExpr is null || nameExpr.kind() != Expr.Kind.kString) {
                        throw new ParseTemplateException("Expected a string expression for a name");
                    }

                    this.skipWs();

                    Pipeline pipeline = null;
                    if (!this.matchClose()) {
                        pipeline = this.parsePipeline("template clause", false);
                    }

                    this.skipWs();
                    this.consumeClose();

                    *block ~= new TemplateCallNode(
                        (cast(StringExpr)nameExpr).content,
                        pipeline
                    );
                    break;
                }

                case "break": {
                    this.skipWs();
                    this.consumeClose();
                    if (rangeDepth == 0) {
                        throw new ParseTemplateException("{{break}} outside of {{range}}");
                    }
                    *block ~= new BreakNode();
                    break;
                }

                case "continue": {
                    this.skipWs();
                    this.consumeClose();
                    if (rangeDepth == 0) {
                        throw new ParseTemplateException("{{continue}} outside of {{range}}");
                    }
                    *block ~= new ContinueNode();
                    break;
                }

                case "else": {
                    this.skipWs();

                    // Check for an 'else if'
                    pos = this.savePos();
                    id = this.parseIdent();
                    if (id == "if") {
                        this.skipWs();
                        auto ifNode = this.parseBranch("if");

                        if (stack.length == 0 || (cast(IfNode) stack[$-1].node) is null) {
                            throw new ParseTemplateException("{{else if}} without if action to target");
                        }

                        auto node = stack[$-1].node;
                        node.elseBlock = [];
                        stack[$-1] = Entry(node, &(node.elseBlock), stack[$-1].isElseIf);

                        *block ~= ifNode;
                        stack ~= Entry(ifNode, &(ifNode.bodyBlock), true);
                    }
                    else {
                        // plain else
                        this.jumpTo(pos);
                        this.consumeClose();
                        if (stack.length == 0) {
                            throw new ParseTemplateException("{{else}} without branch action to target");
                        }
                        auto node = stack[$-1].node;
                        if (cast(RangeNode) node) {
                            rangeDepth--;
                        }
                        node.elseBlock = [];
                        stack[$-1] = Entry(node, &(node.elseBlock), stack[$-1].isElseIf);
                    }
                    break;
                }

                case "end": {
                    this.skipWs();
                    this.consumeClose();
                    if (stack.length == 0) {
                        if (this.isSubParser) {
                            goto LparseEnd;
                        }
                        throw new ParseTemplateException("{{end}} without branch action to close");
                    }
                    if (auto r = cast(RangeNode) stack[$-1].block) {
                        if (r.elseBlock != null) {
                            rangeDepth--;
                        }
                    }
                    int n = stack[$-1].isElseIf ? 2 : 1;
                    stack = stack[0..$-n];
                    break;
                }

                case "range":
                    rangeDepth++;
                    goto case;
                case "if":
                case "with":
                {
                    auto node = this.parseBranch(id);
                    *block ~= node;
                    stack ~= Entry(node, &(node.bodyBlock));
                    break;
                }

                default: {
                    this.jumpTo(pos);
                    auto pipeline = this.parsePipeline("command", false);
                    this.consumeClose();
                    *block ~= new PipelineNode(pipeline);
                    break;
                }
            }
        }

        LparseEnd:

        if (stack.length > 0) {
            throw new ParseTemplateException("Found atleast one unterminated branch node");
        }

        ret.templates[ret.name] = ret;
        return;
    }

}
