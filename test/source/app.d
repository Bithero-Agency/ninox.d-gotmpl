import std.stdio;

import ninox.gotmpl;
import ninox.std.variant;
import ninox.std.traits;
import ninox.std.callable;

struct Test {
    string name;
    string content;
    Variant data;
    FuncMap globals;
    string result;

    private static void defSetup(ref Test t) {}
    private static bool defCheck(ref Test t, Template tmpl, string res) => res == t.result;

    alias Setup = Callable!(void, RefT!Test);
    Setup setup = &defSetup;

    alias Check = Callable!(bool, RefT!Test, Template, string);
    Check check = &defCheck;

    bool run() {
        writeln("==================== Test: ", this.name, " ====================");
        this.setup(this);
        auto tmpl = Template.parseString(this.name, this.content);
        tmpl.globals = this.globals;
        //writeln("----- Execute:");
        string res;
        tmpl.execute(
            (const char[] data) {
                res ~= data;
            },
            this.data
        );
        bool isOk = this.check(this, tmpl, res);
        writeln("----- Result: ", isOk ? "ok" : "error");

        if (!isOk) {
            writeln(res);
            writeln("----- Dump:");
            tmpl.dump();
        }

        return isOk;
    }
}

struct Job {
    string name;
}

struct Other {
    int i;
}

struct Person {
    string name;
    private int age;
    Job job;

    int getAge() {
        return this.age;
    }

    int getAgeMul(int m) {
        return this.age * m;
    }

    Other getOther(int i) {
        return Other(i);
    }
}

Test[] testEval() {
    return [
        Test(
            name: "testEval_dot",
            content: "{{.}}",
            data: Variant("hello"),
            result: "hello",
        ),
        Test(
            name: "testEval_field",
            content: "{{.name}}",
            data: Variant(Person( name: "Joe" )),
            result: "Joe",
        ),
        Test(
            name: "testEval_nestedField",
            content: "{{.job.name}}",
            data: Variant(Person( job: Job("Teacher") )),
            result: "Teacher",
        ),
        Test(
            name: "testEval_method",
            content: "{{.getAge}}",
            data: Variant(Person( age: 24 )),
            result: "24",
        ),
        Test(
            name: "testEval_method_withParams",
            content: "{{.getAgeMul 2}}",
            data: Variant(Person( age: 24 )),
            result: "48",
        ),
        Test(
            name: "testEval_subPipeline",
            content: "{{ (.getOther 12).i }}",
            data: Variant(Person()),
            result: "12",
        ),
        Test(
            name: "testEval_func",
            content: "{{ reverseNum 1234 }}",
            globals: [
                "reverseNum": Variant((int n) {
                    import std.conv : to;
                    import std.range : retro;
                    return n.to!string.retro.to!int;
                }),
            ],
            result: "4321",
        ),
        Test(
            name: "testEval_cmds",
            content: "{{ 1 | add 2 }}",
            globals: [
                "add": Variant((int i, int j) {
                    return i + j;
                }),
            ],
            result: "3",
        ),
        Test(
            name: "testEval_rootDollar",
            content: "{{$}}",
            data: Variant("hello"),
            result: "hello",
        ),
    ];
}

Test[] testLit() {
    return [
        Test(
            name: "testLit_true",
            content: "{{true}}",
            result: "true",
        ),
        Test(
            name: "testLit_false",
            content: "{{false}}",
            result: "false",
        ),
        Test(
            name: "testLit_number",
            content: "{{12}} {{012}} {{0x1f}} {{0o70}} {{0b100}} {{0.14}} {{1.23e+1}} {{0x1.2p+1}}",
            result: "12 12 31 56 4 0.14 12.3 2.25",
        ),
        Test(
            name: "testLit_char",
            content: "{{'a'}} {{'\\t'}}",
            result: "a \t",
        ),
        Test(
            name: "testLit_string",
            content: `{{"abc"}} {{"a\tb"}}`,
            result: "abc a\tb",
        ),
        Test(
            name: "testLit_rawString",
            content: "{{`a\tb`}}",
            result: "a\tb",
        ),
    ];
}

Test[] testVars() {
    return [
        Test(
            name: "testVars_decl",
            content: "{{ $x := 1 }}{{$x}}",
            result: "1",
        ),
        Test(
            name: "testVars_assign",
            content: "{{ $x := 1 }}{{ $x = 2 }}{{$x}}",
            result: "2",
        ),
        Test(
            name: "testVars_scope",
            content: "{{$x := 1}}{{if true}}{{$x := 2}}{{$x}}{{end}} {{$x}}",
            result: "2 1",
        ),
    ];
}

