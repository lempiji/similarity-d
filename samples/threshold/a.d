int shortFunc()
{
    int x = 0;
    for(int i = 0; i < 10; ++i)
        x += i;
    return x;
}

int biggerFunc()
{
    int y = 0;
    for(int i = 0; i < 5; ++i)
        y += i * 2;
    if (y > 10)
        y += 3;
    return y;
}
