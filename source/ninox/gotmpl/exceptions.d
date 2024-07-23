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
 * Module containing all exception types.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module ninox.gotmpl.exceptions;

class TemplateException : Exception {
    @nogc @safe pure nothrow this(string msg, Throwable nextInChain = null, string file = __FILE__, size_t line = __LINE__) {
        super(msg, nextInChain, file, line);
    }
}

class ParseTemplateException : TemplateException {
    @nogc @safe pure nothrow this(string msg, Throwable nextInChain = null, string file = __FILE__, size_t line = __LINE__) {
        super(msg, nextInChain, file, line);
    }
}

class ExecuteTemplateException : TemplateException {
    @nogc @safe pure nothrow this(string msg, Throwable nextInChain = null, string file = __FILE__, size_t line = __LINE__) {
        super(msg, nextInChain, file, line);
    }
}
