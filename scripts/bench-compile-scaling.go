// Package main implements compile-time scaling microbenchmarks for Polytropos records.
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// generateRecordModule generates a Haskell source module with an N-field Polytropos record.
func generateRecordModule(modName string, n int) string {
	var sb strings.Builder
	sb.WriteString("{-# LANGUAGE DataKinds #-}\n")
	sb.WriteString("{-# LANGUAGE OverloadedRecordDot #-}\n")
	sb.WriteString("{-# LANGUAGE TypeOperators #-}\n")
	sb.WriteString("{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}\n")
	sb.WriteString(fmt.Sprintf("module %s where\n\n", modName))
	sb.WriteString("import Polytropos\n\n")

	// Define type alias
	sb.WriteString(fmt.Sprintf("type Rec%d = Record '[", n))
	for i := 0; i < n; i++ {
		if i > 0 {
			sb.WriteString(", ")
		}
		sb.WriteString(fmt.Sprintf("\"f%d\" ':= Int", i))
	}
	sb.WriteString("]\n\n")

	// Define value
	sb.WriteString(fmt.Sprintf("val%d :: Rec%d\n", n, n))
	sb.WriteString(fmt.Sprintf("val%d = REC\n  { ", n))
	for i := 0; i < n; i++ {
		if i > 0 {
			sb.WriteString("  , ")
		}
		sb.WriteString(fmt.Sprintf("f%d = %d :: Int\n", i, i))
	}
	sb.WriteString("  }\n\n")

	// Define accessor function
	sb.WriteString(fmt.Sprintf("sum%d :: Rec%d -> Int\n", n, n))
	sb.WriteString(fmt.Sprintf("sum%d r = ", n))
	for i := 0; i < n; i++ {
		if i > 0 {
			sb.WriteString(" + ")
		}
		sb.WriteString(fmt.Sprintf("r.f%d", i))
	}
	sb.WriteString("\n")

	return sb.String()
}

func measureCompileTime(repoDir string, arity int) (int64, error) {
	tmpDir, err := os.MkdirTemp("", fmt.Sprintf("poly-scale-%d-*", arity))
	if err != nil {
		return 0, fmt.Errorf("failed to create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	modName := fmt.Sprintf("ScaleN%d", arity)
	srcFile := filepath.Join(tmpDir, modName+".hs")
	content := generateRecordModule(modName, arity)
	if err := os.WriteFile(srcFile, []byte(content), 0644); err != nil {
		return 0, fmt.Errorf("failed to write module %s: %w", srcFile, err)
	}

	start := time.Now()
	cmd := exec.Command("cabal", "--project-dir="+repoDir, "exec", "--", "ghc",
		"-O1", "-fforce-recomp", "-fno-code", "-package", "polytropos-core", "-package", "polytropos-plugin",
		"-fplugin=Polytropos.Plugin", srcFile)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return 0, fmt.Errorf("ghc compilation failed for N=%d: %v\nstderr: %s", arity, err, stderr.String())
	}
	elapsed := time.Since(start).Milliseconds()
	return elapsed, nil
}

func main() {
	repoDir := "."
	if len(os.Args) > 1 {
		repoDir = os.Args[1]
	}

	arities := []int{16, 32, 64, 128}
	fmt.Println("| Arity (N Fields) | Compile Wall-Time (ms) | Scaling Ratio vs N=16 |")
	fmt.Println("| :--- | :--- | :--- |")

	var baselineMs int64 = 1
	for idx, n := range arities {
		ms, err := measureCompileTime(repoDir, n)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error measuring N=%d: %v\n", n, err)
			continue
		}
		if idx == 0 {
			baselineMs = ms
			if baselineMs <= 0 {
				baselineMs = 1
			}
		}
		ratio := float64(ms) / float64(baselineMs)
		fmt.Printf("| N = %-4d | %8d ms | %6.2fx |\n", n, ms, ratio)
	}
}
