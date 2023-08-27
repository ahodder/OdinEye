package main

import "core:fmt"
import "core:os"
import "core:strings"

commands: []Command = {
    Command { "-whereis", "Prints where the executable lives", process_command_whereis },
    Command { "-h", "Prints the stuff you are seeing now", process_command_help},
}

Command :: struct {
    flagName: string,
    helpString: string,
    callback: proc(int),
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
}

process_command_whereis :: proc(argIndex: int) {
    fmt.println("The OdinEye executable is located at: ", os.args[0])
}

process_command_help :: proc(argIndex: int) {
    fmt.println("OdinEye is a program that fuzzy scans for APIs given some constraints")
    for i := 0; i < len(commands); i += 1 {
        fmt.printf("\t%-10s  %v\n", commands[i].flagName, commands[i].helpString)
    }
}