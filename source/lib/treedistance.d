module treedistance;

import std.algorithm : min;
import std.typecons : Tuple;

/// Kinds of AST nodes used for tree edit distance.
public enum NodeKind
{
    Identifier,
    Literal,
    Keyword,
    Operator,
    Other
}

/// Simple tree node for TED.
public struct Node
{
    NodeKind kind;
    string value;
    Node[] children;
}

/// Compute the size (number of nodes) of a subtree.
public size_t treeSize(Node n)
{
    size_t s = 1;
    foreach (c; n.children)
        s += treeSize(c);
    return s;
}

/// Compute the tree edit distance between two nodes.
public size_t ted(Node a, Node b)
{
    size_t m = a.children.length;
    size_t n = b.children.length;
    size_t[][] dp = new size_t[][](m + 1, n + 1);

    dp[0][0] = 0;
    foreach (i; 1 .. m + 1)
        dp[i][0] = dp[i - 1][0] + treeSize(a.children[i - 1]);
    foreach (j; 1 .. n + 1)
        dp[0][j] = dp[0][j - 1] + treeSize(b.children[j - 1]);

    for (size_t i = 1; i <= m; ++i)
    {
        for (size_t j = 1; j <= n; ++j)
        {
            auto delCost = dp[i - 1][j] + treeSize(a.children[i - 1]);
            auto insCost = dp[i][j - 1] + treeSize(b.children[j - 1]);
            auto repCost = dp[i - 1][j - 1] + ted(a.children[i - 1], b.children[j - 1]);
            dp[i][j] = min(delCost, insCost, repCost);
        }
    }

    size_t cost = (a.kind == b.kind && a.value == b.value) ? 0 : 1;
    return cost + dp[m][n];
}

unittest
{
    Node leaf(NodeKind k, string v)
    {
        return Node(k, v, []);
    }
    auto a = Node(NodeKind.Other, "", [leaf(NodeKind.Identifier, "<id>"), leaf(NodeKind.Literal, "<lit>")]);
    auto b = Node(NodeKind.Other, "", [leaf(NodeKind.Identifier, "<id>"), leaf(NodeKind.Literal, "<lit>"), leaf(NodeKind.Keyword, "if")]);
    assert(ted(a, a) == 0);
    assert(ted(a, b) == 1); // one insertion
}