Test[] testIf() {
    return [
        Test(
            name: "testIf_true",
            content: "{{if true}}T0{{else}}T1{{end}}",
            result: "T0",
        ),
        Test(
            name: "testIf_false",
            content: "{{if false}}T0{{else}}T1{{end}}",
            result: "T1",
        ),
        Test(
            name: "testIf_elseIf_true",
            content: "{{if false}}T0{{else if true}}T1{{else}}T2{{end}}",
            result: "T1",
        ),
        Test(
            name: "testIf_elseIf_false",
            content: "{{if false}}T0{{else if false}}T1{{else}}T2{{end}}",
            result: "T2",
        ),
    ];
}

Test[] testWith() {
    return [
        Test(
            name: "testWith_object",
            content: "{{with .job}}{{.name}}{{end}} {{.name}}",
            data: Variant(Person( name: "Joe", job: Job("Teacher") )),
            result: "Teacher Joe",
        ),
        Test(
            name: "testWith_scalar",
            content: "{{with .getAge}}{{.}}{{else}}unborn{{end}}",
            data: Variant(Person( age: 24 )),
            result: "24",
        ),
        Test(
            name: "testWith_scalar_else",
            content: "{{with .getAge}}{{.}}{{else}}unborn{{end}}",
            data: Variant(Person( age: 0 )),
            result: "unborn",
        ),
        Test(
            name: "testWith_rootDollar",
            content: "{{with .job}}{{.name}} {{$.name}}{{end}}",
            data: Variant(Person( name: "Joe", job: Job("Teacher") )),
            result: "Teacher Joe",
        ),
    ];
}

Test[] testLoop() {
    return [
        Test(
            name: "testLoop_single",
            content: "{{range .}}{{.}}{{end}}",
            data: Variant(['a', 'b']),
            result: "ab",
        ),
        Test(
            name: "testLoop_break",
            content: "{{range .}}{{if ge . 10}}{{break}}{{end}}{{.}}{{end}}",
            data: Variant([5, 10, 15]),
            globals: [
                "ge": Variant((int a, int b) {
                    return a >= b;
                }),
            ],
            result: "5",
        ),
        Test(
            name: "testLoop_continue",
            content: "{{range .}}{{if eq . 10}}{{continue}}{{end}} {{.}}{{end}}",
            data: Variant([5, 10, 15]),
            globals: [
                "eq": Variant((int a, int b) {
                    return a == b;
                }),
            ],
            result: " 5 15",
        ),
        Test(
            name: "testLoop_1var",
            content: "{{range $e := .}} {{$e}}{{end}}",
            data: Variant([5, 10, 15]),
            result: " 5 10 15",
        ),
        Test(
            name: "testLoop_2var",
            content: "{{range $i, $e := .}} {{$i}}=>{{$e}}{{end}}",
            data: Variant([5, 10, 15]),
            result: " 0=>5 1=>10 2=>15",
        ),
    ];
}

Test[] testDefine() {
    return [
        Test(
            name: "testDefine_defineOnly",
            content: "{{define \"a\"}}b{{end}}",
            check: Test.Check((ref Test t, Template tmpl, string _) {
                auto a = tmpl.getTemplate("a");
                import ninox.gotmpl.nodes : TextNode;
                return a !is null
                    && a.name == "a"
                    && a.block.length == 1
                    && (cast(TextNode) a.block[0]) !is null
                    && (cast(TextNode) a.block[0]).content == "b"
                ;
            }),
        ),
        Test(
            name: "testDefine_call",
            content: "{{define \"a\"}}b{{end}}{{template \"a\"}}",
            result: "b",
        ),
        Test(
            name: "testDefine_callWithParam",
            content: "{{define \"a\"}}{{.}} {{$}}{{end}}{{template \"a\" 12}}",
            result: "12 12",
        ),
        Test(
            name: "testBlock",
            content: "{{block \"a\" 12}}{{.}}{{end}}",
            result: "12",
        ),
    ];
}

