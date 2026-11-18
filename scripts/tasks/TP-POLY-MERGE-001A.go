package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

func findSeed(name string) string {
	candidates := []string{
		filepath.Join("seeds", name),
		filepath.Join(os.Getenv("HOME"), "src/plans/seeds", name),
		filepath.Join("..", "seeds", name),
		filepath.Join("/home/nyc/src/plans/seeds", name),
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	return filepath.Join("seeds", name)
}

func main() {
	fmt.Println("=== [TP-POLY-MERGE-001A Task Runner (Go)] ===")

	// 1. Copy MergeMorph.hs
	srcMM := findSeed("TP-POLY-MERGE-001A-MergeMorph.hs")
	dstMM := "packages/polytropos-core/src/Polytropos/MergeMorph.hs"
	if err := copyFile(srcMM, dstMM); err != nil {
		fmt.Fprintf(os.Stderr, "failed to copy %s -> %s: %v\n", srcMM, dstMM, err)
		os.Exit(1)
	}
	fmt.Printf("  [+] Mounted %s\n", dstMM)

	// 2. Copy Record.hs and Record.hs-boot
	srcRec := findSeed("TP-POLY-MERGE-001A-Record.hs")
	dstRec := "packages/polytropos-core/src/Polytropos/Record.hs"
	if err := copyFile(srcRec, dstRec); err != nil {
		fmt.Fprintf(os.Stderr, "failed to copy %s -> %s: %v\n", srcRec, dstRec, err)
		os.Exit(1)
	}
	srcRecBoot := findSeed("TP-POLY-MERGE-001A-Record.hs-boot")
	dstRecBoot := "packages/polytropos-core/src/Polytropos/Record.hs-boot"
	if err := copyFile(srcRecBoot, dstRecBoot); err != nil {
		fmt.Fprintf(os.Stderr, "failed to copy %s -> %s: %v\n", srcRecBoot, dstRecBoot, err)
		os.Exit(1)
	}
	fmt.Printf("  [+] Mounted %s and %s\n", dstRec, dstRecBoot)

	// 3. Update polytropos-core.cabal
	cabalPath := "packages/polytropos-core/polytropos-core.cabal"
	cabalBytes, err := os.ReadFile(cabalPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read %s: %v\n", cabalPath, err)
		os.Exit(1)
	}
	cabalStr := string(cabalBytes)
	if !strings.Contains(cabalStr, "Polytropos.MergeMorph") {
		cabalStr = strings.Replace(cabalStr, "                  , Polytropos.RowMorph\n", "                  , Polytropos.RowMorph\n                  , Polytropos.MergeMorph\n                  , Polytropos.Record\n", 1)
		if err := os.WriteFile(cabalPath, []byte(cabalStr), 0644); err != nil {
			fmt.Fprintf(os.Stderr, "failed to write %s: %v\n", cabalPath, err)
			os.Exit(1)
		}
		fmt.Printf("  [+] Updated %s (exposed MergeMorph & Record)\n", cabalPath)
	}

	// 4. Copy updated test/Main.hs
	srcTest := findSeed("TP-POLY-MERGE-001A-test-Main.hs")
	dstTest := "packages/polytropos-core/test/Main.hs"
	if err := copyFile(srcTest, dstTest); err != nil {
		fmt.Fprintf(os.Stderr, "failed to copy %s -> %s: %v\n", srcTest, dstTest, err)
		os.Exit(1)
	}
	fmt.Printf("  [+] Updated %s (added merge-morph test tree)\n", dstTest)

	fmt.Println("=== [TP-POLY-MERGE-001A Task Runner Finished] ===")
}
