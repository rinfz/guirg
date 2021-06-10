import nake

task "run", "build and run executable":
  direShell nimExe, "c", "--threads:on", "-r", "--outdir:.", "--gc:orc", "src/main.nim"
