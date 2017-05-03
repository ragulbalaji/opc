# python3 opcasm.py <filename.s> [<filename.hex>]
import sys, re
op = { "and"  :0x00, "lda":0x01,"not"  :0x02,"add":0x03, "and.i":0x10, "lda.i":0x11, "not.i":0x12,
       "add.i":0x13, "sec":0x15,"lda.p":0x09,"sta":0x18, "sta.p":0x08, "jpc"  :0x19, "jpz"  :0x1a,
       "jp"   :0x1b, "jsr":0x1c,"rts"  :0x1d,"lxa":0x1e, "halt" :0x1f, "BYTE":0x100 }

(symtab, bytemem) = (dict(), bytearray(2048))
line_re = re.compile( '^(\w+)?:?\s*(\w+(?:\.i|\.p)?)?\s*(.*)' )
macstart_re = re.compile("MACRO\s*(\w*)\s*?\((.*)\)", re.IGNORECASE)
macend_re   = re.compile("ENDMACRO.*", re.IGNORECASE)
macinst_re  = re.compile("^(?:(\w*):?)?\s*(\w+)\s*?\((.*)\)")

# Pass 0 - macro expansion
(macro, macroname, newtext)  = ( dict(), None, [])
for line in open(sys.argv[1], "r").readlines():
    if macstart_re.match(line) :
        (macroname,paramstr) = (macstart_re.match(line)).groups()
        macro[macroname] = ([x.strip() for x in paramstr.split(",")], [])
        newtext.append("# %s" % line)
    elif macroname and not macend_re.match(line):
        macro[macroname][1].append(line)
        newtext.append("# %s" % line)
    elif macend_re.match(line):
        macroname = None
        newtext.append("# %s" % line)
    elif macinst_re.match(line):
        (label, instname, paramstr) = (macinst_re.match(line)).groups()
        instparams = [x.strip() for x in paramstr.split(",")]
        labeltext = ("%s:\n" % label) if label else ""
        if instname in macro:
            newtext.append("%s# %s" % (labeltext,line))
            for newline in macro[instname][1]:
                for (s,r) in zip( macro[instname][0], instparams):
                    if s and r:
                        newline = newline.replace(s,r)
                newtext.append(newline)
            newtext.append("\n")
    else:
        newtext.append(line)

for iteration in range (0,2):     # Two pass assembly
    nextmem = 0
    for line in newtext:
        bytes = []
        gr = line_re.match( re.sub("#.*","",line) ).groups()
        if gr[0]:
            exec ("%s= %d" % (gr[0],nextmem), globals(), symtab )
        if gr[1] and gr[1] == "ORG" and gr[2]:
            nextmem = eval(gr[2],globals(),symtab)
        elif gr[1] and gr[1] in op:
            bytes=[0]
            if gr[2]:
                if iteration==0:
                    bytes = [0]*len(gr[2].split(","))
                else:
                    try:
                        bytes = [eval( x ,globals(), symtab) for x in gr[2].split(",")]
                    except (ValueError, NameError):
                        sys.exit("Error evaluating expression %s" % gr[2] )
            if gr[1]=="BYTE":
                bytes = [x & 0xFF for x in bytes]
            else:
                bytes = [op[gr[1]]<<3 | (bytes[0]>>8) & 0xF, bytes[0] & 0xFF]
        elif gr[1]:
            sys.exit("Error: unrecognized instruction %s" % gr[1])
        if iteration > 0 :
            for ptr in range(0,len(bytes)):
                bytemem[ptr+nextmem] =  bytes[ptr]
            print("%04x  %-20s  %s" % (nextmem,
                ' '.join([("%02x" % i) for i in bytes]), line.rstrip()))
        nextmem += len(bytes)

print ("\nSymbol Table:\n", symtab)

if len(sys.argv) > 2:  # Write Hex File
    with open(sys.argv[2],"w" ) as f:
        for i in range(0, len(bytemem), 24):
            f.write( '%s\n' %  ' '.join("%02x"%n for n in bytemem[i:i+24]))
