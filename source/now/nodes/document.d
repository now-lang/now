module now.nodes.document;

import core.sys.posix.dlfcn;
import std.algorithm.searching : endsWith;
import std.file : isFile, read;
import std.path : buildPath;
import std.string : toStringz;
import std.uni : toUpper;


import now.nodes;

import now.base_command;
import now.grammar;
import now.procedure;
import now.shell_script;
import now.system_command;


class Document : Dict {
    string title;
    string description;
    string sourcePath;
    Dict metadata;
    Dict data;
    Dict text;

    // CLI commands:
    Procedure[string] commands;
    // Procedures:
    BaseCommand[string] procedures;

    string[] nowPath;

    this(string title, string description, Dict metadata, Dict data)
    {
        log(": Document: ", title);
        this.type = ObjectType.Document;
        this.methods = dictMethods;
        this.typeName = "document";

        this.title = title;
        this.description = description;
        this.metadata = metadata;
        this.data = data;
        log(":: Document created");
    }
    this(string title, string description, Dict metadata)
    {
        log(": Document: ", title, " / ", description, " / ", metadata);
        this(title, description, metadata, new Dict());
    }
    this(string title, string description)
    {
        log(": Document: ", title, " / ", description);
        this(title, description, new Dict(), new Dict());
    }

    void initialize(Dict environmentVariables)
    {
        log("- Initializing document");
        setNowPath(environmentVariables);

        importPackages();
        loadConfiguration(environmentVariables);
        loadConstants();
        loadTemplates();
        loadShells();
        loadProcedures();
        loadDocumentCommands();
        loadSystemCommands();
        loadText();
    }

    void setNowPath(Dict environmentVariables)
    {
        log("- Setting nowPath");
        auto nowPath = environmentVariables.getOr!string(
            "NOW_PATH",
            delegate (Dict d)
            {
                auto pwd = d.get!string("PWD");
                return pwd ~ "/now";
            }
        );
        this.nowPath = nowPath.split(":");
    }
    void importPackages()
    {
        log("- Importing packages");
        auto packages = this.getOrCreate!Dict("packages");
        foreach (index, filenameItem; packages.values)
        {
            bool success = false;
            string filename = filenameItem.toString();
            foreach (basedir; this.nowPath)
            {
                auto path = buildPath([basedir.to!string, filename]);
                if (path.isFile)
                {
                    this.importPackage(path);
                    success = true;
                    break;
                }
            }
            if (!success)
            {
                throw new Exception(
                    "Could not load package " ~ filename ~ "."
                );
            }
        }

    }
    void loadConfiguration(Dict environmentVariables)
    {
        log("- Adjusting configuration");
        /*
        About [configuration]:
        - It must always follow the format "configuration/:key";
        - No sub-keys are allowed;
        - No "direct" configuration is allowed.
        */
        auto configuration = data.getOrCreate!Dict("configuration");
        foreach (configSectionName, configSection; configuration)
        {
            // TODO: check if the key is already present:
            auto scopeDict = new Dict();
            this[configSectionName] = scopeDict;
            // Example: configSectionName = "http"

            // "name" = host
            // "infoItem" = type, default value, etc. (before casting to Dict)
            foreach (name, infoItem; cast(Dict)configSection)
            {
                string envName = (configSectionName ~ "_" ~ name).toUpper;
                Item finalValue;

                Item *envValuePtr = (envName in environmentVariables.values);
                if (envValuePtr !is null)
                {
                    finalValue = *envValuePtr;
                }
                else if (infoItem.type != ObjectType.Dict)
                {
                    finalValue = infoItem;
                }
                else
                {
                    auto info = cast(Dict)infoItem;
                    Item* valuePtr = ("default" in info.values);
                    if (valuePtr !is null)
                    {
                        // (http . port) = 5000
                        finalValue = *valuePtr;
                    }
                    else
                    {
                        throw new InvalidConfigurationException(
                            null,
                            "Configuration "
                            ~ configSectionName ~ "/" ~ name
                            ~ " not found. The environment variable "
                            ~ envName
                            ~ " should be set."
                        );
                    }
                }
                scopeDict[name] = finalValue;
                // We'll overwrite if repeated and that's expected:
                this[envName] = finalValue;
            }
        }
    }
    void loadConstants()
    {
        log("- Adjusting constants");

        auto constants = data.getOrCreate!Dict("constants");
        foreach (sectionName, section; constants)
        {
            if (section.type != ObjectType.Dict)
            {
                this[sectionName] = section;
            }
            else
            {
                auto sectionDict = cast(Dict)section;
                Dict currentSection;
                try
                {
                    currentSection = this.get!Dict(sectionName);
                }
                catch (NotFoundException ex)
                {
                    currentSection = new Dict();
                    this[sectionName] = cast(Dict)section;
                    continue;
                }
                // else:
                currentSection.update(cast(Dict)section);
            }
        }
    }
    void loadTemplates()
    {
        log("- Adjusting templates");

        auto templates = data.getOrCreate!Dict("templates");
        foreach (templateName, infoItem; templates.values)
        {
            log("-- templateName: ", templateName);
            auto templateInfo = cast(Dict)infoItem;
            templates[templateName] = parseTemplate(
                templateName, templateInfo, templates
            );
        }
    }
    void loadShells()
    {
        log("- Adjusting shells");

        auto shells = data.getOrCreate!Dict("shells");
        foreach (shellName, infoItem; shells.values)
        {
            auto shellInfo = cast(Dict)infoItem;

            auto command = shellInfo.get!Dict("command", null);
            if (command is null)
            {
                auto cmdDict = new Dict();
                shellInfo["command"] = cmdDict;
                // default options for every shell:
                // (works fine on bash)
                cmdDict["-"] = new String(shellName);
                cmdDict["-"] = new String("-c");
                cmdDict["-"] = new Reference("script_body");
                if (shellName[0..3] != "ksh")
                {
                    cmdDict["-"] = new Reference("script_name");
                }
            }

            // Scripts for this shell:
            auto scripts = shellInfo.getOrCreate!Dict("scripts");
            foreach (scriptName, scriptInfoItem; scripts.values)
            {
                /*
                XXX: since we are passing shellInfo IMMEDIATELY,
                we can't declare the shell itself AFTER the scripts
                were declared (we could, but it'd be innefective).
                */
                auto scriptInfo = cast(Dict)scriptInfoItem;
                this.procedures[scriptName] = new ShellScript(
                    shellName, shellInfo, scriptName, scriptInfo
                );
            }
        }
    }
    void loadProcedures()
    {
        log("- Adjusting procedures");

        // The document dict is loaded, now
        // act accordingly on each different section.
        auto procedures = data.getOrCreate!Dict("procedures");
        foreach (name, infoItem; procedures.values)
        {
            auto info = cast(Dict)infoItem;
            this.procedures[name] = new Procedure(name, info);
        }
    }
    void loadDocumentCommands()
    {
        log("- Adjusting commands");

        auto commandsDict = data.getOrCreate!Dict("commands");
        foreach (name, infoItem; commandsDict.values)
        {
            auto info = cast(Dict)infoItem;
            commands[name] = new Procedure(name, info);
        }
    }
    void loadSystemCommands()
    {
        log("- Preparing system commands");

        auto system_commands = data.getOrCreate!Dict("system_commands");
        foreach (name, infoItem; system_commands.values)
        {
            auto info = cast(Dict)infoItem;
            if (info is null)
            {
                throw new Exception(
                    "system_commands/" ~ name
                    ~ ".info is null"
                );
            }
            // XXX: is it correct to save procedures and
            // syscmds in the same place???
            this.procedures[name] = new SystemCommand(name, info);
        }
    }
    void loadText()
    {
        log("- Collecting Text");

        this.text = new Dict();

        foreach (key, value; data)
        {
            auto firstLetter = key[0];
            if (firstLetter >= 'A' && firstLetter <= 'Z')
            {
                text[key] = value;
            }
        }

        this["text"] = this.text;
    }

