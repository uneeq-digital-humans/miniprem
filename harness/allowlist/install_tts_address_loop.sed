# bash prints "Terminated" (job-status report for a child — the `cat`/`basename` inside usage() —
# killed by timeout's process-group SIGTERM). Not script output; Go has no child to report.
# See DEVIATIONS.md D1.
/^Terminated$/d
