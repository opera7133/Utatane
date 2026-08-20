#!/bin/sh
set -eu

test -f build/src/libkawari/kawari_code.cpp

perl -pi -e 's/unsigned int pos=0;/wstring::size_type pos=0;/; s/unsigned int pos2=ws\.find_first_of/wstring::size_type pos2=ws.find_first_of/; s/pos2==string::npos/pos2==wstring::npos/' build/src/libkawari/kawari_code.cpp
perl -pi -e 's/map\[ch\]/map[static_cast<unsigned char>(ch)]/g; s/lex_map\[\(int\)m\]\[ch\]/lex_map[(int)m][static_cast<unsigned char>(ch)]/g; s/map\[c\]/map[static_cast<unsigned char>(c)]/g' build/src/libkawari/kawari_lexer.cpp
perl -pi -e 's/unsigned int pos=bp\.rfind/wstring::size_type pos=bp.rfind/; s/unsigned int pos=path\.rfind/wstring::size_type pos=path.rfind/g; s/pos==string::npos/pos==wstring::npos/g' build/src/misc/misc.cpp
perl -pi -e 's/unsigned int pos=path\.find_last_of/string::size_type pos=path.find_last_of/' build/src/saori/saori_native.cpp
perl -pi -e 's/unsigned int pos=\(f\)\?/wstring::size_type pos=(f)?/; s/pos!=string::npos/pos!=wstring::npos/; s/unsigned int pos=tmp;/wstring::size_type pos=static_cast<wstring::size_type>(tmp);/; s/pos==string::npos/pos==wstring::npos/g; if ($. >= 245 && $. <= 260) { s/unsigned int pos=0;/wstring::size_type pos=0;/; s/unsigned int replen=replace\.length\(\);/wstring::size_type replen=replace.length();/; }; s/unsigned int index=search\.find/wstring::size_type index=search.find/' build/src/kis/kis_string.cpp
perl -pi -e 's/unsigned int pos=ctow\(dirname\)\.rfind/wstring::size_type pos=ctow(dirname).rfind/; s/pos==string::npos/pos==wstring::npos/' build/src/kis/kis_file.cpp
perl -pi -e 's/unsigned int idx;/wstring::size_type idx;/' build/src/kis/kis_split.cpp
perl -pi -e 's/unsigned int pos=statusline\.find/string::size_type pos=statusline.find/; s/unsigned int npos=statusline\.find/string::size_type npos=statusline.find/' build/src/kis/kis_saori.cpp
