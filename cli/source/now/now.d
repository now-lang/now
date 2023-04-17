module now.cli;

extern(C) int isatty(int);

import std.algorithm.searching : canFind, startsWith;
import std.datetime.stopwatch;
import std.file;
import std.process : environment;
import std.stdio;
import std.string;

import now.commands;
import now.context;
import now.conv;
import now.grammar;
import now.nodes;
import now.process;


Dict envVars;

const defaultFilepath = "Nowfile";


static this()
{
    envVars = new Dict();
    foreach(key, value; environment.toAA())
    {
        envVars[key] = new String(value);
    }
}


int main(string[] args)
{
    NowParser parser;

    auto argumentsList = new List(
        cast(Items)args.map!(x => new String(x)).array
    );

    debug
    {
        auto sw = StopWatch(AutoStart.no);
        sw.start();
    }

    // Potential small speed-up:
    commands.rehash();

    string filepath = defaultFilepath;
    string subCommandName = null;
    Procedure subCommand = null;
    int programArgsIndex = 2;

    if (args.length >= 2)
    {
        subCommandName = args[1];
    }

    debug {stderr.writeln("subCommandName:", subCommandName);}

    while (true)
    {
        if (subCommandName.canFind(":"))
        {
            auto parts = subCommandName.split(":");
            debug {stderr.writeln("  parts:", parts);}
            auto prefix = parts[0];
            debug {stderr.writeln("  prefix:", prefix);}

            // ":stdin".split(":") -> ["", "stdin"];
            if (prefix == "")
            {
                auto keyword = parts[1];
                switch (keyword)
                {
                    case "stdin":
                        filepath = null;
                        subCommandName = null;
                        parser = new NowParser(stdin.byLine.join("\n").to!string);
                        break;
                    case "f":
                        filepath = args[programArgsIndex];
                        programArgsIndex++;
                        subCommandName = null;
                        parser = new NowParser(filepath.read.to!string);
                        break;
                    case "repl":
                        return repl(filepath, parser);
                    case "cmd":
                        return cmd(parser, args);
                    case "bash-complete":
                        return bashAutoComplete(parser);
                    case "help":
                        return now_help();
                    default:
                        stderr.writeln("Unknown command: ", filepath);
                        return 1;
                }
            }
        }
        if (subCommandName is null && args.length > programArgsIndex)
        {
            subCommandName = args[programArgsIndex++];
        }
        else
        {
            break;
        }
    }

    if (parser is null)
    {
        try
        {
            parser = new NowParser(filepath.read.to!string);
        }
        catch (FileException ex)
        {
            stderr.writeln(
                "Error ",
                ex.errno, ": ",
                ex.msg
            );
            return ex.errno;
        }
    }

    debug
    {
        sw.stop();
        stderr.writeln(
            "Code was loaded in ",
            sw.peek.total!"msecs", " miliseconds"
        );
    }

    debug {sw.start();}

    Program program;
    try
    {
        program = parser.run();
    }
    catch (Exception ex)
    {
        stderr.writeln(ex.to!string);
        return -1;
    }
    program.initialize(commands, envVars);

    debug
    {
        sw.stop();
        stderr.writeln(
            "Semantic analysis took ",
            sw.peek.total!"msecs", " miliseconds"
        );
    }

    debug {stderr.writeln(">>> subCommandName:", subCommandName);}

    if (subCommandName == "--help")
    {
        return show_program_help(filepath, args, program);
    }


    // The scope:
    program["args"] = argumentsList;
    program["env"] = envVars;

    // Find the right subCommand:
    if (subCommandName !is null)
    {
        auto subCommandPtr = (subCommandName in program.subCommands);
        if (subCommandPtr !is null)
        {
            subCommand = *subCommandPtr;
        }
        else
        {
            stderr.writeln("Command ", subCommandName, " not found.");
            return 2;
        }
    }
    else
    {
        // Instead of trying any of the eventually existent
        // commands, just show the help text for the program.
        show_program_help(filepath, args, program);
        return 4;
    }

    // The main Process:
    auto process = new Process("main");

    // Start!
    debug {sw.start();}

    auto escopo = new Escopo(program);
    auto context = Context(process, escopo);

    // Push all command line arguments into the stack:
    /*
    [commands/default]
    parameters {
        name { type string }
        times {
            type integer
            default 1
        }
    }
    ---
    $ now Fulano
    Hello, Fulano!

    No need to cast, here. Leave it to
    the BaseCommand/Procedure class.
    */
    foreach (arg; args[programArgsIndex..$].retro)
    {
        debug {stderr.writeln(" arg:", arg);}
        if (arg.length > 2 && arg[0..2] == "--")
        {
            auto pair = arg[2..$].split("=");
            // alfa-beta -> alfa_beta
            auto key = pair[0].replace("-", "_");

            // alfa-beta=1=2=3 -> alfa_beta = "1=2=3"
            auto value = pair[1..$].join("=");

            auto p = new NowParser(value);

            context.push(new Pair([
                new String(key),
                p.consumeItem()
            ]));
        }
        else
        {
            context.push(arg);
        }
    }

    debug {
        stderr.writeln("cli stack: ", context.process.stack);
    }
    // Run the main process:
    /*
    Procedure.run is going to create a new scope first thing, so
    we don't have to worry about the program itself being the scope.
    */
    context = subCommand.run(subCommandName, context);

    debug {
        stderr.writeln(" end of program; context: ", context);
    }

    if (context.exitCode == ExitCode.Failure)
    {
        // Global error handler:
        auto handlerString = program.get!String(
            ["document", "on.error", "body"],
            delegate (Dict d) {
                return null;
            }
        );
        if (handlerString !is null)
        {
            auto localParser = new NowParser(handlerString.toString());
            SubProgram handler = localParser.consumeSubProgram();

            // Avoid calling on.error recursively:
            auto newScope = new Escopo(context.escopo);
            newScope.rootCommand = null;

            auto error = context.peek();
            if (error.type == ObjectType.Error)
            {
                newScope["error"] = error;
            }

            auto newContext = Context(context.process, newScope);
            context = context.process.run(handler, newContext);
        }
    }

    int returnCode = process.finish(context);

    debug
    {
        sw.stop();
        stderr.writeln(
            "Program was run in ",
            sw.peek.total!"msecs", " miliseconds"
        );
    }

    return returnCode;
}

