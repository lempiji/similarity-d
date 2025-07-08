/// Converts AST statements into simplified nodes and measures similarity.
/// Exposes `treeSimilarity` which leverages tree edit distance on normalized code.
module treediff;

import std.algorithm : min, max;
import functioncollector : FunctionInfo, collectFunctionsFromSource;
import treedistance : Node, NodeKind, ted, treeSize;

version(unittest) import testutils : DmdInitGuard;

import dmd.frontend : parseModule;
import dmd.statement : Statement, CompoundStatement, IfStatement, WhileStatement,
    ForStatement, ForeachStatement, ForeachRangeStatement, ReturnStatement,
    ExpStatement, TryCatchStatement, TryFinallyStatement, ScopeStatement,
    ConditionalStatement, StaticForeachStatement, CaseStatement, DefaultStatement,
    LabelStatement, GotoStatement, GotoDefaultStatement, GotoCaseStatement,
    BreakStatement, ContinueStatement, DoStatement, SwitchStatement,
    CaseRangeStatement, WithStatement, SynchronizedStatement, MixinStatement,
    ThrowStatement, DebugStatement, ScopeGuardStatement, SwitchErrorStatement,
    UnrolledLoopStatement, CompoundDeclarationStatement, CompoundAsmStatement,
    PragmaStatement, StaticAssertStatement, ImportStatement, AsmStatement,
    InlineAsmStatement, GccAsmStatement;
import dmd.expression : Expression, IdentifierExp, IntegerExp, StringExp,
    RealExp, ComplexExp, ThisExp, SuperExp, VarExp, DsymbolExp,
    TupleExp, ArrayLiteralExp, AssocArrayLiteralExp, StructLiteralExp,
    CompoundLiteralExp, NewExp, AssertExp, ThrowExp, MixinExp, ImportExp,
    TypeidExp, TraitsExp, IsExp, TypeExp, AddrExp, PtrExp, DeleteExp,
    CastExp, SliceExp, ArrayExp, IndexExp, ArrayLengthExp,
    DefaultInitExp, FileInitExp, LineInitExp, ModuleInitExp,
    FuncInitExp, PrettyFuncInitExp,
    BinExp, UnaExp, CallExp, CondExp, NullExp;
import dmd.hdrgen : EXPtoString;