    // Conversions
    override string toString()
    {
        return this.title;
    }

    // Commands (for command line)
    Procedure getCommand(string name)
    {
        auto commandPtr = (name in commands);
        if (commandPtr !is null)
        {
            return *commandPtr;
        }
        else
        {
            stderr.writeln("Command ", name, " not found.");
            return null;
        }
    }
    ExitCode runProcedure(string path, Input input, Output output)
    {
        if (auto procPtr = (path in this.procedures))
        {
            auto proc = *procPtr;
            return proc.run(path, input, output);
        }

        if (auto cmdPtr = (path in builtinCommands))
        {
            auto cmd = *cmdPtr;
            auto exitCode = cmd(path, input, output);
            return exitCode;
        }

        throw new ProcedureNotFoundException(
            input.escopo,
            "Procedure not found: " ~ path
        );
    }

    // Packages
    void importPackage(string path)
    {
        if (path.endsWith(".so"))
        {
            throw new InvalidPackageException(
                null,
                "Cannot import shared libraries.",
                -1,
                this
            );
        }
        else
        {
            return importNowLibrary(path);
        }
    }
    void importNowLibrary(string path)
    {
        auto parser = new NowParser(path.read().to!string);
        auto library = parser.run();
        // Merge the library into the document:
        foreach (key, value; library.values)
        {
            this.on(
                key,
                delegate (Item localValue)
                {
                    // Found both locally and in library:
                    this.merge(key, localValue, value);
                },
                delegate ()
                {
                    // Found in library, not found locally:
                    this[key] = value;
                }
            );
        }
    }
    void merge(string key, Item localValue, Item otherValue)
    {
        if (otherValue.type != ObjectType.Dict)
        {
            this[key] = otherValue;
        }
        else if (localValue.type != ObjectType.Dict)
        {
            this[key] = otherValue;
        }
        else
        {
            auto localDict = cast(Dict)localValue;
            auto otherDict = cast(Dict)otherValue;
            foreach (otherKey, value; otherDict.values)
            {
                localDict[otherKey] = value;
            }
        }
    }
}
