module now.process;


import now.nodes;
import now.stack;


class Process
{
    Stack stack;

    // Process identification:
    static uint counter = 0;
    string description;
    uint index;

    this(string description)
    {
        this.description = description;

        this.stack = new Stack();
        this.index = this.counter++;
    }

    // SubProgram execution:
    Context run(SubProgram subprogram, Escopo escopo)
    {
        return run(subprogram, Context(this, escopo));
    }
    Context run(SubProgram subprogram, Context context, int inputSize=0)
    {
        foreach(pipeline; subprogram.pipelines)
        {
            context.size = 0;
            context.inputSize = inputSize;
            context = pipeline.run(context);
            debug {stderr.writeln("pipeline.run.exitCode: ", context.exitCode);}

            final switch(context.exitCode)
            {
                case ExitCode.Undefined:
                    throw new Exception(to!string(pipeline) ~ " returned Undefined");

                case ExitCode.Success:
                    // That is the expected result from Pipelines:
                    break;

                // -----------------
                // Proc execution:
                case ExitCode.Return:
                    // Return should keep stopping
                    // processes until properly
                    // handled.
                    return context;

                case ExitCode.Failure:
                    if (context.escopo.rootCommand !is null)
                    {
                        auto escopo = context.escopo;
                        auto rootCommand = escopo.rootCommand;
                        context = rootCommand.handleEvent(context, "on.error");
                    }
                    /*
                    Wheter we called errorHandler or not,
                    we ARE going to exit the current
                    scope right now. The idea of
                    a errorHandler is NOT to
                    allow continuing in the
                    same scope.
                    */
                    return context;

                // -----------------
                // Loops:
                case ExitCode.Break:
                case ExitCode.Continue:
                case ExitCode.Skip:
                    return context;
            }
        }

        // Returns the context of the last expression:
        return context;
    }

    Context closeCMs(Context context)
    {
        auto cmList = context.escopo.contextManagers;
        foreach (contextManager; cmList)
        {
            auto closeContext = contextManager.runMethod("close", context);
            if (closeContext.exitCode == ExitCode.Failure)
            {
                // If the subprogram itself failed, we're going
                // to be very forgiving with autoclose errors,
                // since it could cloud the real issue from the
                // programmers view:
                if (context.exitCode != ExitCode.Failure)
                {
                    return closeContext;
                }
            }
        }
        return context;
    }

    int unixExitStatus(Context context)
    {
        // Search for errors:
        if (context.exitCode == ExitCode.Failure)
        {
            Item x = context.peek();
            Erro e = cast(Erro)x;
            return e.code;
        }
        else
        {
            return 0;
        }
    }

    int finish(Context context)
    {
        int returnCode = unixExitStatus(context);

        if (context.exitCode == ExitCode.Failure)
        {
            auto e = context.pop!Erro();
            stderr.writeln(e);
        }
        else
        {
            foreach (item; context.items)
            {
                stdout.writeln(item.toString());
            }
        }

        return returnCode;
    }
}
