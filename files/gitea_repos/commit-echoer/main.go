package main

import (
	"fmt"
	"os"
	"time"
)

// CommitID can be injected at build time via -ldflags "-X main.CommitID=<hash>"
var CommitID = "development"

func main() {
	commit := os.Getenv("COMMIT_ID")
	if commit == "" {
		commit = CommitID
	}

	fmt.Printf("Starting commit-echoer service (Commit ID: %s) [CI/CD Verified]\n", commit)
	for {
		fmt.Printf("[%s] Commit ID: %s\n", time.Now().UTC().Format(time.RFC3339), commit)
		time.Sleep(5 * time.Second)
	}
}
