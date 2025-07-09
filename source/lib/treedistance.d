/// Implements a basic tree edit distance algorithm over lightweight nodes.
/// Defines `Node` and `NodeKind` utilities used by higher-level modules.
module treedistance;

import std.algorithm : min;

/// Kinds of AST nodes used for tree edit distance.
public enum NodeKind
{
    /// Node representing a variable or function name.
    Identifier,
    /// Node representing a numeric or string literal.
    Literal,
    /// Node for language keywords such as `if` or `return`.
    Keyword,
    /// Node for operators like `+`, `-` or `*`.
    Operator,
    /// Fallback node type for uncategorized tokens.
    Other
}

/// Simple tree node for TED.
public struct Node
{
    /// Classification used by the distance algorithm.
    NodeKind kind;
    /// Normalized identifier or literal text.
    string value;
    /// Child nodes that form the subtree.
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

version(unittest)
{
    /// Convenience helper for constructing a leaf node in tests.
    private Node leaf(NodeKind k, string v)
    {
        return Node(k, v, []);
    }
}

unittest
{
    auto nodeA = Node(NodeKind.Other, "",
        [leaf(NodeKind.Identifier, "<id>"),
         leaf(NodeKind.Literal, "<lit>")]);
    auto nodeB = Node(NodeKind.Other, "",
        [leaf(NodeKind.Identifier, "<id>"),
         leaf(NodeKind.Literal, "<lit>"),
         leaf(NodeKind.Keyword, "if")]);
    assert(ted(nodeA, nodeA) == 0);
    assert(ted(nodeA, nodeB) == 1); // one insertion

    // Deleting a subtree should cost its size (3 nodes here).
    auto complex = Node(NodeKind.Other, "",
        [Node(NodeKind.Other, "",
            [leaf(NodeKind.Identifier, "x"),
             leaf(NodeKind.Literal, "1")]),
         leaf(NodeKind.Keyword, "if")]);
    auto withoutSub = Node(NodeKind.Other, "",
        [leaf(NodeKind.Keyword, "if")]);
    assert(ted(complex, withoutSub) == 3);

    // Replacing a child's label costs 1 when structure is the same.
    auto c = Node(NodeKind.Other, "",
        [leaf(NodeKind.Identifier, "a"),
         leaf(NodeKind.Literal, "lit")]);
    auto d = Node(NodeKind.Other, "",
        [leaf(NodeKind.Identifier, "b"),
         leaf(NodeKind.Literal, "lit")]);
    assert(ted(c, d) == 1);

    // Symmetry property.
    assert(ted(nodeA, nodeB) == ted(nodeB, nodeA));
}

unittest
{


    auto original = Node(NodeKind.Other, "", [
        leaf(NodeKind.Identifier, "<id>"),
        leaf(NodeKind.Literal, "<lit>")
    ]);
    auto removed = Node(NodeKind.Other, "", [
        leaf(NodeKind.Identifier, "<id>")
    ]);

    assert(ted(original, removed) == 1); // one deletion
}

unittest
{


    auto original = Node(NodeKind.Other, "", [
        leaf(NodeKind.Identifier, "<id>"),
        leaf(NodeKind.Literal, "<lit>")
    ]);
    auto replaced = Node(NodeKind.Other, "", [
        leaf(NodeKind.Keyword, "for"),
        leaf(NodeKind.Literal, "<lit>")
    ]);

    assert(ted(original, replaced) == 1); // one replacement
}


unittest
{
    auto single = leaf(NodeKind.Identifier, "solo");
    assert(treeSize(single) == 1);
}

unittest
{
    auto empty = Node.init;
    auto tree = Node(NodeKind.Other, "", [
        leaf(NodeKind.Identifier, "x"),
        leaf(NodeKind.Literal, "1")
    ]);

    assert(ted(empty, tree) == treeSize(tree));
    assert(ted(tree, empty) == treeSize(tree));
    assert(ted(empty, empty) == 0);
}
