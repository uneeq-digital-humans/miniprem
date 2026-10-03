# Collapse the infinite `usage` loop (unbounded identical blocks) so the artifact is
# deterministic: N identical consecutive usage blocks -> one block + a marker line.
# The prefix and the SIGTERM-trap tail are kept verbatim.
perl -e '
my ($blk,$prev,$in)=("","",0);
sub flush { if ($blk ne "") { if ($blk eq $prev) { $main::rep=1 } else { print "[harness: usage block repeated]\n" if $main::rep; $main::rep=0; print $blk; $prev=$blk } $blk="" } }
$main::rep=0;
while (<STDIN>) {
  if (/^install_miniprem\.sh \[OPTIONS\]$/) { flush(); $in=1 }
  if ($in) { $blk.=$_; if (/^\s+--help\s+Show this help message$/) { $in=0; flush() } next }
  flush(); if ($main::rep) { print "[harness: usage block repeated]\n"; $main::rep=0; $prev="" } print;
}
flush(); print "[harness: usage block repeated]\n" if $main::rep;
' < /out/stdout > /out/stdout.post && mv /out/stdout.post /out/stdout
