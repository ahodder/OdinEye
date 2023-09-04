package main

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:runtime"
import "core:strings"

commands: []Command = {
    Command { "-whereis", "Prints where the executable lives", process_command_whereis },
    Command { "-h", "Prints the stuff you are seeing now", process_command_help },
    Command { "-d", "Set the directory to scan for documents", process_command_set_scan_directory },
    Command { "-args", "The comma separated list of proc args that we require to be in the proc", process_proc_args },
    Command { "-rets", "The comma separated list of proc returns that we require to be in the proc", process_proc_rets },
}

config : Config = {  }

Command :: struct {
    flagName: string,
    helpString: string,
    callback: proc(int),
}

Config :: struct {
    scanDirectory: string,
    scanDirectorySet: bool,
    // This is not great, but I am not sure how to get the proc name from the ast. I thought it was
    // the assignment statement, but I either did it wrong or it isn't that. So, we just maintain a
    // pointer to the last known ident which comes before the proc lit.
    lastIdent : ^ast.Ident,

    // The field types or field names for the argument list of the proc that we are looking for.
    desiredFieldTypesOrNames: []string,
    // The field types or field names for the return list of the proc that we are looking for.
    desiredReturnTypesOrNames: []string,
}

main :: proc() {
    // Process Commands
    for i := 1; i < len(os.args); i += 1 {
        for c := 0; c < len(commands); c += 1 {
            if strings.compare(commands[c].flagName, os.args[i]) == 0 {
                commands[c].callback(i)
            }
        }
    }

    // If our config was properly set up, let's perform the check
    if !config.scanDirectorySet {
        fmt.println("OdinEye cannot peer into the Aethyr. You must first provide a plane of existence to scry")
        os.exit(1)
    }

    // Check if the given directory exists
    if !os.exists(config.scanDirectory) {
        fmt.printf("Given directory %v does not exist.\n", config.scanDirectory)
        os.exit(1)
    }

    if config.desiredFieldTypesOrNames == nil {
        fmt.printf("Cannot scan: please provide -args\n")
        os.exit(1)
    }

    // Honestly, we shouldn't require return values. A lot of raylib / sdl functions don't actually return anything
/*
    if config.desiredReturnTypesOrNames == nil {
        fmt.printf("Cannot scan: please provide -rets\n")
        os.exit(1)
    }
*/

    visit_path :: proc(fileInfo: os.File_Info, in_err: os.Errno, data: rawptr) -> (err: os.Errno, skip_dir: bool) {
        if fileInfo.is_dir {
            astPackage, ok := parser.parse_package_from_path(fileInfo.fullpath)
            if !ok {
                fmt.printf("Cannot scan directory %v: it's not a directory :(\n", fileInfo.fullpath)
                return os.ERROR_NONE, false
            }

            visit_node :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
                if node == nil || node.derived == nil {
                    return visitor
                }

                #partial switch n in &node.derived {
                case ^ast.Package:
                    if len(n.files) > 0
                    {
                        fmt.printf("Showing results for package: %v at %v\n", n.name, n.fullpath)
                    }
                case ^ast.Ident:
                    // Because I are not smert and don't know how to get the identifier of a proc, just
                    // retain the last found ident which through clever testing has been determined to
                    // be the proc identifier.
                    config.lastIdent = n
                case ^ast.Proc_Lit:
                    if proc_matches_filter(n.type) {
                        fmt.printf("Found proc %v\n", config.lastIdent.name)
                    }
                }

                return visitor
            }

            visitor : ast.Visitor
            visitor.visit = visit_node

            ast.walk(&visitor, astPackage)
        }

        return os.ERROR_NONE, false
    }

    filepath.walk(config.scanDirectory, visit_path, nil)
}

proc_matches_filter :: proc(astProc: ^ast.Proc_Type) -> bool {
    if (astProc.params != nil && len(astProc.params.list) != len(config.desiredFieldTypesOrNames)) ||
        (astProc.results != nil && len(astProc.results.list) != len(config.desiredReturnTypesOrNames)) {
        return false
    }

    foundArgs := 0
    foundRets := 0

    // The params can come in any order, and should be pretty short length-wise
    for i := 0; astProc.params != nil && i < len(astProc.params.list); i += 1 {
        found := false
        for j := 0; j < len(config.desiredFieldTypesOrNames); j += 1 {
            thing := astProc.params.list[i].type
            str : string
            // The Odin ast hides the proc idents across multiple expressions. This should handle normal and pointer types
            #partial switch t in &astProc.params.list[i].type.derived {
            case ^ast.Ident:
                str = t.name
            case ^ast.Pointer_Type:
                selector := cast(^ast.Selector_Expr)t.elem
                str = selector.field.name
            }

            target := config.desiredFieldTypesOrNames[j]

            if strings.compare(str, target) == 0 {
                foundArgs += 1
            }
        }
    }

    for i := 0; astProc.results != nil && i < len(astProc.results.list); i += 1 {
        for j := 0; j < len(config.desiredReturnTypesOrNames); j += 1 {
            thing := astProc.results.list[i].type
            str : string
            // The Odin ast hides the proc idents across multiple expressions. This should handle normal and pointer types
            #partial switch t in &astProc.results.list[i].type.derived {
            case ^ast.Ident:
                str = t.name
            case ^ast.Pointer_Type:
                selector := cast(^ast.Selector_Expr)t.elem
                str = selector.field.name
            }

            target := config.desiredReturnTypesOrNames[j]

            if strings.compare(str, target) == 0 {
                foundRets += 1
            }
        }
    }

    return foundArgs == len(config.desiredFieldTypesOrNames) && foundRets == len(config.desiredReturnTypesOrNames)
}

process_command_whereis :: proc(argIndex: int) {
    fmt.println("The OdinEye executable is located at: ", os.args[0])
    os.exit(0)
}

process_command_help :: proc(argIndex: int) {
    fmt.println("OdinEye is a program that fuzzy scans for APIs given some constraints")
    for i := 0; i < len(commands); i += 1 {
        fmt.printf("\t%-10s  %v\n", commands[i].flagName, commands[i].helpString)
    }
    os.exit(0)
}

process_command_set_scan_directory :: proc(argIndex: int) {
    if argIndex + 1 >= len(os.args) {
        fmt.println("Expected directory argument")
        os.exit(1)
    }
    config.scanDirectory = os.args[argIndex + 1]
    config.scanDirectorySet = true
}

process_proc_args :: proc(argIndex: int) {
    if argIndex + 1 >= len(os.args) {
        fmt.println("Expected comma separated proc arguments")
        os.exit(1)
    }

    parts, err := strings.split(os.args[argIndex + 1], ",")
    if err != runtime.Allocator_Error.None {
        fmt.println("Failed to split proc arguments")
        os.exit(1)
    }

    config.desiredFieldTypesOrNames = parts
}

process_proc_rets :: proc(argIndex: int) {
    if argIndex + 1 >= len(os.args) {
        fmt.println("Expected comma separated proc returns")
        os.exit(1)
    }

    parts, err := strings.split(os.args[argIndex + 1], ",")
    if err != runtime.Allocator_Error.None {
        fmt.println("Failed to split proc returns")
        os.exit(1)
    }

    config.desiredReturnTypesOrNames = parts
}

intret :: proc() -> int {
    return 0
}

twointparamoneretparams :: proc(a: int, b: int) -> int {
    return 0
}

intparamsintret :: proc(a: int) -> int {
    return 0
}