int show_program_help(string filepath, string[] args, Program program)
{
    auto programName = program.get!String(
        ["document", "title"],
        delegate (Dict d) {
            if (filepath)
            {
                return new String(filepath);
            }
            else
            {
                return new String("-");
            }
        }
    );
    stdout.writeln(programName.toString());

    auto programDescription = program.get!String(
        ["document", "description"],
        delegate (Dict d) {
            return null;
        }
    );
    if (programDescription)
    {
        stdout.writeln(programDescription.toString());
    }
    stdout.writeln();

    auto programDict = cast(Dict)program;
    auto commands = cast(Dict)(programDict["commands"]);

    long maxLength = 16;
    foreach (commandName; program.subCommands.keys)
    {
        // XXX: certainly there's a Dlangier way of doing this:
        auto l = commandName.length;
        if (l > maxLength)
        {
            maxLength = l;
        }
    }
    foreach (commandName; program.subCommands.keys)
    {
        auto command = cast(Dict)(commands[commandName]);

        string description = "?";
        if (auto descriptionPtr = ("description" in command.values))
        {
            description = (*descriptionPtr).toString();
        }
        stdout.writeln(
            " ", (commandName ~ " ").leftJustify(maxLength, '-'),
            "> ", description
        );

        auto parameters = cast(Dict)(command["parameters"]);
        foreach (parameter; parameters.order)
        {
            auto info = cast(Dict)(parameters[parameter]);
            auto type = info["type"];
            auto defaultPtr = ("default" in info.values);
            string defaultStr = "";
            if (defaultPtr !is null)
            {
                auto d = *defaultPtr;
                defaultStr = " = " ~ d.toString();
            }
            stdout.writeln("    ", parameter, " : ", type, defaultStr);
        }
        if (parameters.order.length == 0)
        {
            // stdout.writeln("    (no parameters)");
        }
    }

    return 0;
}

int now_help()
{
    stdout.writeln("now");
    stdout.writeln("  No arguments: run ./", defaultFilepath, " if present");
    stdout.writeln("  :bash-complete - shell autocompletion");
    stdout.writeln("  :cmd <command> - run commands passed as arguments");
    stdout.writeln("  :f <file> - run a specific file");
    stdout.writeln("  :repl - enter interactive mode");
    stdout.writeln("  :stdin - read a program from standard input");
    stdout.writeln("  :help - display this help message");
    return 0;
}

