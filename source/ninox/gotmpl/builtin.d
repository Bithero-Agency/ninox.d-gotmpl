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
 * Module containing all builtin functions.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module ninox.gotmpl.builtin;

import ninox.gotmpl.exceptions;

import ninox.std.variant;

/** 
 * Returns a associative array containing all builtin functions.
 * The associative array is cached after the first call.
 * 
 * Returns: A associative array containing all builtin functions.
 */
@property Variant[string] builtins() {
    static Variant[string] funcs = null;
    if (funcs !is null)
        return funcs;

    funcs = [
        "and": Variant(&and),
        "call": Variant(&call),
        "index": Variant(&index),
        "len": Variant(&length),
        "not": Variant(&not),
        "or": Variant(&or),
        "print": Variant(&print),
        "println": Variant(&println),

        // comparison
        "eq": Variant(&eq),
        "ge": Variant(&ge),
        "gt": Variant(&gt),
        "le": Variant(&le),
        "lt": Variant(&lt),
        "ne": Variant(&ne),
    ];
    return funcs;
}

/** 
 * Evaluates `a && b `.
 * Should be handled seperately by the template engine.
 * 
 * Params:
 *   a = Left hand side
 *   b = Right hand side
 * 
 * Returns: The result of `a && b`.
 */
Variant and(Variant a, Variant b) {
    throw new ExecuteTemplateException("'and' func should be handled specially");
}

/** 
 * Used to call another function: `call print "a"`.
 * 
 * First argument **must** be a callable value.
 * 
 * Params:
 *   args = The arguments.
 * 
 * Throws: `ExecuteTemplateException` when the first argument is not callable.
 * 
 * Returns: The result of the called function.
 */
Variant call(Variant[] args...) {
    if (!args[0].isCallable) {
        throw new ExecuteTemplateException("Cannot call function: " ~ args[0].toString);
    }
    return args[0].doCall(args[1..$]);
}

/** 
 * Evaluates the first argument as an indexable (indexee), and uses the next argument as parameter
 * for the index operation. The result is then taken and used as new indexee with the next argument as
 * parameter, as long as there are parameters left. The result is the value at the end.
 * 
 * Example: `a[b][c][d]`
 * 
 * Params:
 *   args = The arguments.
 * 
 * Throws: `ExecuteTemplateException` when the first argument is not indexable.
 * 
 * Returns: The result of the index operation.
 */
Variant index(Variant[] args...) {
    if (!args[0].isIndexable) {
        throw new ExecuteTemplateException("Cannot index value: " ~ args[0].toString);
    }

    Variant v = args[0];
    foreach (ref arg; args[1..$]) {
        v = v.doIndex(arg);
    }
    return v;
}

/** 
 * Retrieves the `.length` property of the argument.
 * Most usefull with iterateable values, such as arrays.
 * 
 * Params:
 *   arg = The value to get the length of.
 * 
 * Returns: The length of the value
 */
Variant length(Variant arg) {
    return Variant(arg.length);
}

/** 
 * Returns the inverse of the truthiness of the input.
 * 
 * Params:
 *   arg = The input.
 * 
 * Returns: Inverse of the truthiness.
 */
Variant not(Variant arg) {
    return Variant( !arg.isTruthy );
}

/** 
 * Evaluates `a || b `.
 * Should be handled seperately by the template engine.
 * 
 * Params:
 *   a = Left hand side
 *   b = Right hand side
 * 
 * Returns: The result of `a || b`.
 */
Variant or(Variant a, Variant b) {
    throw new ExecuteTemplateException("'or' func should be handled specially");
}

/** 
 * Combines the input args into a string.
 * Inbetween every non-string argument, a space is placed.
 * 
 * Params:
 *   args = The arguments.
 * 
 * Returns: The combined string.
 */
Variant print(Variant[] args...) {
    string str = "";
    bool lastWasString = args[0].peek!string !is null;
    str ~= args[0].toString;
    foreach (ref arg; args[1..$]) {
        bool isString = arg.peek!string !is null;
        if (!lastWasString && !isString) {
            str ~= ' ';
        }
        lastWasString = isString;
        str ~= arg.toString;
    }
    return Variant(str);
}

/** 
 * Combines the input args into a string.
 * Inbetween every argument, a space is placed.
 * Adds a newline at the end.
 * 
 * Params:
 *   args = The arguments.
 * 
 * Returns: The combined string.
 */
Variant println(Variant[] args...) {
    string str = "";
    foreach (ref arg; args) {
        if (str.length > 0)
            str ~= ' ';
        str ~= arg.toString;
    }
    str ~= '\n';
    return Variant(str);
}

/** 
 * Evaluates 'a == b || a == c || ...'
 * 
 * Params:
 *   args = the arguments
 * 
 * Returns: `true` or `false`.
 */
Variant eq(Variant[] args...) {
    if (args.length < 2) {
        throw new ExecuteTemplateException("'eq' expects atleast 2 arguments");
    }

    Variant a = args[0];
    foreach (ref arg; args[1..$]) {
        if (a == arg) {
            return Variant(true);
        }
    }
    return Variant(false);
}

/** 
 * Evaluates 'a != b && a != c && ...'
 * 
 * Params:
 *   args = The arguments
 * 
 * Returns: `true` or `false`.
 */
Variant ne(Variant[] args...) {
    if (args.length < 2) {
        throw new ExecuteTemplateException("'ne' expects atleast 2 arguments");
    }

    Variant a = args[0];
    foreach (ref arg; args[1..$]) {
        if (a != arg) {
            continue;
        }
        return Variant(false);
    }
    return Variant(true);
}

/** 
 * Evaluates 'a >= b'
 * 
 * Params:
 *   args = The arguments.
 * 
 * Throws: `ExecuteTemplateException` if not recieved exactly 2 arguments.
 * 
 * Returns: 
 */
Variant ge(Variant[] args...) {
    if (args.length != 2) {
        throw new ExecuteTemplateException("'ge' expects exactly 2 arguments");
    }
    return Variant( args[0] >= args[1] );
}

/** 
 * Evaluates 'a > b'
 * 
 * Params:
 *   args = The arguments.
 * 
 * Throws: `ExecuteTemplateException` if not recieved exactly 2 arguments.
 * 
 * Returns: 
 */
Variant gt(Variant[] args...) {
    if (args.length != 2) {
        throw new ExecuteTemplateException("'gt' expects exactly 2 arguments");
    }
    return Variant( args[0] > args[1] );
}

/** 
 * Evaluates 'a <= b'
 * 
 * Params:
 *   args = The arguments.
 * 
 * Throws: `ExecuteTemplateException` if not recieved exactly 2 arguments.
 * 
 * Returns: 
 */
Variant le(Variant[] args...) {
    if (args.length != 2) {
        throw new ExecuteTemplateException("'le' expects exactly 2 arguments");
    }
    return Variant( args[0] <= args[1] );
}

/** 
 * Evaluates 'a < b'
 * 
 * Params:
 *   args = The arguments.
 * 
 * Throws: `ExecuteTemplateException` if not recieved exactly 2 arguments.
 * 
 * Returns: 
 */
Variant lt(Variant[] args...) {
    if (args.length != 2) {
        throw new ExecuteTemplateException("'lt' expects exactly 2 arguments");
    }
    return Variant( args[0] < args[1] );
}
