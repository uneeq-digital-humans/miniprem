// Command miniprem is the Go port of miniprem.sh, docker/scripts/install_miniprem.sh
// and docker/scripts/merge-compose.sh. The original script paths are shims that exec
// this binary with the entry name as the first argument.
package main

import (
	"fmt"
	"os"

	"github.com/uneeq-digital-humans/miniprem/internal/mergecompose"
	"github.com/uneeq-digital-humans/miniprem/internal/mp"
	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: miniprem {miniprem|install|merge-compose} [args...]")
		os.Exit(2)
	}
	entry, args := os.Args[1], os.Args[2:]
	switch entry {
	case "miniprem":
		os.Exit(sh.Main(sh.DefaultIFS, func() { mp.MiniPremMain(args) }))
	case "install":
		os.Exit(sh.Main("\n\t", func() { mp.InstallMain(args) }))
	case "merge-compose":
		os.Exit(sh.Main(sh.DefaultIFS, func() { mergecompose.Main(args) }))
	default:
		fmt.Fprintf(os.Stderr, "unknown entry %q\n", entry)
		os.Exit(2)
	}
}