private Node exprToNode(Expression e)
{
    if (e is null)
        return Node(NodeKind.Other, "", []);

    if (e.isIdentifierExp() || e.isVarExp() || e.isDsymbolExp())
        return Node(NodeKind.Identifier, "<id>", []);

    if (e.isIntegerExp() || e.isStringExp() || e.isRealExp() ||
        e.isComplexExp() || e.isDefaultInitExp() || e.isFileInitExp() ||
        e.isLineInitExp() || e.isModuleInitExp() || e.isFuncInitExp() ||
        e.isPrettyFuncInitExp())
        return Node(NodeKind.Literal, "<lit>", []);

    if (e.isThisExp())
        return Node(NodeKind.Keyword, "this", []);
    if (e.isSuperExp())
        return Node(NodeKind.Keyword, "super", []);
    if (e.isDollarExp())
        return Node(NodeKind.Keyword, "$", []);

    if (auto t = e.isTupleExp())
    {
        Node[] elems;
        if (t.exps)
            foreach (ex; *t.exps)
                elems ~= exprToNode(ex);
        return Node(NodeKind.Other, "tuple", elems);
    }

    if (auto arr = e.isArrayLiteralExp())
    {
        Node[] elems;
        if (arr.elements)
            foreach (ex; *arr.elements)
                elems ~= exprToNode(ex);
        return Node(NodeKind.Other, "arraylit", elems);
    }

    if (auto aa = e.isAssocArrayLiteralExp())
    {
        Node[] elems;
        if (aa.keys)
            foreach (i; 0 .. aa.keys.length)
                elems ~= Node(NodeKind.Other, "kv",
                    [exprToNode((*aa.keys)[i]), exprToNode((*aa.values)[i])]);
        return Node(NodeKind.Other, "assocarray", elems);
    }

    if (auto st = e.isStructLiteralExp())
    {
        Node[] elems;
        if (st.elements)
            foreach (ex; *st.elements)
                if (ex !is null)
                    elems ~= exprToNode(ex);
        return Node(NodeKind.Other, "struct", elems);
    }

    if (auto comp = e.isCompoundLiteralExp())
        return Node(NodeKind.Other, "compound", []);

    if (auto ne = e.isNewExp())
    {
        Node[] args;
        if (ne.arguments)
            foreach(a; *ne.arguments)
                args ~= exprToNode(a);
        return Node(NodeKind.Keyword, "new", args);
    }

    if (auto as = e.isAssertExp())
    {
        Node[] args = [exprToNode(as.e1)];
        if (as.msg)
            args ~= exprToNode(as.msg);
        return Node(NodeKind.Keyword, "assert", args);
    }

    if (auto th = e.isThrowExp())
        return Node(NodeKind.Keyword, "throw", [exprToNode(th.e1)]);

    if (auto mx = e.isMixinExp())
    {
        Node[] elems;
        if (mx.exps)
            foreach(ex; *mx.exps)
                elems ~= exprToNode(ex);
        return Node(NodeKind.Keyword, "mixin", elems);
    }

    if (auto ie = e.isImportExp())
        return Node(NodeKind.Keyword, "import", [exprToNode(ie.e1)]);

    if (e.isTypeExp())
        return Node(NodeKind.Keyword, "type", []);
    if (e.isTypeidExp())
        return Node(NodeKind.Keyword, "typeid", []);
    if (e.isTraitsExp())
        return Node(NodeKind.Keyword, "traits", []);
    if (e.isIsExp())
        return Node(NodeKind.Keyword, "is", []);

    if (auto a = e.isAddrExp())
        return Node(NodeKind.Operator, "&", [exprToNode(a.e1)]);
    if (auto p = e.isPtrExp())
        return Node(NodeKind.Operator, "*", [exprToNode(p.e1)]);
    if (auto d = e.isDeleteExp())
        return Node(NodeKind.Keyword, "delete", [exprToNode(d.e1)]);
    if (auto cst = e.isCastExp())
        return Node(NodeKind.Keyword, "cast", [exprToNode(cst.e1)]);

    if (auto sl = e.isSliceExp())
    {
        Node[] args = [exprToNode(sl.e1)];
        if (sl.lwr) args ~= exprToNode(sl.lwr);
        if (sl.upr) args ~= exprToNode(sl.upr);
        return Node(NodeKind.Operator, "slice", args);
    }

    if (auto ae = e.isArrayExp())
    {
        Node[] args = [exprToNode(ae.e1)];
        if (ae.arguments)
            foreach(a; *ae.arguments)
                args ~= exprToNode(a);
        return Node(NodeKind.Operator, "array", args);
    }

    if (auto idx = e.isIndexExp())
        return Node(NodeKind.Operator, "index", [exprToNode(idx.e1), exprToNode(idx.e2)]);

    if (auto len = e.isArrayLengthExp())
        return Node(NodeKind.Operator, "length", [exprToNode(len.e1)]);

    if (auto b = e.isBinExp())
        return Node(NodeKind.Operator, EXPtoString(b.op),
            [exprToNode(b.e1), exprToNode(b.e2)]);
    if (auto u = e.isUnaExp())
        return Node(NodeKind.Operator, EXPtoString(u.op),
            [exprToNode(u.e1)]);
    if (auto c = e.isCallExp())
    {
        Node[] args = [exprToNode(c.e1)];
        if (c.arguments)
            foreach(a; *c.arguments)
                args ~= exprToNode(a);
        return Node(NodeKind.Keyword, "call", args);
    }
    if (auto q = e.isCondExp())
        return Node(NodeKind.Operator, "?:",
            [exprToNode(q.econd), exprToNode(q.e1), exprToNode(q.e2)]);
    if (e.isNullExp())
        return Node(NodeKind.Literal, "<lit>", []);

    return Node(NodeKind.Other, EXPtoString(e.op), []);
}

