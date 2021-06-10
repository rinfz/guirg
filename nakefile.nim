import nake

task "run", "build and run executable":
  direShell nimExe, "c", "--threads:on", "-r", "--outdir:.", "--gc:arc", "src/main.nim"

task "release", "build a release executable":
  direShell nimExe, "c", "-d:release", "--threads:on", "--outdir:.", "--gc:arc", "src/main.nim"
