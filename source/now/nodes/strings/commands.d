module now.nodes.strings.commands;

import std.array;
import std.conv : ConvException;
import std.file : dirEntries, SpanMode;
import std.regex : matchAll, matchFirst;
import std.string;
import std.algorithm.mutation : strip, stripLeft, stripRight;

import now.conv;
import now.nodes;


static this()
{
    stringCommands["eval"] = function (string path, Context context)
    {
        import now.grammar;

        /*
        > eval "set x 10"
        > print $x
        10
        */
        auto code = context.pop!string();
        SubProgram subprogram;

        auto parser = new NowParser(code);
        try
        {
            subprogram = parser.consumeSubProgram();
        }
        catch (Exception ex)
        {
            return context.error(
                ex.to!string,
                ErrorCode.InvalidSyntax,
                ""
            );
        }

        context = context.process.run(subprogram, context.next());
        return context;
    };


    stringCommands["get"] = function (string path, Context context)
    {
        String target = context.pop!String();

        if (context.size == 0) return context.push(target);

        long s = context.pop().toInt();
        if (s < 0)
        {
            s = target.repr.length + s;
        }
        size_t start = cast(size_t)s;

        if (context.size == 0)
        {
            return context.push(target.repr[start..start+1]);
        }

        size_t end;
        auto item = context.pop();
        if (item.toString() == "end")
        {
            end = target.repr.length;
        }
        else
        {
            long e = item.toInt();
            if (e < 0)
            {
                e = target.repr.length + e;
            }
            end = cast(size_t)e;
        }

        return context.push(target.repr[start..end]);
    };
    stringCommands["."] = stringCommands["get"];

    stringCommands["length"] = function (string path, Context context)
    {
        foreach (item; context.items)
        {
            auto s = cast(String)item;
            context.push(s.repr.length);
        }
        return context;
    };
    stringCommands["split"] = function (string path, Context context)
    {
        auto separator = context.pop!string;
        if (context.size == 0)
        {
            auto msg = "`" ~ path ~ "` expects two arguments";
            return context.error(msg, ErrorCode.InvalidSyntax, "");
        }

        foreach (item; context.items)
        {
            auto s = item.toString();
            List l = new List(
                cast(Items)(s.split(separator)
                    .map!(x => new String(x))
                    .array)
            );

            context.push(l);
        }
        return context;
    };
    stringCommands["indent"] = function (string path, Context context)
    {
        auto s = context.pop!string();
        long level = 1;
        if (context.size)
        {
            level = context.pop!long();
        }
        string spacer = rightJustify("", level * 4, ' ');
        return context.push(new String(spacer ~ s));
    };
    stringCommands["join"] = function (string path, Context context)
    {
        string joiner = context.pop!string();
        if (context.size == 0)
        {
            auto msg = "`" ~ path ~ "` expects at least two arguments";
            return context.error(msg, ErrorCode.InvalidSyntax, "");
        }
        foreach (item; context.items)
        {
            if (item.type != ObjectType.List)
            {
                auto msg = "`" ~ path ~ "` expects a list of Lists";
                return context.error(msg, ErrorCode.InvalidSyntax, "");
            }
            List l = cast(List)item;
            context.push(
                new String(l.items.map!(x => to!string(x)).join(joiner))
            );
        }
        return context;
    };
    stringCommands["strip"] = function (string path, Context context)
    {
        auto chars = context.pop!string();

        foreach (item; context.items)
        {
            string s = item.toString();
            context.push(new String(s.strip(chars[0])));
        }
        return context;
    };
    stringCommands["strip.left"] = function (string path, Context context)
    {
        auto chars = context.pop!string();

        foreach (item; context.items)
        {
            string s = item.toString();
            context.push(new String(s.stripLeft(chars[0])));
        }
        return context;
    };
    stringCommands["strip.right"] = function (string path, Context context)
    {
        auto chars = context.pop!string();

        foreach (item; context.items)
        {
            string s = item.toString();
            context.push(new String(s.stripRight(chars[0])));
        }
        return context;
    };
    stringCommands["find"] = function (string path, Context context)
    {
        string needle = context.pop!string();

        if (context.size == 0)
        {
            auto msg = "`" ~ path ~ "` expects two arguments";
            return context.error(msg, ErrorCode.InvalidSyntax, "");
        }
        foreach(item; context.items)
        {
            string haystack = item.toString();
            context.push(haystack.indexOf(needle));
        }
        return context;
    };
    stringCommands["matches"] = function (string path, Context context)
    {
        string expression = context.pop!string();
        if (context.size == 0)
        {
            auto msg = "`" ~ path ~ "` expects two arguments";
            return context.error(msg, ErrorCode.InvalidSyntax, "");
        }

        foreach (item; context.items)
        {
            string target = item.toString();

            List l = new List([]);
            foreach(m; target.matchAll(expression))
            {
                l.items ~= new String(m.hit);
            }
            context.push(l);
        }

        return context;
    };
    stringCommands["match"] = function (string path, Context context)
    {
        string expression = context.pop!string();
        if (context.size == 0)
        {
            auto msg = "`" ~ path ~ "` expects two arguments";
            return context.error(msg, ErrorCode.InvalidSyntax, "");
        }

        foreach (item; context.items)
        {
            string target = item.toString();

            foreach(m; target.matchFirst(expression))
            {
                context.push(m);
            }
        }

        return context;
    };
    stringCommands["range"] = function (string path, Context context)
    {
        /*
        range "12345" -> 1 , 2 , 3 , 4 , 5
        */
        class StringRange : Item
        {
            string s;
            int currentIndex = 0;
            ulong _length;

            this(string s)
            {
                this.s = s;
                this._length = s.length;
            }
            override string toString()
            {
                return "StringRange";
            }
            override Context next(Context context)
            {
                if (this.currentIndex >= this._length)
                {
                    context.exitCode = ExitCode.Break;
                }
                else
                {
                    auto chr = this.s[this.currentIndex++];
                    context.push(to!string(chr));
                    context.exitCode = ExitCode.Continue;
                }
                return context;
            }
        }

        string s = context.pop!string();
        return context.push(new StringRange(s));
    };

    // Operators
    stringCommands["eq"] = function (string path, Context context)
    {
        if (context.size < 2)
        {
            auto msg = "`" ~ path ~ "` expects at least 2 arguments";
            return context.error(msg, ErrorCode.InvalidArgument, "int");
        }

        string first = context.pop!string();
        foreach (item; context.items)
        {
            if (item.toString() != first)
            {
                return context.push(false);
            }
        }
        return context.push(true);
    };
    stringCommands["=="] = stringCommands["eq"];
    stringCommands["neq"] = function (string path, Context context)
    {
        if (context.size < 2)
        {
            auto msg = "`" ~ path ~ "` expects at least 2 arguments";
            return context.error(msg, ErrorCode.InvalidArgument, "int");
        }

        string first = context.pop!string();
        foreach (item; context.items)
        {
            if (item.toString() == first)
            {
                return context.push(false);
            }
        }
        return context.push(true);
    };
    stringCommands["!="] = stringCommands["neq"];

    // Conversions
    stringCommands["to.integer"] = function (string path, Context context)
    {
        foreach (item; context.items)
        {
            string target = item.toString();

            long result;
            try
            {
                result = toLong(target);
            }
            catch (Exception ex)
            {
                string msg = "Could not convert to integer: " ~ ex.msg;
                return context.error(msg, ErrorCode.InvalidArgument, "");
            }

            context.push(result);
        }
        return context;
    };
    stringCommands["to.float"] = function (string path, Context context)
    {
        foreach (item; context.items)
        {
            string target = item.toString();

            if (target.length == 0)
            {
                target = "0.0";
            }

            float result;
            try
            {
                result = to!float(target);
            }
            catch (ConvException)
            {
                auto msg = "Could not convert to float";
                return context.error(msg, ErrorCode.InvalidArgument, "");
            }

            context.push(result);
        }
        return context;
    };

    stringCommands["to.ascii"] = function (string path, Context context)
    {
        foreach (item; context.items)
        {
            auto s = cast(String)item;
            auto items = s.toBytes()
                .map!(x => new IntegerAtom(x))
                .map!(x => cast(Item)x)
                .array;
            context.push(new List(items));
        }
        return context;
    };
    stringCommands["to.byte_vector"] = function (string path, Context context)
    {
        foreach (item; context.items)
        {
            auto s = cast(String)item;
            context.push(new ByteVector(s.toBytes()));
        }
        return context;
    };
}