private Node stmtToNode(Statement s)
{
    if (s is null)
        return Node(NodeKind.Other, "", []);
    if (auto cs = s.isCompoundStatement())
    {
        Node[] ch;
        if (cs.statements)
            foreach(st; *cs.statements)
                ch ~= stmtToNode(st);
        return Node(NodeKind.Other, "compound", ch);
    }
    if (auto sc = s.isScopeStatement())
        return stmtToNode(sc.statement);
    if (auto conds = s.isConditionalStatement())
        return Node(NodeKind.Keyword, "static-if",
            [stmtToNode(conds.ifbody), stmtToNode(conds.elsebody)]);
    if (auto sf = s.isStaticForeachStatement())
        return Node(NodeKind.Keyword, "staticforeach", []);
    if (auto rs = s.isReturnStatement())
        return Node(NodeKind.Keyword, "return",
            [exprToNode(rs.exp)]);
    if (auto ifs = s.isIfStatement())
        return Node(NodeKind.Keyword, "if",
            [exprToNode(ifs.condition), stmtToNode(ifs.ifbody),
             stmtToNode(ifs.elsebody)]);
    if (auto ws = s.isWhileStatement())
        return Node(NodeKind.Keyword, "while",
            [exprToNode(ws.condition), stmtToNode(ws._body)]);
    if (auto fs = s.isForStatement())
        return Node(NodeKind.Keyword, "for",
            [stmtToNode(fs._init), exprToNode(fs.condition),
             exprToNode(fs.increment), stmtToNode(fs._body)]);
    if (auto fes = s.isForeachStatement())
        return Node(NodeKind.Keyword, "foreach",
            [exprToNode(fes.aggr), stmtToNode(fes._body)]);
    if (auto fr = s.isForeachRangeStatement())
        return Node(NodeKind.Keyword, "foreachrange",
            [exprToNode(fr.lwr), exprToNode(fr.upr), stmtToNode(fr._body)]);
    if (auto ex = s.isExpStatement())
        return Node(NodeKind.Other, "exp", [exprToNode(ex.exp)]);
    if (auto lbl = s.isLabelStatement())
        return Node(NodeKind.Other, "label", [stmtToNode(lbl.statement)]);
    if (auto gt = s.isGotoStatement())
        return Node(NodeKind.Keyword, "goto",
            [Node(NodeKind.Identifier, "<id>", [])]);
    if (auto gtd = s.isGotoDefaultStatement())
        return Node(NodeKind.Keyword, "gotodefault", []);
    if (auto gtc = s.isGotoCaseStatement())
        return Node(NodeKind.Keyword, "gotocase",
            [exprToNode(gtc.exp)]);
    if (auto br = s.isBreakStatement())
        return Node(NodeKind.Keyword, "break", []);
    if (auto cont = s.isContinueStatement())
        return Node(NodeKind.Keyword, "continue", []);
    if (auto dos = s.isDoStatement())
        return Node(NodeKind.Keyword, "do",
            [stmtToNode(dos._body), exprToNode(dos.condition)]);
    if (auto sw = s.isSwitchStatement())
        return Node(NodeKind.Keyword, "switch",
            [exprToNode(sw.condition), stmtToNode(sw._body)]);
    if (auto csw = s.isCaseStatement())
        return Node(NodeKind.Keyword, "case",
            [exprToNode(csw.exp), stmtToNode(csw.statement)]);
    if (auto cr = s.isCaseRangeStatement())
        return Node(NodeKind.Keyword, "caserange",
            [exprToNode(cr.first), exprToNode(cr.last), stmtToNode(cr.statement)]);
    if (auto def = s.isDefaultStatement())
        return Node(NodeKind.Keyword, "default", [stmtToNode(def.statement)]);
    if (auto sync = s.isSynchronizedStatement())
        return Node(NodeKind.Keyword, "synchronized",
            [exprToNode(sync.exp), stmtToNode(sync._body)]);
    if (auto w = s.isWithStatement())
        return Node(NodeKind.Keyword, "with",
            [exprToNode(w.exp), stmtToNode(w._body)]);
    if (auto mx = s.isMixinStatement())
    {
        Node[] elems;
        if (mx.exps)
            foreach(ex; *mx.exps)
                elems ~= exprToNode(ex);
        return Node(NodeKind.Keyword, "mixin", elems);
    }
    if (auto tc = s.isTryCatchStatement())
        return Node(NodeKind.Keyword, "try",
            [stmtToNode(tc._body)]);
    if (auto tf = s.isTryFinallyStatement())
        return Node(NodeKind.Keyword, "try",
            [stmtToNode(tf._body), stmtToNode(tf.finalbody)]);
    if (auto th = s.isThrowStatement())
        return Node(NodeKind.Keyword, "throw", [exprToNode(th.exp)]);
    if (auto dbg = s.isDebugStatement())
        return Node(NodeKind.Keyword, "debug", [stmtToNode(dbg.statement)]);
    if (auto sg = s.isScopeGuardStatement())
        return Node(NodeKind.Keyword, "scope", [stmtToNode(sg.statement)]);
    if (auto se = s.isSwitchErrorStatement())
        return Node(NodeKind.Keyword, "switcherror", []);
    if (auto ur = s.isUnrolledLoopStatement())
    {
        Node[] ch;
        if (ur.statements)
            foreach(st; *ur.statements)
                ch ~= stmtToNode(st);
        return Node(NodeKind.Other, "unrolled", ch);
    }
    if (auto cd = s.isCompoundDeclarationStatement())
    {
        Node[] ch;
        if (cd.statements)
            foreach(st; *cd.statements)
                ch ~= stmtToNode(st);
        return Node(NodeKind.Other, "compounddecl", ch);
    }
    if (auto ca = s.isCompoundAsmStatement())
    {
        Node[] ch;
        if (ca.statements)
            foreach(st; *ca.statements)
                ch ~= stmtToNode(st);
        return Node(NodeKind.Keyword, "asm", ch);
    }
    if (auto pr = s.isPragmaStatement())
    {
        Node[] args;
        if (pr.args)
            foreach(a; *pr.args)
                args ~= exprToNode(a);
        if (pr._body)
            args ~= stmtToNode(pr._body);
        return Node(NodeKind.Keyword, "pragma", args);
    }
    if (auto sa = s.isStaticAssertStatement())
        return Node(NodeKind.Keyword, "staticassert", []);
    if (auto imp = s.isImportStatement())
        return Node(NodeKind.Keyword, "import", []);
    if (auto asmStmt = s.isAsmStatement())
        return Node(NodeKind.Keyword, "asm", []);
    if (auto inAsm = s.isInlineAsmStatement())
        return Node(NodeKind.Keyword, "asm", []);
    if (auto gccAsm = s.isGccAsmStatement())
        return Node(NodeKind.Keyword, "asm", []);
    return Node(NodeKind.Other, "stmt", []);
}