Test[] testBuiltins() {
    int tmp = 1;
    return [
        // 'or' special case
        Test(
            name: "testBuiltin_or1",
            content: "{{ or (t) (t) }}",
            globals: [
                "t": Variant({
                    auto t = tmp;
                    tmp++;
                    return t;
                }),
            ],
            setup: Test.Setup((ref Test test) {
                tmp = 1;
            }),
            check: Test.Check((ref Test test, Template tmpl, string res) {
                return res == "1" && tmp == 2;
            }),
        ),
        Test(
            name: "testBuiltin_or2",
            content: "{{ or2 (t) (t) }}",
            globals: [
                "or2": Variant((int a, int b) {
                    return a || b;
                }),
                "t": Variant({
                    auto t = tmp;
                    tmp++;
                    return t;
                }),
            ],
            setup: Test.Setup((ref Test test) {
                tmp = 1;
            }),
            check: Test.Check((ref Test test, Template tmpl, string res) {
                return res == "true" && tmp == 3;
            }),
        ),

        // 'and' special case
        Test(
            name: "testBuiltin_and1",
            content: "{{ and (t) (t) }}",
            globals: [
                "t": Variant({
                    auto t = tmp;
                    tmp++;
                    return t;
                }),
            ],
            setup: Test.Setup((ref Test test) {
                tmp = 1;
            }),
            check: Test.Check((ref Test test, Template tmpl, string res) {
                return res == "2" && tmp == 3;
            }),
        ),
        Test(
            name: "testBuiltin_and2",
            content: "{{ and (t) (t) }}",
            globals: [
                "t": Variant({
                    auto t = tmp;
                    tmp++;
                    return t;
                }),
            ],
            setup: Test.Setup((ref Test test) {
                tmp = 0;
            }),
            check: Test.Check((ref Test test, Template tmpl, string res) {
                return res == "0" && tmp == 1;
            }),
        ),

        // 'call'
        Test(
            name: "testBuiltin_call",
            content: "{{ call . 1 2 }}",
            data: Variant((int a, int b) => a + b),
            result: "3",
        ),

        // 'index'
        Test(
            name: "testBuiltin_indexSingle",
            content: "{{ index . 1 }}",
            data: Variant([11, 22]),
            result: "22",
        ),
        Test(
            name: "testBuiltin_indexMulti",
            content: "{{ index . 1 2 }}",
            data: Variant([ [] , [11, 22, 33] ]),
            result: "33",
        ),

        // 'len'
        Test(
            name: "testBuiltin_len",
            content: "{{ len . }}",
            data: Variant([11, 22]),
            result: "2",
        ),

        // 'not'
        Test(
            name: "testBuiltin_not",
            content: "{{ not false }}",
            result: "true",
        ),

        // 'print'
        Test(
            name: "testBuiltin_print",
            content: `{{ print "a" "b" }}|{{ print 1 2 }}|{{ print 1 "a" }}`,
            result: "ab|1 2|1a",
        ),

        // 'println'
        Test(
            name: "testBuiltin_println",
            content: `{{ println "a" "b" }}|{{ println 1 2 }}|{{ println 1 "a" }}`,
            result: "a b\n|1 2\n|1 a\n",
        ),

        // 'eq', 'ne'
        Test(
            name: "testBuiltin_eq",
            content: `{{ eq "hello" "hello" }} {{ eq "hello" 1 }} {{ eq "hello" 1 "hello" }}`,
            result: "true false true",
        ),
        Test(
            name: "testBuiltin_ne",
            content: `{{ ne "hello" "hello" }} {{ ne "hello" 1 }} {{ ne "hello" 1 "hello" }}`,
            result: "false true false",
        ),

        // 'ge', 'gt'
        Test(
            name: "testBuiltin_ge",
            content: `{{ ge 1 2 }} {{ ge 2 2 }} {{ ge 3 2 }}`,
            result: "false true true",
        ),
        Test(
            name: "testBuiltin_gt",
            content: `{{ gt 1 2 }} {{ gt 2 2 }} {{ gt 3 2 }}`,
            result: "false false true",
        ),

        // 'le', 'lt'
        Test(
            name: "testBuiltin_le",
            content: `{{ le 1 2 }} {{ le 2 2 }} {{ le 3 2 }}`,
            result: "true true false",
        ),
        Test(
            name: "testBuiltin_lt",
            content: `{{ lt 1 2 }} {{ lt 2 2 }} {{ lt 3 2 }}`,
            result: "true false false",
        ),
    ];
}

Test[] testTrim() {
    return [
        Test(
            name: "testTrim_none",
            content: `  {{"a"}}  `,
            result: "  a  ",
        ),
        Test(
            name: "testTrim_before",
            content: `  {{- "a"}}  `,
            result: "a  ",
        ),
        Test(
            name: "testTrim_after",
            content: `  {{"a" -}}  `,
            result: "  a",
        ),
        Test(
            name: "testTrim_around",
            content: `  {{- "a" -}}  `,
            result: "a",
        ),
    ];
}

int main(string[] args) {

    import std.array : join;
    Test[] tests = join([
        testEval(),
        testLit(),
        testVars(),
        testIf(),
        testWith(),
        testLoop(),
        testDefine(),
        testBuiltins(),
        testTrim(),
    ]);

    bool isAllOk = true;

    if (args.length > 1) {
        foreach (ref test; tests) {
            import std.string : startsWith;
            if (test.name.startsWith(args[1])) {
                if (!test.run()) {
                    isAllOk = false;
                }
            }
        }
    }
    else {
        foreach (ref test; tests) {
            if(!test.run()) {
                isAllOk = false;
            }
        }
    }

    return isAllOk ? 0 : -1;
}