int repl(string filepath, NowParser parser)
{
    Program program;

    if (filepath is null)
    {
        filepath = defaultFilepath;
    }

    if (parser !is null)
    {
        program = parser.run();
    }
    else
    {
        if (filepath.exists)
        {
            parser = new NowParser(read(filepath).to!string);
            program = parser.run();
            stderr.writeln("Loaded ", filepath);
        }
        else
        {
            program = new Program();
            program["title"] = new String("repl");
            program["description"] = new String("Read Eval Print Loop");
        }
    }

    program.initialize(commands, envVars);

    auto process = new Process("repl");
    auto escopo = new Escopo(program);
    auto context = Context(process, escopo);

    stderr.writeln("Starting REPL...");

    auto istty = cast(bool)isatty(stdout.fileno);
    string line;
    string prompt = "> ";
    while (true)
    {
        if (istty)
        {
            stderr.write(prompt);
        }
        line = readln();
        if (line is null)
        {
            break;
        }
        else if (line == "R\n")
        {
            if (filepath.exists)
            {
                parser = new NowParser(read(filepath).to!string);
                program = parser.run();
                stderr.writeln("Loaded ", filepath);
            }
            else
            {
                stderr.writeln(filepath, " not found.");
            }
            continue;
        }
        else if (line == "Q\n")
        {
            break;
        }

        parser = new NowParser(line);
        Pipeline pipeline;
        try
        {
            pipeline = parser.consumePipeline();
        }
        catch (Exception ex)
        {
            stderr.writeln("Exception: ", ex);
            stderr.writeln("----------");
            continue;
        }
        context = pipeline.run(context);
        if (context.exitCode == ExitCode.Failure)
        {
            auto error = context.pop!Erro();
            stderr.writeln(error.toString());
            stderr.writeln("----------");
        }
        else
        {
            if (context.exitCode != ExitCode.Success)
            {
                stderr.writeln(context.exitCode.to!string);
            }
        }
    }
    return 0;
}

int bashAutoComplete(NowParser parser)
{
    Program program;

    if (parser !is null)
    {
        program = parser.run();
    }
    else
    {
        string filepath = defaultFilepath;

        if (filepath.exists)
        {
            parser = new NowParser(read(filepath).to!string);
            program = parser.run();
        }
        else
        {
            return 0;
        }
    }

    auto words = envVars["COMP_LINE"].toString().split(" ");
    string lastWord = null;
    auto ignore = 0;
    foreach (word; words.retro)
    {
        if (word.length)
        {
            lastWord = word;
            break;
        }
        ignore++;
    }
    auto n = words.length - ignore;

    program.initialize(null, envVars);

    if (n == 1)
    {
        stdout.writeln(program.subCommands.keys.join(" "));
    }
    else {
        string[] commands;
        foreach (name; program.subCommands.keys)
        {
            if (name.startsWith(lastWord))
            {
                commands ~= name;
            }
        }
        stdout.writeln(commands.join(" "));
    }
    return 0;
}

int cmd(NowParser parser, string[] args)
{
    Program program;

    if (parser !is null)
    {
        program = parser.run();
    }
    else
    {
        string filepath = defaultFilepath;

        if (filepath.exists)
        {
            parser = new NowParser(read(filepath).to!string);
            program = parser.run();
            stderr.writeln("Loaded ", filepath);
        }
        else
        {
            program = new Program();
            program["title"] = new String("cmd");
            program["description"] = new String("Run commands passed as arguments");
        }
    }

    program.initialize(commands, envVars);

    auto process = new Process("cmd");
    auto escopo = new Escopo(program);
    auto context = Context(process, escopo);

    foreach (line; args[2..$])
    {
        Pipeline pipeline;

        parser = new NowParser(line);
        pipeline = parser.consumePipeline();

        context = pipeline.run(context);
        if (context.exitCode == ExitCode.Failure)
        {
            auto error = context.pop!Erro();
            stderr.writeln(error.toString());
            stderr.writeln("----------");
            return error.code;
        }
        else
        {
            if (context.exitCode != ExitCode.Success)
            {
                stderr.writeln(context.exitCode.to!string);
            }
        }
    }
    return 0;
}