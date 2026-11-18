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
	fmt.Println("=== [TP-POLY-MERGE-001B Task Runner (Go)] ===")

	// 1. Copy Plugin/MergeMorph.hs
	srcMM := findSeed("TP-POLY-MERGE-001B-PluginMergeMorph.hs")
	dstMM := "packages/polytropos-plugin/src/Polytropos/Plugin/MergeMorph.hs"
	if err := copyFile(srcMM, dstMM); err != nil {
		fmt.Fprintf(os.Stderr, "failed to copy %s -> %s: %v\n", srcMM, dstMM, err)
		os.Exit(1)
	}
	fmt.Printf("  [+] Mounted %s\n", dstMM)

	// 2. Update polytropos-plugin.cabal
	cabalPath := "packages/polytropos-plugin/polytropos-plugin.cabal"
	cabalBytes, err := os.ReadFile(cabalPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read %s: %v\n", cabalPath, err)
		os.Exit(1)
	}
	cabalStr := string(cabalBytes)
	if !strings.Contains(cabalStr, "Polytropos.Plugin.MergeMorph") {
		cabalStr = strings.Replace(cabalStr, "  exposed-modules:  Polytropos.Plugin\n                  , Polytropos.Plugin.Source\n", "  exposed-modules:  Polytropos.Plugin\n                  , Polytropos.Plugin.Source\n                  , Polytropos.Plugin.MergeMorph\n", 1)
		cabalStr = strings.Replace(cabalStr, "    , ghc-tcplugin-api >= 0.1 && < 0.21\n", "    , ghc-tcplugin-api >= 0.1 && < 0.21\n    , bytestring >= 0.11 && < 0.13\n    , containers >= 0.6 && < 0.9\n    , polytropos-core\n", 1)
		cabalStr = strings.Replace(cabalStr, "    , directory\n", "    , directory\n    , bytestring\n", 1)
		if err := os.WriteFile(cabalPath, []byte(cabalStr), 0644); err != nil {
			fmt.Fprintf(os.Stderr, "failed to write %s: %v\n", cabalPath, err)
			os.Exit(1)
		}
		fmt.Printf("  [+] Updated %s (exposed Polytropos.Plugin.MergeMorph)\n", cabalPath)
	}

	// 3. Update tests/smoke/Main.hs with evalMergeOp test
	smokePath := "packages/polytropos-plugin/tests/smoke/Main.hs"
	smokeBytes, err := os.ReadFile(smokePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read %s: %v\n", smokePath, err)
		os.Exit(1)
	}
	smokeStr := string(smokeBytes)
	if !strings.Contains(smokeStr, "Plugin MergeMorph Skew Boolean Row Solver") {
		testSnippet := `
  , testGroup "Plugin MergeMorph Skew Boolean Row Solver"
      [ testCase "evalMergeOp OpOverrideR encodes right-biased union" $ do
          let bytes = encodeGatherBytes [0, -1]
          BS.length bytes @?= 16
      ]
`
		if !strings.Contains(smokeStr, "import Polytropos.Plugin.MergeMorph") {
			smokeStr = strings.Replace(smokeStr, "import Polytropos\n", "import Polytropos\nimport Polytropos.Plugin.MergeMorph\nimport qualified Data.ByteString as BS\n", 1)
		}
		smokeStr = strings.Replace(smokeStr, "      ]\n  ]\n\ncheckGhcDiag", "      ]"+testSnippet+"  ]\n\ncheckGhcDiag", 1)
		if err := os.WriteFile(smokePath, []byte(smokeStr), 0644); err != nil {
			fmt.Fprintf(os.Stderr, "failed to write %s: %v\n", smokePath, err)
			os.Exit(1)
		}
		fmt.Printf("  [+] Updated %s (added Plugin MergeMorph test)\n", smokePath)
	}

	fmt.Println("=== [TP-POLY-MERGE-001B Task Runner Finished] ===")
}
