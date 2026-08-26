set debuginfod enabled on

# switch to commandline debugging 
define line
  tui disable
end

# switch to debugging c:
define clang
   tui  enable
   set extended -prompt clang (\w)>
   set tui border-mode standout
   set tui active-border-mode standout
   set tui border-kind acs
   layout src
end

# switch to debugging assembly - language:
define asm
   set extended -prompt asm (\w)>
   set disassembly-flavor intel
   layout asm
   tui reg all
   set tui border-mode standout
   set tui active-border-mode standout
   set tui border-kind acs
end