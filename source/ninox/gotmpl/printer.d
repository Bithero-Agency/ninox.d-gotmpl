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
 * Module containing the template debug printer.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module ninox.gotmpl.printer;

import ninox.gotmpl.templ;
import ninox.gotmpl.nodes;

import std.stdio : writeln, write;

struct Printer {

    private int lvl = 0;
    private bool eatIndent = false;

    private void indent() {
        if (eatIndent) {
            eatIndent = false;
            return;
        }

        for (int i = 0; i < lvl; i++) {
            write("    ");
        }
    }

    private pragma(inline) void log(T...)(T args) {
        indent(); writeln(args);
    }

    void visit(Template templ) {
        writeln("Template '" ~ templ.name ~ "' {");
        lvl++;
        this.visitBlock(templ.block);
        writeln("}");
    }

    private void visit(Command cmd) {
        log("Command {");
        lvl++;
            foreach (ref arg; cmd.args) {
                this.visit(arg);
            }
        lvl--;
        log("}");
    }

    private void visit(Pipeline pipeline) {
        if (pipeline.decls.length > 0) {
            log("Decls ", pipeline.decls);
        }
        log("Commands [");
        lvl++;
            foreach (ref cmd; pipeline.commands) {
                this.visit(cmd);
            }
        lvl--;
        log("]");
    }

    private void visit(Expr expr) {
        switch (expr.kind) {
            case Expr.Kind.kVar: {
                log("VarExpr '" ~ (cast(VarExpr) expr).name ~ "'");
                break;
            }
            case Expr.Kind.kField: {
                auto field = cast(FieldExpr) expr;
                if (field.base !is null) {
                    log("FieldExpr {");
                    lvl++;
                        indent(); write("base: "); eatIndent = true; visit(field.base);
                        log("names: ", field.names);
                    lvl--;
                    log("}");
                }
                else {
                    log("FieldExpr ", field.names);
                }
                break;
            }
            case Expr.Kind.kDot: {
                log("DotExpr");
                break;
            }
            case Expr.Kind.kBool: {
                log("BoolExpr " ~ ((cast(BoolExpr) expr).value ? "true" : "false"));
                break;
            }
            case Expr.Kind.kIdent: {
                log("IdentExpr " ~ (cast(IdentExpr) expr).id);
                break;
            }
            case Expr.Kind.kNumber: {
                auto num = cast(NumberExpr) expr;
                log("NumberExpr ", num.numKind(), " : ", num.toString());
                break;
            }
            case Expr.Kind.kString: {
                auto str = cast(StringExpr) expr;
                log("StringExpr \"", str.content, "\"");
                break;
            }
            case Expr.Kind.kPipeline: {
                auto pipeline = cast(Pipeline) expr;
                log("Pipeline {");
                lvl++;
                    this.visit(pipeline);
                lvl--;
                log("}");
                break;
            }
            default: {
                log("Unknown expression");
            }
        }
    }

    private void visitBranch(BranchNode node) {
        lvl++;
            indent(); writeln("Pipeline {");
            lvl++;
                this.visit(node.pipeline);
            lvl--;
            indent(); writeln("}");
            if (node.bodyBlock.length > 0) {
                indent(); writeln("Body [");
                lvl++;
                    this.visitBlock(node.bodyBlock);
                lvl--;
                indent(); writeln("]");
            }
            if (node.elseBlock.length > 0) {
                indent(); writeln("Else [");
                lvl++;
                    this.visitBlock(node.elseBlock);
                lvl--;
                indent(); writeln("]");
            }
        lvl--;
    }

    private void visit(Node node) {
        if (auto text = cast(TextNode) node) {
            log("TextNode '" ~ text.content ~ "'");
        } else if (auto ifNode = cast(IfNode) node) {
            log("IfNode {");
            visitBranch(ifNode);
            log("}");
        } else if (auto withNode = cast(WithNode) node) {
            log("WithNode {");
            visitBranch(withNode);
            log("}");
        } else if (auto rangeNode = cast(RangeNode) node) {
            log("RangeNode {");
            visitBranch(rangeNode);
            log("}");
        } else if (auto n = cast(PipelineNode) node) {
            log("PipelineNode {");
            lvl++;
            visit(n.pipeline);
            lvl--;
            log("}");
        } else if (cast(BreakNode) node) {
            log("BreakNode");
        } else if (cast(ContinueNode) node) {
            log("ContinueNode");
        } else if (auto call = cast(TemplateCallNode) node) {
            indent(); write("TemplateCallNode name: \"", call.name, "\"");
            if (call.pipeline !is null) {
                write(", pipeline: {\n");
                lvl++;
                visit(call.pipeline);
                lvl--;
                log("}");
            } else {
                write("\n");
            }
        } else {
            log("UNKNOWN NODE");
        }
    }

    private void visitBlock(Node[] block) {
        foreach (ref node; block) {
            visit(node);
        }
    }

}
