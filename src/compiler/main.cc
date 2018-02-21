/*
 * FastBasic - Fast basic interpreter for the Atari 8-bit computers
 * Copyright (C) 2017,2018 Daniel Serpell
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>
 */

// main.cc: Main compiler file

#include "atarifp.cc"
#include "looptype.cc"
#include "vartype.cc"
#include <iostream>
#include <fstream>
#include <map>
#include <set>
#include <cmath>
#include <vector>

static bool do_debug = false;

#include "parser.cc"

// Include generated parser
#include "basic.cc"

// Those modules depends on token types
#include "peephole.cc"
#include "codestat.cc"


static bool readLine(std::string &r, std::istream &is)
{
 int c;
 while( -1 != (c = is.get()) )
 {
     r += char(c);
     if( c == '\n' || c == (unsigned char)'\x9b' )
         return true;
 }
 return false;
}

static int show_version()
{
    std::cerr << "FastBasic v3 - (c) 2018 dmsc\n";
    return 0;
}

static int show_help()
{
    show_version();
    std::cerr << "Usage: fastbasic [options] <input.bas> <output.asm>\n"
                 "\n"
                 "Options:\n"
                 " -d\tenable parser debug options (only useful to debug parser)\n"
                 " -n\tdon't run the optimizer, produces same code as 6502 version\n"
                 " -prof\tshow token usage statistics\n"
                 " -v\tshow version and exit\n"
                 " -h\tshow this help\n";
    return 0;
}

static int show_error(std::string msg)
{
    std::cerr << "fastbasic: " << msg << "\n";
    return 1;
}

int main(int argc, char **argv)
{
    std::vector<std::string> args(argv+1, argv+argc);
    std::string iname;
    std::ifstream ifile;
    std::ofstream ofile;
    bool show_stats = false;
    bool optimize = true;

    for(auto &arg: args)
    {
        if( arg == "-d" )
            do_debug = true;
        else if( arg == "-n" )
            optimize = false;
        else if( arg == "-prof" )
            show_stats = true;
        else if( arg == "-v" )
            return show_version();
        else if( arg == "-h" )
            return show_help();
        else if( arg.empty() )
            return show_error("invalid argument, try -h for help");
        else if( arg[0] == '-' )
            return show_error("invalid option '" + arg + "', try -h for help");
        else if( !ifile.is_open() )
        {
            ifile.open(arg);
            if( !ifile.is_open() )
                return show_error("can't open input file '" + arg + "'");
            iname = arg;
        }
        else if( !ofile.is_open() )
        {
            ofile.open(arg);
            if( !ofile.is_open() )
                return show_error("can't open output file '" + arg + "'");
        }
        else
            return show_error("too many arguments, try -h for help");
    }
    if( !ifile.is_open() )
        return show_error("missing input file name");

    if( !ofile.is_open() )
        return show_error("missing output file name");

    parse s;
    int ln = 0;
    while(1)
    {
        std::string line;
        if( !readLine(line, ifile) && line.empty() )
            break;
        ln++;
        if( do_debug )
            std::cerr << iname << ": parsing line " << ln << "\n";
        s.new_line(line, ln);
        if( !SMB_PARSE_START(s) || s.pos != line.length() )
        {
            std::cerr << iname << ":" << ln << ":" << s.max_pos << ": parse error";
            if( !s.saved_error.empty() )
                std::cerr << ", expected " << s.saved_error;
            std::cerr << "\n";
            size_t min = 0, max = s.str.length();
            if( s.max_pos > 40 ) min = s.max_pos - 40;
            if( s.max_pos + 40 < max ) max = s.max_pos + 40;
            for(auto i = min; i<s.max_pos; i++)
                std::cerr << s.str[i];
            std::cerr << "<--- HERE -->";
            for(auto i = s.max_pos; i<max; i++)
                std::cerr << s.str[i];
            std::cerr << "\n";
            return 1;
        }
    }
    if( do_debug )
    {
        std::cerr << "parse end:\n";
        std::cerr << "MAX LEVEL: " << s.maxlvl << "\n";
    }

    s.emit_tok(TOK_END);
    // Optimize
    if( optimize )
        peephole pp(s.full_code());
    // Statistics
    if( show_stats )
        opstat op(s.full_code());

    // Write global symbols
    for(auto &c: s.full_code())
    {
        // Lower-case symbols are internal
        auto s = c.get_str();
        if( !s.empty() && s[0] >= 'A' && s[0] <= '_' )
        {
            if( c.is_sword() )
                ofile << "\t.global " << c.get_str() << "\n";
            else if( c.is_sbyte() )
                ofile << "\t.globalzp " << c.get_str() << "\n";
        }
    }
    // Export common symbols and include atari defs
    ofile << "\t.export bytecode_start\n"
             "\t.exportzp NUM_VARS\n"
             "\n\t.include \"atari.inc\"\n\n";

    // Write tokens
    ofile << "; TOKENS:\n";
    for(auto &i: s.used_tokens())
    {
        if( token_names[i] && *token_names[i] )
            ofile << "\t.importzp\t" << token_names[i] << "\n";
    }
    ofile << ";-----------------------------\n"
             "; Variables\n"
             "NUM_VARS = " << s.vars.size() << "\n"
             ";-----------------------------\n"
             "; Bytecode\n"
             "bytecode_start:\n";
    ln = -1;;
    for(auto c: s.full_code())
    {
        if( c.linenum() != ln )
        {
            ln = c.linenum();
            // Adds a label to facilitate debugging of resulting program
            ofile << "@FastBasic_LINE_" << ln << ":  ";
            ofile << "; LINE " << ln << "\n";
        }
        ofile << c.to_asm() << "\n";
    }

    return 0;
}