/// Convert a `FunctionInfo` instance into a simplified AST used for similarity
/// comparisons.  Identifiers and literals are normalized and the resulting tree
/// is rooted at a single placeholder node.
public Node normalizedAst(FunctionInfo f)
{
    Node[] children;
    if (f.funcDecl)
        children ~= stmtToNode(f.funcDecl.fbody);
    return Node(NodeKind.Other, "root", children);
}

/// Recursively search `n` for a node with matching `value`. This helper is
/// only used in unit tests so it is wrapped in `version(unittest)` to avoid
/// being part of the public library. When adding test helpers in the future,
/// prefer guarding them with `version(unittest)` as well.
version(unittest)
private bool containsNode(Node n, string value)
{
    if (n.value == value)
        return true;
    foreach (c; n.children)
        if (containsNode(c, value))
            return true;
    return false;
}

/// Return the number of AST nodes in the normalized tree for `f`.
public size_t nodeCount(FunctionInfo f)
{
    // subtract one to ignore the artificial root node
    return treeSize(normalizedAst(f)) - 1;
}

unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(){ return 1; }
};
    auto funcs = collectFunctionsFromSource("ast.d", code);
    assert(funcs.length == 1);
    auto n = normalizedAst(funcs[0]);
    assert(n.children.length == 1);
    auto c = n.children[0];
    assert(c.kind == NodeKind.Other); // compound
    assert(c.children.length == 1);
    assert(c.children[0].kind == NodeKind.Keyword);
    assert(c.children[0].children.length == 1);
    assert(c.children[0].children[0].kind == NodeKind.Literal);
}

unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(){ return 1; }
};
    auto funcs = collectFunctionsFromSource("count.d", code);
    assert(funcs.length == 1);
    auto ast = normalizedAst(funcs[0]);
    assert(nodeCount(funcs[0]) == treeSize(ast) - 1);
}

/// ensure exprToNode covers additional expression forms
unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
class C{ int x; this(int n){ this.x = n; } }
C foo(){
    auto a = [1,2];
    assert(a.length > 0);
    auto b = new C(a[0]);
    return b.x;
}
};
    auto funcs = collectFunctionsFromSource("expr.d", code);
    assert(funcs.length >= 2);
    auto ast = normalizedAst(funcs[1]);

    assert(containsNode(ast, "assert"));
}

/// Compute a similarity score between two functions using tree edit distance.
/// When `sizePenalty` is enabled the result is scaled by the ratio of the
/// smaller tree size to the larger one so that very small functions do not
/// receive disproportionately high scores.
public double treeSimilarity(FunctionInfo a, FunctionInfo b, bool sizePenalty=true)
{
    auto ta = normalizedAst(a);
    auto tb = normalizedAst(b);
    auto sizeA = treeSize(ta) - 1; // ignore root node
    auto sizeB = treeSize(tb) - 1;
    if (sizeA == 0 && sizeB == 0)
        return 1.0;
    auto dist = ted(ta, tb);
    auto maxlen = max(sizeA, sizeB);
    double score = 1.0 - cast(double)dist / maxlen;
    // clamp to [0,1] in case dist > maxlen or negative rounding issues
    if (score < 0) score = 0;
    if (score > 1) score = 1;

    if (sizePenalty && maxlen > 0)
    {
        double penalty = cast(double)min(sizeA, sizeB) / maxlen;
        score *= penalty;
    }
    return score;
}

unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int x){ return x + 1; }
int bar(int y){ return y + 1; }
};
    auto funcs = collectFunctionsFromSource("t.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    assert(isClose(sim, 1.0));

    code = q{
int a(){ return 0; }
int b(){ return 0 + 1; }
};
    funcs = collectFunctionsFromSource("t2.d", code);
    assert(funcs.length == 2);
    sim = treeSimilarity(funcs[0], funcs[1]);
    assert(sim > 0.23 && sim < 0.25);
}

/// Variable renaming should not affect similarity
unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(){ int a = 1; return a; }
int bar(){ int b = 1; return b; }
};
    auto funcs = collectFunctionsFromSource("rename.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // Renaming variables should yield identical trees
    import std.math : isClose;
    assert(isClose(sim, 1.0));
}

/// Binary operator change should keep similarity high
unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int x){ return x + 1; }
int bar(int x){ return x - 1; }
};
    auto funcs = collectFunctionsFromSource("op.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // Only the operator differs -> expect high similarity (~0.8)
    assert(isClose(sim, 0.8, 0.01));
}

/// Literal differences should have minimal impact
unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(){ return 1; }
int bar(){ return 2; }
};
    auto funcs = collectFunctionsFromSource("lit.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // Literal changes shouldn't affect similarity
    import std.math : isClose;
    assert(isClose(sim, 1.0));
}

/// Additional if statement near the root should keep high similarity
unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int x){
    if(x > 0) return x;
    return -x;
}
int bar(int x){
    return x > 0 ? x : -x;
}
};
    auto funcs = collectFunctionsFromSource("if.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // Extra branch lowers similarity to about 0.05
    assert(sim > 0 && sim < 0.1);
}

/// Wrapping body in try-catch should not drastically lower similarity
unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(){ return 1; }
int bar(){ try{ return 1; }catch(Exception e){ return 0; } }
};
    auto funcs = collectFunctionsFromSource("try.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // Try/catch wrapper produces similarity around 0.12
    assert(sim > 0.1 && sim < 0.2);
}

