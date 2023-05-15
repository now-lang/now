module now.nodes.boolean.methods;


import std.array;
import std.regex : matchAll, matchFirst;
import std.string;

import now;


template CreateComparisonOperator(string cmdName, string operator)
{
    const string CreateComparisonOperator = "
        booleanMethods[\"" ~ cmdName ~ "\"] = function (Item object, string path, Input input, Output output)
        {
            bool pivot = (cast(Boolean)object).toBool;
            foreach (item; input.popAll)
            {
                bool x = item.toBool();
                if (!(pivot " ~ operator ~ " x))
                {
                    output.push(false);
                    return ExitCode.Success;
                }
                pivot = x;
            }
            output.push(true);
            return ExitCode.Success;
        };
        booleanMethods[\"" ~ operator ~ "\"] = booleanMethods[\"" ~ cmdName ~ "\"];
        ";
}

// Methods:
static this()
{
    mixin(CreateComparisonOperator!("eq", "=="));
    mixin(CreateComparisonOperator!("neq", "!="));

    booleanMethods["||"] = function (Item object, string path, Input input, Output output)
    {
        foreach (item; input.popAll)
        {
            if (item.toBool())
            {
                output.push(true);
                return ExitCode.Success;
            }
        }
        output.push(false);
            return ExitCode.Success;
    };
    booleanMethods["&&"] = function (Item object, string path, Input input, Output output)
    {
        foreach (item; input.popAll)
        {
            if (!item.toBool())
            {
                output.push(false);
            return ExitCode.Success;
            }
        }
        output.push(true);
        return ExitCode.Success;
    };
    booleanMethods["then"] = function(Item object, string path, Input input, Output output)
    {
        bool isConditionTrue = (cast(Boolean)object).toBool;
        auto thenBody = input.pop!SubProgram;
        auto elseBody = input.pop!SubProgram(null);
        ExitCode exitCode;
        if (isConditionTrue)
        {
            return thenBody.run(input.escopo, output);
        }
        else if (elseBody !is null)
        {
            return elseBody.run(input.escopo, output);
        }
        return ExitCode.Success;
    };
    booleanMethods["else"] = function(Item object, string path, Input input, Output output)
    {
        bool isConditionTrue = (cast(Boolean)object).toBool;
        auto elseBody = input.pop!SubProgram;
        if (!isConditionTrue)
        {
            return elseBody.run(input.escopo, output);
        }
        output.push(isConditionTrue);
        return ExitCode.Success;
    };
}