/// Leaf level expression change should keep similarity high
unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int x){ return x + 1; }
int bar(int x){ return x + 2; }
};
    auto funcs = collectFunctionsFromSource("leaf.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // Expression tweak keeps similarity almost perfect
    import std.math : isClose;
    assert(isClose(sim, 1.0));
}

/// for and foreach loops should be considered similar
unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int[] a){ int s=0; for(int i=0;i<a.length;i++) s+=a[i]; return s; }
int bar(int[] a){ int s=0; foreach(i; a) s+=i; return s; }
};
    auto funcs = collectFunctionsFromSource("loop.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // for vs foreach yields around 0.2 similarity
    assert(sim > 0.15 && sim < 0.25);
}

/// for and while loops also share structure
unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int n){ int i=0; for(; i<n; ++i){} return i; }
int bar(int n){ int i=0; while(i<n) ++i; return i; }
};
    auto funcs = collectFunctionsFromSource("loop2.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // for vs while yields about 0.5 similarity
    assert(sim > 0.45 && sim < 0.55);
}

/// Nested if differences
unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int x){ if(x>0){ if(x>1) return x;} return -x; }
int bar(int x){ if(x>0) return x; return -x; }
};
    auto funcs = collectFunctionsFromSource("nested.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // Nested conditionals drop similarity to about 0.34
    assert(sim > 0.3 && sim < 0.4);
}

/// Completely different functions should score low
unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(){ return 1; }
void bar(string s){ import std.stdio; writeln(s); }
};
    auto funcs = collectFunctionsFromSource("diff.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // Expect very low similarity (~0.12)
    assert(sim > 0 && sim < 0.2);
}

/// stmtToNode should recognize various statement forms
unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int x){
    L1: for(int i=0;i<x;i++){
        if(i==1) continue;
        if(i==2) break;
        goto L1;
    }
    switch(x){
        case 1: goto L1;
        default: break;
    }
    do { --x; } while(x > 0);
    return x;
}
};
    auto funcs = collectFunctionsFromSource("stmt.d", code);
    assert(funcs.length == 1);
    auto ast = normalizedAst(funcs[0]);

    assert(containsNode(ast, "break"));
    assert(containsNode(ast, "continue"));
    assert(containsNode(ast, "goto"));
    assert(containsNode(ast, "case"));
    assert(containsNode(ast, "default"));
    assert(containsNode(ast, "do"));
}

/// Renaming identifiers across parameters and locals yields full similarity
unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int a){ int x = a * 2; return x; }
int bar(int b){ int y = b * 2; return y; }
};
    auto funcs = collectFunctionsFromSource("rename2.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // variable and parameter names differ but structure identical -> ~1.0
    assert(isClose(sim, 1.0));
}

/// Changing literal values should not lower similarity
unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(){ return 42; }
int bar(){ return 1337; }
};
    auto funcs = collectFunctionsFromSource("literal2.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    // literals normalized -> expect 1.0
    assert(isClose(sim, 1.0));
}

/// Variations in loop form still yield high similarity
unittest
{

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(int n){ int i=0; do{ ++i; } while(i<n); return i; }
int bar(int n){ int i=0; while(i<n){ ++i; } return i; }
};
    auto funcs = collectFunctionsFromSource("loop3.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    import std.math : isClose;
    // do-while vs while loops retain partial structural similarity
    assert(isClose(sim, 0.461538, 0.01));
}

unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int a(){ return 0; }
int b(){ return 1; }
};
    auto funcs = collectFunctionsFromSource("penalty.d", code);
    auto sim = treeSimilarity(funcs[0], funcs[1], false);
    assert(sim >= 0 && sim <= 1);
}

unittest
{
    import std.math : isClose;

    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
void foo(){}
void bar(){}
};
    auto funcs = collectFunctionsFromSource("empty.d", code);
    assert(funcs.length == 2);
    auto sim = treeSimilarity(funcs[0], funcs[1]);
    assert(isClose(sim, 1.0));
}
